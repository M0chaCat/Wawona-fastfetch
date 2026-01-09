// WawonaStartupManager.m - Compositor startup management implementation
// Extracted from WawonaCompositor.m for better organization

#import "WawonaStartupManager.h"
#import "../compositor_implementations/wayland_compositor.h"
#include "../compositor_implementations/wayland_compositor.h"
#import "../compositor_implementations/wayland_data_device_manager.h"
#import "../compositor_implementations/wayland_output.h"
#import "../compositor_implementations/wayland_shm.h"
#import "../compositor_implementations/wayland_subcompositor.h"
#import "../input/input_handler.h"
#import "../input/wayland_seat.h"
#import "../logging/logging.h"
#import "WawonaCompositor.h"
#import "WawonaDisplayLinkManager.h"
#import "WawonaEventLoopManager.h"
#import "WawonaProtocolSetup.h"
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import "WawonaCompositorView_ios.h"
#else
#import "WawonaCompositorView_macos.h"
#endif

extern WawonaCompositor *g_wl_compositor_instance;

@implementation WawonaStartupManager {
  WawonaCompositor *_compositor;
}

- (instancetype)initWithCompositor:(WawonaCompositor *)compositor {
  self = [super init];
  if (self) {
    _compositor = compositor;
  }
  return self;
}

- (BOOL)start {
  init_compositor_logging();
  NSLog(@"✅ Starting compositor backend...");
  log_printf("COMPOSITOR", "Starting compositor backend...\n");

  // Create Wayland protocol implementations
  // These globals are advertised to clients and enable EGL platform extension
  // support Clients querying the registry will see wl_compositor, which
  // allows them to create EGL surfaces using
  // eglCreatePlatformWindowSurfaceEXT with Wayland surfaces
  _compositor.compositor = wl_compositor_create(_compositor.display);
  if (!_compositor.compositor) {
    NSLog(@"❌ Failed to create wl_compositor");
    return NO;
  }
  NSLog(@"   ✓ wl_compositor created (supports EGL platform extensions)");

  // Set up render callback for immediate rendering on commit
  g_wl_compositor_instance = _compositor;
  // Functions defined in WawonaCompositor.m
  extern void render_surface_callback(struct wl_surface_impl * surface);
  extern void wl_compositor_set_render_callback(
      struct wl_compositor_impl * compositor,
      wl_surface_render_callback_t callback);
  extern void wl_compositor_set_title_update_callback(
      struct wl_compositor_impl * compositor,
      wl_title_update_callback_t callback);
  extern void wl_compositor_set_frame_callback_requested(
      struct wl_compositor_impl * compositor,
      wl_frame_callback_requested_t callback);
  extern void wawona_compositor_update_title(struct wl_client * client);
  extern void wawona_frame_callback_requested(void);

  wl_compositor_set_render_callback(_compositor.compositor,
                                    render_surface_callback);
  wl_compositor_set_title_update_callback(_compositor.compositor,
                                          wawona_compositor_update_title);
  wl_compositor_set_frame_callback_requested(_compositor.compositor,
                                             wawona_frame_callback_requested);

  // Get window size for output
  // CRITICAL: Use actual CompositorView bounds (already constrained to safe
  // area if respecting) This ensures proper scaling from the start
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  CGFloat scale = [UIScreen mainScreen].scale;
  if (scale <= 0) {
    scale = 1.0; // Fallback to 1x if scale is invalid
  }

  // Find CompositorView to get actual rendering area size
  UIView *containerView = _compositor.window.rootViewController.view;
  CompositorView *compositorView = nil;
  for (UIView *subview in containerView.subviews) {
    if ([subview isKindOfClass:[CompositorView class]]) {
      compositorView = (CompositorView *)subview;
      break;
    }
  }
  if (!compositorView && [containerView isKindOfClass:[CompositorView class]]) {
    compositorView = (CompositorView *)containerView;
  }

  CGRect frame;
  if (compositorView) {
    [compositorView setNeedsLayout];
    [compositorView layoutIfNeeded];
    frame = compositorView.bounds;
  } else {
    frame = _compositor.window.bounds;
  }
#else
  NSRect frame = [_compositor.window.contentView bounds];
  CGFloat scale = _compositor.window.backingScaleFactor;
  if (scale <= 0) {
    scale = 1.0;
  }
#endif

  // Calculate pixel dimensions: points * scale = pixels
  int32_t pixelWidth = (int32_t)round(frame.size.width * scale);
  int32_t pixelHeight = (int32_t)round(frame.size.height * scale);
  int32_t scaleInt = (int32_t)scale;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  _compositor.output = wl_output_create(_compositor.display, pixelWidth,
                                        pixelHeight, scaleInt, "iOS");
#else
  _compositor.output = wl_output_create(_compositor.display, pixelWidth,
                                        pixelHeight, scaleInt, "macOS");
#endif
  if (!_compositor.output) {
    NSLog(@"❌ Failed to create wl_output");
    return NO;
  }
  NSLog(@"   ✓ wl_output created: %.0fx%.0f points @ %.0fx scale = %dx%d "
        @"pixels",
        frame.size.width, frame.size.height, scale, pixelWidth, pixelHeight);

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  if (compositorView) {
    [_compositor updateOutputSize:compositorView.bounds.size];
  } else {
    [_compositor updateOutputSize:frame.size];
  }
#else
  [_compositor updateOutputSize:frame.size];
#endif

  _compositor.seat = wl_seat_create(_compositor.display);
  if (!_compositor.seat) {
    NSLog(@"❌ Failed to create wl_seat");
    return NO;
  }
  NSLog(@"   ✓ wl_seat created");

  // Set seat in compositor for focus management
  // wl_compositor_set_seat is defined in WawonaCompositor.m
  extern void wl_compositor_set_seat(struct wl_seat_impl * seat);
  wl_compositor_set_seat(_compositor.seat);

  _compositor.shm = wl_shm_create(_compositor.display);
  if (!_compositor.shm) {
    NSLog(@"❌ Failed to create wl_shm");
    return NO;
  }
  NSLog(@"   ✓ wl_shm created");

  _compositor.subcompositor = wl_subcompositor_create(_compositor.display);
  if (!_compositor.subcompositor) {
    NSLog(@"❌ Failed to create wl_subcompositor");
    return NO;
  }
  NSLog(@"   ✓ wl_subcompositor created");

  _compositor.data_device_manager =
      wl_data_device_manager_create(_compositor.display);
  if (!_compositor.data_device_manager) {
    NSLog(@"❌ Failed to create wl_data_device_manager");
    return NO;
  }
  NSLog(@"   ✓ wl_data_device_manager created");

  // Setup Wayland protocols
  WawonaProtocolSetup *protocolSetup =
      [[WawonaProtocolSetup alloc] initWithCompositor:_compositor];
  if (![protocolSetup setupProtocols]) {
    return NO;
  }

  // Start dedicated Wayland event processing thread
  WawonaEventLoopManager *eventLoopManager =
      [[WawonaEventLoopManager alloc] initWithCompositor:_compositor];
  if ([eventLoopManager setupEventLoop]) {
    [eventLoopManager startEventThread];
    _compositor.eventLoopManager = eventLoopManager; // Store reference
  }

  // Set up frame rendering using DisplayLinkManager
  WawonaDisplayLinkManager *displayLinkManager =
      [[WawonaDisplayLinkManager alloc] initWithCompositor:_compositor];
  [displayLinkManager setupDisplayLink];

  // Add a heartbeat timer to show compositor is alive (every 5 seconds)
  static int heartbeat_count = 0;
  [NSTimer
      scheduledTimerWithTimeInterval:5.0
                             repeats:YES
                               block:^(NSTimer *timer) {
                                 heartbeat_count++;
                                 log_printf(
                                     "[COMPOSITOR] ",
                                     "💓 Compositor heartbeat #%d - window "
                                     "visible, event thread running\n",
                                     heartbeat_count);
                                 // Stop after 12 heartbeats (1 minute) to
                                 // reduce log spam
                                 if (heartbeat_count >= 12) {
                                   [timer invalidate];
                                   log_printf("COMPOSITOR",
                                              "💓 Heartbeat logging stopped "
                                              "(compositor still running)\n");
                                 }
                               }];

  // Set up input handling
  // Create InputHandler and set it up
  if (_compositor.seat && _compositor.window) {
    _compositor.inputHandler =
        [[InputHandler alloc] initWithSeat:_compositor.seat
                                    window:_compositor.window
                                compositor:_compositor];
    [_compositor.inputHandler setupInputHandling];

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    // iOS: Set input handler reference in compositor view
    UIView *contentView = _compositor.window.rootViewController.view;
    if ([contentView isKindOfClass:[CompositorView class]]) {
      ((CompositorView *)contentView).inputHandler = _compositor.inputHandler;
    }
#else
    // macOS: Set input handler reference in compositor view
    NSView *contentView = _compositor.window.contentView;
    if ([contentView isKindOfClass:[CompositorView class]]) {
      CompositorView *compositorView = (CompositorView *)contentView;
      compositorView.inputHandler = _compositor.inputHandler;
    }
    [_compositor.window setAcceptsMouseMovedEvents:YES];
    NSLog(@"   ✓ Input handling set up (macOS)");
#endif
  }

  NSLog(@"✅ Compositor backend started");
  NSLog(@"   Wayland event processing thread active");
  NSLog(@"   Input handling active");

  return YES;
}

@end
