#import "WawonaCompositor.h"
#import "../ui/Settings/WawonaPreferencesManager.h"
#import "WawonaBackendManager.h"
#import "WawonaClientManager.h"
#import "WawonaDisplayLinkManager.h"
#import "WawonaEventLoopManager.h"
#import "WawonaFrameCallbackManager.h"
#import "WawonaProtocolSetup.h"
#import "WawonaRenderManager.h"
#import "WawonaShutdownManager.h"
#import "WawonaStartupManager.h"
#import "WawonaSurfaceManager.h"
#import "WawonaWindowManager.h"
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import "WawonaCompositorView_ios.h"
#else
#import "WawonaCompositorView_macos.h"
#import "WawonaCompositor_macos.h"
#import "WawonaWindowLifecycle_macos.h"
#endif
#import "../rendering/renderer_macos.h"
#include "WawonaSettings.h"
#include <wayland-server-core.h>

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
@interface NSWindow (Private)
- (void)performWindowResizeWithEdge:(NSInteger)edge event:(NSEvent *)event;
- (void)performWindowDragWithEvent:(NSEvent *)event;
@end

@interface WawonaWindow : NSWindow
@end

@implementation WawonaWindow
- (BOOL)canBecomeKeyWindow {
  return YES;
}
- (BOOL)canBecomeMainWindow {
  return YES;
}
@end
#endif

#ifdef __APPLE__
#import <CoreVideo/CoreVideo.h>
#import <QuartzCore/QuartzCore.h>
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import <libproc.h>
#endif
#endif
#include "../compositor_implementations/wayland_fullscreen_shell.h"
#include "../compositor_implementations/wayland_linux_dmabuf.h"
#include "../logging/logging.h"
#include <arpa/inet.h>
#include <assert.h>
#ifdef __APPLE__
#include <dispatch/dispatch.h>
#endif
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
// --- Forward Declarations ---

int macos_compositor_get_client_count(void) {
  if (g_wl_compositor_instance) {
    return (int)g_wl_compositor_instance.connectedClientCount;
  }
  return 0;
}

bool macos_compositor_multiple_clients_enabled(void) {
#ifdef __APPLE__
  @try {
    WawonaPreferencesManager *prefsManager =
        [WawonaPreferencesManager sharedManager];
    if (prefsManager) {
      return [prefsManager multipleClientsEnabled];
    }
  } @catch (NSException *exception) {
    NSLog(@"⚠️ Failed to read multipleClientsEnabled preference: %@", exception);
  }
#else
  return WawonaSettings_GetMultipleClientsEnabled();
#endif
  return false;
}

#ifdef __APPLE__
WawonaCompositor *g_wl_compositor_instance;
#else
struct WawonaCompositor {
  struct wl_display *display;
  int tcp_listen_fd;
  int connectedClientCount;
  // Add other fields as needed
};
static struct WawonaCompositor *g_wl_compositor_instance;
#endif

// TCP accept handlers and event loop callbacks moved to
// WawonaEventLoopManager.m

void wl_compositor_set_render_callback(struct wl_compositor_impl *compositor,
                                       wl_surface_render_callback_t callback) {
  if (compositor)
    compositor->render_callback = callback;
}

void wl_compositor_set_title_update_callback(
    struct wl_compositor_impl *compositor,
    wl_title_update_callback_t callback) {
  if (compositor)
    compositor->update_title_callback = callback;
}

void wl_compositor_set_frame_callback_requested(
    struct wl_compositor_impl *compositor,
    wl_frame_callback_requested_t callback) {
  if (compositor)
    compositor->frame_callback_requested = callback;
}

void wl_compositor_set_seat(struct wl_seat_impl *seat) { (void)seat; }

static volatile int g_wl_surface_list_lock = 0;
void wl_compositor_lock_surfaces(void) {
  while (__atomic_test_and_set(&g_wl_surface_list_lock, __ATOMIC_ACQUIRE)) {
  }
}
void wl_compositor_unlock_surfaces(void) {
  __atomic_clear(&g_wl_surface_list_lock, __ATOMIC_RELEASE);
}

void wl_compositor_for_each_surface(wl_surface_iterator_func_t iterator,
                                    void *data) {
  wl_compositor_lock_surfaces();
  struct wl_surface_impl *s = g_wl_surface_list;
  while (s) {
    struct wl_surface_impl *next = s->next;
    if (s->resource) {
      iterator(s, data);
    }
    s = next;
  }
  wl_compositor_unlock_surfaces();
}

struct wl_surface_impl *wl_surface_from_resource(struct wl_resource *resource) {
  if (wl_resource_instance_of(resource, &wl_surface_interface,
                              &surface_interface)) {
    return wl_resource_get_user_data(resource);
  }
  return NULL;
}

void wl_surface_damage(struct wl_surface_impl *surface, int32_t x, int32_t y,
                       int32_t width, int32_t height) {
  (void)surface;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
  // Internal damage
}

void wl_surface_commit(struct wl_surface_impl *surface) {
  // Internal commit
  surface->committed = true;
}

void wl_surface_attach_buffer(struct wl_surface_impl *surface,
                              struct wl_resource *buffer) {
  surface->buffer_resource = buffer;
}

void *wl_buffer_get_shm_data(struct wl_resource *buffer, int32_t *width,
                             int32_t *height, int32_t *stride) {
  struct wl_shm_buffer *shm_buffer = wl_shm_buffer_get(buffer);
  if (!shm_buffer)
    return NULL;

  if (width)
    *width = wl_shm_buffer_get_width(shm_buffer);
  if (height)
    *height = wl_shm_buffer_get_height(shm_buffer);
  if (stride)
    *stride = wl_shm_buffer_get_stride(shm_buffer);

  wl_shm_buffer_begin_access(shm_buffer);
  return wl_shm_buffer_get_data(shm_buffer);
}

void wl_buffer_end_shm_access(struct wl_resource *buffer) {
  struct wl_shm_buffer *shm_buffer = wl_shm_buffer_get(buffer);
  if (shm_buffer) {
    wl_shm_buffer_end_access(shm_buffer);
  }
}

// Update compositor_create_surface to use g_wl_surface_list
// Re-implementing parts of compositor_create_surface here to ensure correct
// linking (Code above was simplified)
#include "metal_waypipe.h"
#include "wayland_drm.h"
// Removed: wayland_gtk_shell.h (dead code - stubs in protocol_stubs.c)
#include "wayland_idle_inhibit.h"
#include "wayland_idle_manager.h"
#include "wayland_keyboard_shortcuts.h"
#include "wayland_linux_dmabuf.h"
// Removed: wayland_plasma_shell.h (dead code - stubs in protocol_stubs.c)
#include "wayland_pointer_constraints.h"
#include "wayland_pointer_gestures.h"
#include "wayland_primary_selection.h"
#include "wayland_protocol_stubs.h"
// Removed: wayland_qt_extensions.h (dead code - stubs in protocol_stubs.c)
#include "wayland_relative_pointer.h"
#include "wayland_screencopy.h"
#include "wayland_shell.h"
#include "wayland_tablet.h"
#include "wayland_viewporter.h"
#include "xdg-shell-protocol.h"
#include "xdg_shell.h"

// CompositorView implementation moved to WawonaCompositorView.m

// Static reference to compositor instance for C callback
WawonaCompositor *g_wl_compositor_instance = NULL;

// Frame callback timer functions moved to WawonaFrameCallbackManager.m
// C function for frame callback requested callback - now delegates to
// FrameCallbackManager
static void wawona_compositor_frame_callback_requested(void) {
  wawona_frame_callback_requested();
}

// C function to update window title when focus changes
void wawona_compositor_update_title(struct wl_client *client) {
  if (g_wl_compositor_instance) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [g_wl_compositor_instance updateWindowTitleForClient:client];
    });
  }
}

// wawona_compositor_detect_full_compositor moved to WawonaBackendManager.m

#import "WawonaSettings.h"

// Rendering callbacks are now in src/rendering/renderer_macos_helpers.m
// C wrapper function for render callback
void render_surface_callback(struct wl_surface_impl *surface) {
  // Delegate to renderer_macos_helpers.m
  wawona_render_surface_callback(surface);
}

// Helper function to find the appropriate renderer for a surface
static id<RenderingBackend>
findRendererForSurface(struct wl_surface_impl *surface) {
  // Delegate to renderer_macos_helpers.m
  return wawona_find_renderer_for_surface(surface);
}

// Helper function to render surface immediately on main thread
static void renderSurfaceImmediate(struct wl_surface_impl *surface) {
  // Delegate to renderer_macos_helpers.m
  wawona_render_surface_immediate(surface);
}

// C wrapper function to remove surface from renderer's internal tracking
// NOTE: The surface must already be removed from g_wl_surface_list before
// calling this! This is ONLY called from the main thread to avoid deadlocks
// and use-after-free issues.
void remove_surface_from_renderer(struct wl_surface_impl *surface) {
  if (!g_wl_compositor_instance) {
    return;
  }

  // CRITICAL: Only remove from renderer if we're on the main thread.
  // If called from the event thread (surface_destroy_resource), we skip this.
  //
  // Why this is safe:
  // 1. The surface has already been removed from g_wl_surface_list
  // 2. The renderer iterates g_wl_surface_list in
  // drawSurfacesInRect/renderFrame
  // 3. Since the surface is no longer in g_wl_surface_list, it won't be
  // rendered
  // 4. The renderer's surfaceImages/surfaceTextures dictionary may have a
  // stale
  //    entry, but it won't be accessed because the surface isn't in
  //    g_wl_surface_list
  // 5. The stale entry will be cleaned up when renderSurface detects
  // surface->resource is NULL
  //
  // Why we can't use dispatch_sync: causes deadlock when main thread is in
  // renderFrame Why we can't use dispatch_async: surface is freed before
  // block runs = use-after-free

  if ([NSThread isMainThread]) {
    // Remove from renderer if active
    if (g_wl_compositor_instance.renderingBackend &&
        [g_wl_compositor_instance.renderingBackend
            respondsToSelector:@selector(removeSurface:)]) {
      [g_wl_compositor_instance.renderingBackend removeSurface:surface];
    }
  }
  // If not on main thread, skip - the renderer will clean up stale entries
  // naturally
}

// macos_compositor_check_and_hide_window_if_needed moved to
// WawonaClientManager.m

@implementation WawonaCompositor

- (void)runBlock:(void (^)(void))block {
  if (block)
    block();
}

- (void)dispatchToEventThread:(void (^)(void))block {
  if ([NSThread currentThread] == self.eventThread) {
    block();
  } else {
    [self performSelector:@selector(runBlock:)
                 onThread:self.eventThread
               withObject:[block copy]
            waitUntilDone:NO];
  }
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (instancetype)initWithDisplay:(struct wl_display *)display
                         window:(UIWindow *)window {
#else
- (instancetype)initWithDisplay:(struct wl_display *)display
                         window:(NSWindow *)window {
#endif
  self = [super init];
  if (self) {
    _display = display;
    _window = window;
    _eventLoop = wl_display_get_event_loop(display);
    _shouldStopEventThread = NO;
    _frame_callback_source = NULL;
    _pending_resize_width = 0;
    _pending_resize_height = 0;
    _needs_resize_configure = NO;
    _windowShown =
        NO; // Track if window has been shown (delayed until first client)
    _isFullscreen = NO; // Track if window is in fullscreen mode
    _fullscreenExitTimer =
        nil; // Timer to exit fullscreen after client disconnects
    _connectedClientCount = 0; // Track number of connected clients
    _windowToToplevelMap = [[NSMutableDictionary alloc] init];
    _mapLock = [[NSRecursiveLock alloc] init];
    _nativeWindows = [[NSMutableArray alloc] init];
    _toplevelToRendererMap = [[NSMutableDictionary alloc] init];
    _decoration_manager = NULL;

    // Register for Force SSD change notifications for hot-reload
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(handleForceSSDChanged:)
               name:kWawonaForceSSDChangedNotification
             object:nil];

    // Create custom view that accepts first responder and handles drawing
    CompositorView *compositorView;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // On iOS, check if window already has a rootViewController (set in
    // main.m) If it does, use that view; otherwise create a new one
    UIView *containerView = nil;
    if (window.rootViewController && window.rootViewController.view) {
      // Use existing root view controller's view
      containerView = window.rootViewController.view;
      // Ensure it fills the window properly
      containerView.autoresizingMask =
          UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      // Force layout to ensure bounds are correct
      [containerView setNeedsLayout];
      [containerView layoutIfNeeded];
      NSLog(@"✅ Using existing root view controller for compositor view "
            @"(bounds=%@)",
            NSStringFromCGRect(containerView.bounds));
    } else {
      // Create new root view controller (fallback)
      UIViewController *rootVC = [[UIViewController alloc] init];
      // Don't manually set frame - let UIKit handle it with proper
      // autoresizing
      containerView = rootVC.view;
      containerView.backgroundColor =
          [UIColor blackColor]; // Black background for unsafe areas
      // Ensure the view properly fills the window using autoresizing masks
      containerView.autoresizingMask =
          UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      window.rootViewController = rootVC;
      // Force layout to ensure bounds are correct
      [containerView setNeedsLayout];
      [containerView layoutIfNeeded];
      NSLog(@"✅ Created new root view controller for compositor view "
            @"(bounds=%@)",
            NSStringFromCGRect(containerView.bounds));
    }

    // Create CompositorView as a subview with flexible sizing (full screen by
    // default) Layout will be handled in CompositorView's layoutSubviews to
    // respect safe area setting
    // Use window bounds instead of containerView.bounds since containerView
    // might not be laid out yet (bounds could be CGRectZero or incorrect)
    CGRect initialFrame = window.bounds;
    compositorView = [[CompositorView alloc] initWithFrame:initialFrame];
    compositorView.autoresizingMask =
        UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    compositorView.backgroundColor = [UIColor clearColor];
    [containerView addSubview:compositorView];

    NSLog(@"🔵 CompositorView initialized: window.bounds=%@, "
          @"compositorView.frame=%@",
          NSStringFromCGRect(window.bounds),
          NSStringFromCGRect(compositorView.frame));

    // Note: Safe area constraints are now handled dynamically in
    // CompositorView layoutSubviews

#else
    NSRect contentRect = NSMakeRect(0, 0, 800, 600);
    compositorView = [[CompositorView alloc] initWithFrame:contentRect];
    [window setContentView:compositorView];
    [window setDelegate:self];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(windowDidEnterFullScreen:)
               name:NSWindowDidEnterFullScreenNotification
             object:window];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(windowDidExitFullScreen:)
               name:NSWindowDidExitFullScreenNotification
             object:window];
    [window setAcceptsMouseMovedEvents:YES];
    [window setCollectionBehavior:NSWindowCollectionBehaviorDefault];
    [window setStyleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                          NSWindowStyleMaskResizable |
                          NSWindowStyleMaskMiniaturizable)];
    [window makeFirstResponder:compositorView];
#endif

    self.mainCompositorView = compositorView;

    // Force Metal renderer to avoid EGL/GLX issues - use Vulkan-only path
    // Create Metal renderer directly to bypass SurfaceRenderer buffer handling
    // issues
    id<RenderingBackend> renderer =
        [RenderingBackendFactory createBackend:RENDERING_BACKEND_METAL
                                      withView:compositorView];
    _renderingBackend = renderer;
    _backendType = 1; // RENDERING_BACKEND_METAL

    // Set renderer reference in view for drawRect: calls
    compositorView.renderer = renderer;

    // Store global reference for C callbacks (MUST be set before clients
    // connect)
    g_wl_compositor_instance = self;
    NSLog(@"   Global compositor instance set for client detection: %p",
          (__bridge void *)self);

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    NSLog(@"🚀 iOS Wayland Compositor initialized");
#else
    NSLog(@"🚀 macOS Wayland Compositor initialized");
    NSLog(@"   Window: %@", window.title);
#endif
    NSLog(@"   Display: %p", (void *)display);
    NSLog(@"   Initial backend: Cocoa (will auto-switch to Metal for full "
          @"compositors)");
  }
  return self;
}

// Implementation of wayland frame callback functions

- (void)setupInputHandling {
  if (_seat && _window) {
    _inputHandler = [[InputHandler alloc] initWithSeat:_seat
                                                window:_window
                                            compositor:self];
    [_inputHandler setupInputHandling];

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Set input handler reference in compositor view
    UIView *contentView = _window.rootViewController.view;
    if ([contentView isKindOfClass:[CompositorView class]]) {
      ((CompositorView *)contentView).inputHandler = _inputHandler;
    }
    // iOS: Touch events are handled via UIKit gesture recognizers
    // Keyboard events are handled via UIResponder chain
#else
    // macOS: Set input handler reference in compositor view for keyboard
    // event handling
    NSView *contentView = _window.contentView;
    if ([contentView isKindOfClass:[CompositorView class]]) {
      CompositorView *compositorView = (CompositorView *)contentView;
      compositorView.inputHandler = _inputHandler;
    }

    // Mouse events are now handled via NSResponder methods in CompositorView
    // (mouseMoved, mouseDown, etc.) which forward to inputHandler
    // We still set acceptsMouseMovedEvents on the window
    [_window setAcceptsMouseMovedEvents:YES];

    NSLog(@"   ✓ Input handling set up (macOS)");
#endif
  }
}

- (BOOL)start {
  if (!_startupManager) {
    _startupManager = [[WawonaStartupManager alloc] initWithCompositor:self];
  }
  return [_startupManager start];
}

- (BOOL)processWaylandEvents {
  // DEPRECATED: Event processing is now handled by the dedicated event thread
  // This method is kept for compatibility but should not be used
  // The event thread handles all Wayland event processing with blocking
  // dispatch
  return NO;
}

// DisplayLink callback - called at display refresh rate
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)displayLinkCallback:(CADisplayLink *)displayLink {
  (void)displayLink;
  [self renderFrame];
}
#else
static CVReturn
displayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow,
                    const CVTimeStamp *inOutputTime, CVOptionFlags flagsIn,
                    CVOptionFlags *flagsOut, void *displayLinkContext) {
  (void)displayLink;
  (void)inNow;
  (void)inOutputTime;
  (void)flagsIn;
  (void)flagsOut;
  WawonaCompositor *compositor =
      (__bridge WawonaCompositor *)displayLinkContext;
  if (compositor) {
    // Render on main thread
    dispatch_async(dispatch_get_main_queue(), ^{
      [compositor renderFrame];
    });
  }
  return kCVReturnSuccess;
}
#endif

// Show and size window when first client connects
- (void)showAndSizeWindowForFirstClient:(int32_t)width height:(int32_t)height {
  if (_windowShown) {
    return; // Already shown
  }

  if (!_windowManager) {
    _windowManager = [[WawonaWindowManager alloc] initWithCompositor:self];
  }
  [_windowManager showAndSizeWindowForFirstClient:width height:height];
}

// Update output size and notify clients
- (void)updateOutputSize:(CGSize)size {
  if (!_windowManager) {
    _windowManager = [[WawonaWindowManager alloc] initWithCompositor:self];
  }
  [_windowManager updateOutputSize:size];
}

- (void)handleForceSSDChanged:(NSNotification *)notification {
  if (self.decoration_manager) {
    log_printf("COMPOSITOR",
               "ℹ️ Force SSD setting changed, triggering hot-reload\n");
    // This function iterates decoration list and sends configure events
    // and calls macos_update_toplevel_decoration_mode
    wl_decoration_hot_reload(self.decoration_manager);
  }
}

// windowShouldClose moved to WawonaCompositor_macos.m

// Window delegate methods moved to WawonaCompositor_macos.m

// DEPRECATED: This function is no longer used - it caused infinite loops
// Frame callbacks are now handled entirely by the timer mechanism
static void send_frame_callbacks_timer_idle(void *data) {
  // Do nothing - this function should never be called
  // If it is called, it means there's a bug somewhere adding idle callbacks
  (void)data;
  log_printf("COMPOSITOR", "ERROR: send_frame_callbacks_timer_idle called - "
                           "this should not happen!\n");
}

// Frame callback timer functions moved to WawonaFrameCallbackManager.m

- (void)sendFrameCallbacksImmediately {
  // Force immediate flush of input events and frame callback dispatch
  // This allows clients to receive keyboard events and render immediately
  // NOTE: Must be called from main thread, but the callback will run on event
  // thread
  wawona_send_frame_callbacks_immediately(self);
}

// Rendering logic moved to WawonaRenderManager.m
- (void)renderFrame {
  if (!_renderManager) {
    _renderManager = [[WawonaRenderManager alloc] initWithCompositor:self];
  }
  [_renderManager renderFrame];
}

// Shutdown logic moved to WawonaShutdownManager.m
- (void)stop {
  if (!_shutdownManager) {
    _shutdownManager = [[WawonaShutdownManager alloc] initWithCompositor:self];
  }
  [_shutdownManager stop];
}

- (void)switchToMetalBackend {
  // Switch from Cocoa to Metal rendering backend for full compositors
  if (_backendType == 1) { // Already using Metal
    return;
  }

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  if (!WawonaSettings_GetUseMetal4ForNested()) {
    NSLog(@"[BACKEND] Metal renderer requested but disabled in settings "
          @"(Render with Metal4)");
    return;
  }
#endif

  NSLog(@"🔄 Switching to Metal rendering backend for full compositor support");

  // Check Safe Area setting (used throughout this function)
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  BOOL respectSafeArea =
      [[NSUserDefaults standardUserDefaults] boolForKey:@"RespectSafeArea"];
  if ([[NSUserDefaults standardUserDefaults] objectForKey:@"RespectSafeArea"] ==
      nil) {
    respectSafeArea = YES;
  }
#else
  BOOL respectSafeArea = NO;
#endif

  // Get the compositor view
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  UIView *contentView = _window.rootViewController.view;
  CGRect windowBounds;
#else
  NSView *contentView = _window.contentView;
  NSRect windowBounds;
#endif
  if (![contentView isKindOfClass:[CompositorView class]]) {
    NSLog(@"⚠️ Content view is not CompositorView, cannot switch to Metal");
    return;
  }

  CompositorView *compositorView = (CompositorView *)contentView;

  // CRITICAL: Ensure CompositorView is sized to safe area before creating
  // Metal view
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [compositorView setNeedsLayout];
  [compositorView layoutIfNeeded];

  // Update CompositorView frame to safe area if respecting

  if (respectSafeArea) {
    CGRect windowBoundsLocal = _window.bounds;
    CGRect safeAreaFrame = windowBoundsLocal;

    if (@available(iOS 11.0, *)) {
      UILayoutGuide *safeArea = _window.safeAreaLayoutGuide;
      safeAreaFrame = safeArea.layoutFrame;
      if (CGRectIsEmpty(safeAreaFrame)) {
        UIEdgeInsets insets = compositorView.safeAreaInsets;
        if (insets.top != 0 || insets.left != 0 || insets.bottom != 0 ||
            insets.right != 0) {
          safeAreaFrame = UIEdgeInsetsInsetRect(windowBoundsLocal, insets);
        }
      }
    } else {
      UIEdgeInsets insets = compositorView.safeAreaInsets;
      if (insets.top != 0 || insets.left != 0 || insets.bottom != 0 ||
          insets.right != 0) {
        safeAreaFrame = UIEdgeInsetsInsetRect(windowBoundsLocal, insets);
      }
    }

    compositorView.frame = safeAreaFrame;
    compositorView.autoresizingMask = UIViewAutoresizingNone;
  } else {
    compositorView.frame = _window.bounds;
    compositorView.autoresizingMask =
        (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
  }
#endif

  // Get current window size for Metal view
  // Note: CompositorView bounds will be safe area if respecting, or full
  // window if not
  windowBounds = compositorView.bounds;

  // Metal view should fill CompositorView (which is already sized to safe
  // area if respecting)
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  CGRect initialFrame = compositorView.bounds;
  NSLog(@"🔵 Metal view initial frame (CompositorView bounds): (%.0f, %.0f) "
        @"%.0fx%.0f (safe area: %@)",
        initialFrame.origin.x, initialFrame.origin.y, initialFrame.size.width,
        initialFrame.size.height, respectSafeArea ? @"YES" : @"NO");
#else
  CGRect initialFrame = windowBounds;
#endif

  // Create Metal view with safe area-aware frame
  // Use a custom class that allows window dragging for proper window controls
  Class CompositorMTKViewClass = NSClassFromString(@"CompositorMTKView");
  MTKView *metalView = nil;
  if (CompositorMTKViewClass) {
    metalView = [[CompositorMTKViewClass alloc] initWithFrame:initialFrame];
  } else {
    // Fallback to regular MTKView if custom class not available
    metalView = [[MTKView alloc] initWithFrame:initialFrame];
  }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // CRITICAL: Disable autoresizing when safe area is enabled, otherwise it
  // will override our frame
  if (respectSafeArea) {
    metalView.autoresizingMask = UIViewAutoresizingNone;
  } else {
    metalView.autoresizingMask =
        (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
  }
#else
  metalView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
  // Ensure Metal view is opaque and properly configured
  metalView.wantsLayer = YES;
  metalView.layer.opaque = YES;
  metalView.layerContentsRedrawPolicy =
      NSViewLayerContentsRedrawDuringViewResize;
#endif
  metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
  metalView.clearColor = MTLClearColorMake(0.1, 0.1, 0.2, 1.0);

  // CRITICAL: Don't block mouse events - allow window controls to work
  // The Metal view should not intercept mouse events meant for window
  // controls Note: mouseDownCanMoveWindow is a method, not a property -
  // handled in CompositorView Don't set ignoresMouseEvents - we need to
  // receive events for Wayland clients But ensure the view doesn't block
  // window controls

  // Frame is already set above based on safe area setting
  // metalView.frame = initialFrame; // Already set in initWithFrame

  NSLog(@"   Creating Metal view with frame: %.0fx%.0f at (%.0f, %.0f) (safe "
        @"area: %@)",
        initialFrame.size.width, initialFrame.size.height,
        initialFrame.origin.x, initialFrame.origin.y,
        respectSafeArea ? @"YES" : @"NO");

  // Create Metal renderer
  id<RenderingBackend> metalRenderer =
      [RenderingBackendFactory createBackend:RENDERING_BACKEND_METAL
                                    withView:metalView];
  if (!metalRenderer) {
    NSLog(@"❌ Failed to create Metal renderer");
    return;
  }

  // Add Metal view as subview (on top of Cocoa view for rendering)
  // The Metal view renders content but allows events to pass through to
  // CompositorView
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [compositorView addSubview:metalView];
  compositorView.metalView = metalView;

  // CRITICAL: Update output size after Metal view is added to ensure safe
  // area is respected This will recalculate and reposition the metalView if
  // needed
  [self updateOutputSize:compositorView.bounds.size];

  // iOS: Touch events are handled via UIKit gesture recognizers
  // Re-setup input handling if needed
  if (_inputHandler) {
    [_inputHandler setupInputHandling];
  }
#else
  [compositorView addSubview:metalView positioned:NSWindowAbove relativeTo:nil];
  compositorView.metalView = metalView;

  // Ensure CompositorView remains the responder chain - Metal view just
  // renders This allows CompositorView to handle events while Metal view
  // displays content
  [metalView setNextResponder:compositorView];

  // CRITICAL: Ensure mouse events pass through to CompositorView for tracking
  // areas The Metal view should not block mouse events - they need to reach
  // the tracking area Don't set ignoresMouseEvents - we need events for
  // Wayland clients But ensure the view hierarchy allows events to reach
  // CompositorView's tracking area

  // Update input handler's tracking area to cover the full view including
  // Metal view
  if (_inputHandler) {
    // Remove old tracking area and create new one covering full bounds
    NSView *inputContentView = _window.contentView;
    for (NSTrackingArea *area in [inputContentView trackingAreas]) {
      [inputContentView removeTrackingArea:area];
    }
    // Re-setup input handling with updated tracking area
    [_inputHandler setupInputHandling];
  }
#endif

  // Switch rendering backend
  _renderingBackend = metalRenderer;
  _backendType = 1; // RENDERING_BACKEND_METAL

  // Update render callback to use Metal backend
  // The render_surface_callback will now use the Metal backend

  NSLog(@"✅ Switched to Metal rendering backend");
  NSLog(@"   Metal view frame: %.0fx%.0f", metalView.frame.size.width,
        metalView.frame.size.height);
  NSLog(@"   Window bounds: %.0fx%.0f", windowBounds.size.width,
        windowBounds.size.height);
  NSLog(@"   Metal renderer: %@", metalRenderer);
}

- (void)updateWindowTitleForClient:(struct wl_client *)client {
  if (!_window || !client)
    return;

  NSString *windowTitle = @"Wawona"; // Default title when no clients

  // Try to get the focused surface's toplevel title/app_id
  if (_seat && _seat->focused_surface) {
    struct wl_surface_impl *surface =
        (struct wl_surface_impl *)_seat->focused_surface;
    if (surface && surface->resource) {
      struct wl_client *surface_client =
          wl_resource_get_client(surface->resource);
      if (surface_client == client) {
        // Get the toplevel for this surface
        extern struct xdg_toplevel_impl
            *xdg_surface_get_toplevel_from_wl_surface(struct wl_surface_impl *
                                                      wl_surface);
        struct xdg_toplevel_impl *toplevel =
            xdg_surface_get_toplevel_from_wl_surface(surface);

        if (toplevel) {
          // Prefer title over app_id, fallback to app_id if title is not set
          if (toplevel->title && strlen(toplevel->title) > 0) {
            windowTitle = [NSString stringWithUTF8String:toplevel->title];
          } else if (toplevel->app_id && strlen(toplevel->app_id) > 0) {
            // Use app_id, but make it more readable
            NSString *appId = [NSString stringWithUTF8String:toplevel->app_id];
            // Remove common prefixes like "org.freedesktop." or "com."
            appId =
                [appId stringByReplacingOccurrencesOfString:@"org.freedesktop."
                                                 withString:@""];
            appId = [appId stringByReplacingOccurrencesOfString:@"com."
                                                     withString:@""];
            // Capitalize first letter
            if (appId.length > 0) {
              appId = [[appId substringToIndex:1].uppercaseString
                  stringByAppendingString:[appId substringFromIndex:1]];
            }
            windowTitle = appId;
          }
        }

        // If we still don't have a title, try process name as fallback
        if ([windowTitle isEqualToString:@"Wawona"]) {
          pid_t client_pid = 0;
          uid_t client_uid = 0;
          gid_t client_gid = 0;
          wl_client_get_credentials(client, &client_pid, &client_uid,
                                    &client_gid);

          if (client_pid > 0) {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
            char proc_path[PROC_PIDPATHINFO_MAXSIZE] = {0};
            int ret = proc_pidpath(client_pid, proc_path, sizeof(proc_path));
            if (ret > 0) {
              NSString *processPath = [NSString stringWithUTF8String:proc_path];
#else
            // iOS: Process name detection not available
            NSString *processPath = nil;
            if (0) {
#endif
              NSString *processName = [processPath lastPathComponent];
              // Remove common suffixes and make it look nice
              processName =
                  [processName stringByReplacingOccurrencesOfString:@".exe"
                                                         withString:@""];
              windowTitle = processName;
            }
          }
        }
      }
    }
  }

  // Update window title
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // iOS: Window titles are not displayed in the same way
  (void)windowTitle;
  NSLog(@"[WINDOW] Updated title to: %@", windowTitle);
#else
  // macOS: Update titlebar title
  [_window setTitle:windowTitle];
  NSLog(@"[WINDOW] Updated titlebar title to: %@", windowTitle);
#endif
}

// C function to set CSD mode for a toplevel (hide/show macOS window
// decorations)
void macos_compositor_set_csd_mode_for_toplevel(
    struct xdg_toplevel_impl *toplevel, bool csd) {
  if (!g_wl_compositor_instance || !toplevel) {
    return;
  }
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  (void)csd; // iOS: CSD mode not applicable
#else
  // Dispatch to main thread to update UI
  dispatch_async(dispatch_get_main_queue(), ^{
    NSWindow *window = g_wl_compositor_instance.window;
    if (!window) {
      return;
    }

    // Get current style mask
    NSWindowStyleMask currentStyle = window.styleMask;

    // CRITICAL: Cannot change styleMask while window is in fullscreen - macOS
    // throws exception We'll handle fullscreen titlebar visibility by exiting
    // fullscreen after client disconnect (see
    // macos_compositor_handle_client_disconnect)
    BOOL isFullscreen = g_wl_compositor_instance.isFullscreen;

    // Don't change style mask while in fullscreen - wait for fullscreen to
    // exit first
    if (isFullscreen) {
      NSLog(@"[CSD] Skipping styleMask change - window is in fullscreen (will "
            @"be handled after exit)");
      return;
    }

    if (csd) {
      // CLIENT_SIDE decorations - hide macOS window decorations
      // Remove titlebar, close button, etc. - client will draw its own
      // decorations
      NSWindowStyleMask csdStyle = NSWindowStyleMaskBorderless |
                                   NSWindowStyleMaskResizable |
                                   NSWindowStyleMaskMiniaturizable;
      if (currentStyle != csdStyle) {
        window.styleMask = csdStyle;
        NSLog(@"[CSD] Window decorations hidden for CLIENT_SIDE decoration "
              @"mode");
      }
    } else {
      // SERVER_SIDE decorations - show macOS window decorations
      // Show titlebar, close button, resize controls, etc.
      NSWindowStyleMask gsdStyle =
          (NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
           NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable);
      if (currentStyle != gsdStyle) {
        window.styleMask = gsdStyle;
        NSLog(@"[CSD] Window decorations shown for SERVER_SIDE decoration "
              @"mode");
      }
    }
  });
#endif
}

void wl_compositor_flush_and_trigger_frame(void) {
  if (g_wl_compositor_instance) {
    if (g_wl_compositor_instance.display) {
      wl_display_flush_clients(g_wl_compositor_instance.display);
    }
    [g_wl_compositor_instance sendFrameCallbacksImmediately];
  }
}

// C function to activate/raise the window (called from activation protocol)
void macos_compositor_activate_window(void) {
  if (!g_wl_compositor_instance) {
    return;
  }
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  // Dispatch to main thread to raise window
  dispatch_async(dispatch_get_main_queue(), ^{
    NSWindow *window = g_wl_compositor_instance.window;
    if (!window) {
      return;
    }

    // Raise window to front and make it key
    [window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [window becomeKeyWindow];

    NSLog(@"[ACTIVATION] Window activated and raised to front");
  });
#endif
}

// C function to update toplevel window title
// macos_update_toplevel_title moved to WawonaWindowLifecycle_macos.m

// Client management functions moved to WawonaClientManager.m

// EGL disabled - Vulkan only mode

- (void)dealloc {
  // Remove notification observers
  [[NSNotificationCenter defaultCenter] removeObserver:self];

  // Clean up timer
  if (_fullscreenExitTimer) {
    [_fullscreenExitTimer invalidate];
    _fullscreenExitTimer = nil;
  }

  // Clean up text input manager
  if (_text_input_manager) {
    // Text input manager cleanup is handled by wayland resource destruction
    _text_input_manager = NULL;
  }

  // EGL disabled - no cleanup needed

  [self stop];
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#if !__has_feature(objc_arc)
  [super dealloc];
#endif
#endif
}

// macos_update_toplevel_decoration_mode and macos_create_window_for_toplevel
// moved to WawonaWindowLifecycle_macos.m

@end

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
// WindowDelegate category moved to WawonaCompositor_macos.m
#endif

bool wawona_is_egl_enabled(void) {
  // EGL disabled - Vulkan only mode
  return false;
}

// macOS window lifecycle functions moved to WawonaWindowLifecycle_macos.m
