// WawonaSurfaceManager.m - Simplified Wayland Surface Management
//
// Key Simplifications:
// - Single WawonaWindowContainer manages NSWindow for both CSD and SSD.
// - CSD uses NSWindowStyleMaskBorderless.
// - SSD uses standard titled window mask.
// - Rendering is delegated to WawonaRendererMacOS via layers.
// - Removes complex manual shadow window logic in favor of NSWindow defaults or
// simple layers.

#import "WawonaSurfaceManager.h"
#import "../compositor_implementations/wayland_compositor.h"
#import "../compositor_implementations/xdg_shell.h"
#import "../input/input_handler.h"
#import "../logging/WawonaLog.h"
#include "../logging/logging.h"
#import "../ui/Settings/WawonaPreferencesManager.h"
#import "RenderingBackend.h"
#import "WawonaCompositor.h"
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import "WawonaCompositorView_macos.h"
#import "WawonaWindow.h"
#endif
#import "metal_dmabuf.h"
#include <wayland-server-protocol.h>

extern void xdg_toplevel_send_configure(struct wl_resource *resource,
                                        int32_t width, int32_t height,
                                        struct wl_array *states);
extern void xdg_surface_send_configure(struct wl_resource *resource,
                                       uint32_t serial);

// Constants
const CGFloat kResizeEdgeInset = 5.0;
const CGFloat kResizeCornerSize = 20.0;

//==============================================================================
// MARK: - WawonaSurfaceLayer
//==============================================================================

@implementation WawonaSurfaceLayer

- (instancetype)initWithSurface:(struct wl_surface_impl *)surface {
  self = [super init];
  if (self) {
    _surface = surface;
    _rootLayer = [CALayer layer];
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    _rootLayer.backgroundColor = [UIColor clearColor].CGColor;
#else
    _rootLayer.backgroundColor = [NSColor clearColor].CGColor;
#endif
    _rootLayer.anchorPoint = CGPointZero;

    _contentLayer = [CAMetalLayer layer];
    _contentLayer.device = [[WawonaSurfaceManager sharedManager] metalDevice];
    _contentLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _contentLayer.framebufferOnly = NO;
    _contentLayer.presentsWithTransaction = NO;
    _contentLayer.anchorPoint = CGPointZero;

    [_rootLayer addSublayer:_contentLayer];
  }
  return self;
}

- (void)updateContentWithSize:(CGSize)size {
  self.rootLayer.bounds = CGRectMake(0, 0, size.width, size.height);
  self.contentLayer.bounds = CGRectMake(0, 0, size.width, size.height);
}

- (void)addSubsurfaceLayer:(CALayer *)sublayer atIndex:(NSInteger)index {
  [self.subsurfaceLayers insertObject:sublayer atIndex:index];
  [self.rootLayer addSublayer:sublayer];
}

- (void)removeSubsurfaceLayer:(CALayer *)sublayer {
  [self.subsurfaceLayers removeObject:sublayer];
  [sublayer removeFromSuperlayer];
}

- (void)setNeedsRedisplay {
  [self.contentLayer setNeedsDisplay];
}

@end

//==============================================================================
// MARK: - WawonaWindowContainer
//==============================================================================

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
@interface WawonaWindowContainer () <NSWindowDelegate>
@end
#endif

@implementation WawonaWindowContainer

- (instancetype)initWithToplevel:(struct xdg_toplevel_impl *)toplevel
                  decorationMode:(WawonaDecorationMode)mode
                            size:(CGSize)size {
  self = [super init];
  if (self) {
    _toplevel = toplevel;
    _decorationMode = mode;
    [self createWindowWithSize:size];
  }
  return self;
}

- (void)createWindowWithSize:(CGSize)size {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  // Enforce SSD preference
  if ([[WawonaPreferencesManager sharedManager] forceServerSideDecorations]) {
    self.decorationMode = WawonaDecorationModeSSD;
  }

  NSWindowStyleMask styleMask;
  if (self.decorationMode == WawonaDecorationModeCSD) {
    styleMask = NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable |
                NSWindowStyleMaskMiniaturizable;
  } else {
    styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;
  }

  NSRect contentRect = NSMakeRect(100, 100, size.width, size.height);
  // Use WawonaWindow instead of NSWindow
  self.window = [[WawonaWindow alloc] initWithContentRect:contentRect
                                                styleMask:styleMask
                                                  backing:NSBackingStoreBuffered
                                                    defer:NO];

  if (self.decorationMode == WawonaDecorationModeCSD) {
    self.window.backgroundColor = [NSColor clearColor];
    self.window.opaque = NO;
    self.window.hasShadow = YES;                // Try standard shadow first
    self.window.movableByWindowBackground = NO; // Client handles move
    self.window.titlebarAppearsTransparent = YES;
    self.window.titleVisibility = NSWindowTitleHidden;
  } else {
    // SSD: Use glass background if Tahoe is available
    // SSD: Use glass background (Native macOS 26+)
    self.window.backgroundColor = [NSColor clearColor];
    self.window.opaque = NO;
    self.window.hasShadow = YES;
  }

  self.window.delegate = self;
  self.window.releasedWhenClosed = NO;
  self.window.acceptsMouseMovedEvents = YES;

  // Setup Content View
  self.contentView = [[NSView alloc]
      initWithFrame:[self.window contentRectForFrameRect:self.window.frame]];
  self.contentView.wantsLayer = YES;
  self.window.contentView = self.contentView;
#else
  // iOS Implementation: Simple UIWindow or just a container view
  self.window = [[UIWindow alloc]
      initWithFrame:CGRectMake(0, 0, size.width, size.height)];
  self.window.backgroundColor = [UIColor blackColor];

  self.contentView = [[UIView alloc] initWithFrame:self.window.bounds];
  [self.window addSubview:self.contentView];
#endif

  // Updating native_window on main thread logic is kept here as container
  // creation is effectively tied to window existence.
  if (_toplevel) {
    _toplevel->native_window = (__bridge void *)self.window;
  }
}

// ... (Rest of WawonaWindowContainer implementation remains same, skipping to
// keep context small if possible, but tool needs context. I will assume replace
// works on chunks.) Note: I will only replace the top part of
// WawonaWindowContainer and init logic.

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)replaceContentView:(UIView *)newView {
  if (!newView)
    return;

  if (self.contentView.layer.sublayers.count > 0) {
    for (CALayer *layer in [self.contentView.layer.sublayers copy]) {
      [layer removeFromSuperlayer];
      [newView.layer addSublayer:layer];
    }
  }

  [self.contentView removeFromSuperview];
  [self.window addSubview:newView];
  self.contentView = newView;
}
#else
- (void)replaceContentView:(NSView *)newView {
  if (!newView)
    return;

  // Migrate layers if needed
  if (self.contentView.layer.sublayers.count > 0) {
    newView.wantsLayer = YES;
    for (CALayer *layer in [self.contentView.layer.sublayers copy]) {
      [layer removeFromSuperlayer];
      [newView.layer addSublayer:layer];
    }
  }

  self.window.contentView = newView;
  self.contentView = newView;

  // Ensure layer backed
  if (!self.contentView.wantsLayer) {
    self.contentView.wantsLayer = YES;
  }

  // RE-APPLY Liquid Glass if available on the new content view
  if ([self.window respondsToSelector:@selector(setupLiquidGlass)]) {
    [self.window performSelector:@selector(setupLiquidGlass)];
  }
}
#endif

- (void)setSurfaceLayer:(WawonaSurfaceLayer *)surfaceLayer {
  _surfaceLayer = surfaceLayer;
  if (surfaceLayer) {
    [self.contentView.layer addSublayer:surfaceLayer.rootLayer];
    // Ensure accurate sizing
    [surfaceLayer updateContentWithSize:self.contentView.bounds.size];
  }
}

- (void)show {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  [self.window makeKeyAndVisible];
#else
  [self.window makeKeyAndOrderFront:nil];
#endif
}

- (void)hide {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  self.window.hidden = YES;
#else
  [self.window orderOut:nil];
#endif
}

- (void)close {
  // Wayland close request
  if (self.toplevel && self.toplevel->resource) {
    extern void xdg_toplevel_send_close(struct wl_resource *);
    xdg_toplevel_send_close(self.toplevel->resource);
  } else {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    self.window.hidden = YES;
    // On iOS we don't really "close" windows in the same way, but we can hide
    // it.
#else
    [self.window close];
#endif
  }
}

- (void)updateDecorationMode:(WawonaDecorationMode)mode {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  if (self.decorationMode == mode)
    return;

  // Recreate window for clean switch
  NSRect frame = self.window.frame;
  NSRect contentRect = [self.window contentRectForFrameRect:frame];

  NSWindow *oldWindow = self.window;
  NSView *oldContent =
      self.contentView; // Preserve the view (CompositorView usually)

  self.decorationMode = mode;
  [self createWindowWithSize:contentRect.size];

  // Restore content view
  [self replaceContentView:oldContent];

  // Restore frame/position
  NSRect newFrame = [self.window frameRectForContentRect:contentRect];
  newFrame.origin = frame.origin; // Keep position
  [self.window setFrame:newFrame display:YES];

  [oldWindow close];
  [self show];
#endif
}

- (void)setTitle:(NSString *)title {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  self.window.title = title ? title : @"Wawona Client";
#endif
}

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
// CSD Resize Logic
- (NSRectEdge)detectResizeEdgeAtPoint:(CGPoint)point {
  if (self.decorationMode != WawonaDecorationModeCSD)
    return (NSRectEdge)-1;

  CGRect bounds = self.contentView.bounds;
  BOOL left = point.x < kResizeEdgeInset;
  BOOL right = point.x > bounds.size.width - kResizeEdgeInset;
  BOOL bottom = point.y < kResizeEdgeInset;
  BOOL top = point.y > bounds.size.height - kResizeEdgeInset;

  if (left)
    return NSMinXEdge;
  if (right)
    return NSMaxXEdge;
  if (bottom)
    return NSMinYEdge;
  if (top)
    return NSMaxYEdge;

  return (NSRectEdge)-1;
}

- (void)beginResizeWithEdge:(NSRectEdge)edge atPoint:(CGPoint)point {
  self.isResizing = YES;
  self.resizeEdge = edge;
  self.resizeStartPoint = [self.window convertPointToScreen:point];
  self.resizeStartFrame = self.window.frame;
}

- (void)continueResizeToPoint:(CGPoint)screenPoint {
  if (!self.isResizing)
    return;

  CGFloat dx = screenPoint.x - self.resizeStartPoint.x;
  CGFloat dy = screenPoint.y - self.resizeStartPoint.y;
  NSRect frame = self.resizeStartFrame;

  switch (self.resizeEdge) {
  case NSMinXEdge:
    frame.origin.x += dx;
    frame.size.width -= dx;
    break;
  case NSMaxXEdge:
    frame.size.width += dx;
    break;
  case NSMinYEdge:
    frame.origin.y += dy;
    frame.size.height -= dy;
    break;
  case NSMaxYEdge:
    frame.size.height += dy;
    break;
  }

  if (frame.size.width < 50)
    frame.size.width = 50;
  if (frame.size.height < 50)
    frame.size.height = 50;

  [self.window setFrame:frame display:YES];
  [self notifyWaylandResize];
}

- (void)endResize {
  self.isResizing = NO;
}
#else
- (void)continueResizeToPoint:(CGPoint)point {
}
- (void)endResize {
}
#endif

- (void)notifyWaylandResize {
  if (!self.toplevel || !self.toplevel->xdg_surface)
    return;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  CGRect contentRect = self.window.bounds;
#else
  NSRect contentRect = [self.window contentRectForFrameRect:self.window.frame];
#endif
  int w = (int)contentRect.size.width;
  int h = (int)contentRect.size.height;

  struct wl_array states;
  wl_array_init(&states);

  uint32_t *s = wl_array_add(&states, sizeof(uint32_t));
  *s = 4; // ACTIVATED
  s = wl_array_add(&states, sizeof(uint32_t));
  *s = 3; // RESIZING

  xdg_toplevel_send_configure(self.toplevel->resource, w, h, &states);
  xdg_surface_send_configure(self.toplevel->xdg_surface->resource,
                             ++self.toplevel->xdg_surface->configure_serial);
  wl_array_release(&states);
}

// Delegate
- (void)windowDidResize:(NSNotification *)notification {
  if (!self.isResizing)
    [self notifyWaylandResize];
  if (self.surfaceLayer) {
    [self.surfaceLayer updateContentWithSize:self.contentView.bounds.size];
  }
}

- (void)windowDidBecomeKey:(NSNotification *)n {
  // Send activated
  if (!self.toplevel)
    return;
  struct wl_array states;
  wl_array_init(&states);
  uint32_t *s = wl_array_add(&states, sizeof(uint32_t));
  *s = 4;
  xdg_toplevel_send_configure(self.toplevel->resource, 0, 0, &states);
  xdg_surface_send_configure(self.toplevel->xdg_surface->resource,
                             ++self.toplevel->xdg_surface->configure_serial);
  wl_array_release(&states);
}

@end

//==============================================================================
// MARK: - WawonaSurfaceManagerImplementation
//==============================================================================

@interface WawonaSurfaceManager ()
@property(nonatomic, strong) NSMapTable *surfaceLayers;
@property(nonatomic, strong) NSMapTable *windowContainers;
@property(nonatomic, strong) id<MTLDevice> metalDevice;
@end

@implementation WawonaSurfaceManager

+ (instancetype)sharedManager {
  static WawonaSurfaceManager *sharedInstance = nil;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[WawonaSurfaceManager alloc] init];
  });
  return sharedInstance;
}

- (instancetype)init {
  self = [super init];
  if (self) {
    _metalDevice = MTLCreateSystemDefaultDevice();
    _surfaceLayers =
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory
                              valueOptions:NSPointerFunctionsStrongMemory];
    _windowContainers =
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory
                              valueOptions:NSPointerFunctionsStrongMemory];
  }
  return self;
}

- (WawonaSurfaceLayer *)createSurfaceLayerForSurface:
    (struct wl_surface_impl *)surface {
  @synchronized(self) {
    if (!surface)
      return nil;
    NSValue *key = [NSValue valueWithPointer:surface];
    if ([_surfaceLayers objectForKey:key])
      return [_surfaceLayers objectForKey:key];

    WawonaSurfaceLayer *l =
        [[WawonaSurfaceLayer alloc] initWithSurface:surface];
    [_surfaceLayers setObject:l forKey:key];
    return l;
  }
}

- (void)destroySurfaceLayer:(struct wl_surface_impl *)surface {
  @synchronized(self) {
    if (!surface)
      return;
    [_surfaceLayers removeObjectForKey:[NSValue valueWithPointer:surface]];
  }
}

- (WawonaSurfaceLayer *)layerForSurface:(struct wl_surface_impl *)surface {
  @synchronized(self) {
    return [_surfaceLayers objectForKey:[NSValue valueWithPointer:surface]];
  }
}

- (WawonaWindowContainer *)createWindowForToplevel:
                               (struct xdg_toplevel_impl *)toplevel
                                    decorationMode:(WawonaDecorationMode)mode
                                              size:(CGSize)size {
  @synchronized(self) {
    WawonaWindowContainer *c =
        [[WawonaWindowContainer alloc] initWithToplevel:toplevel
                                         decorationMode:mode
                                                   size:size];
    [_windowContainers setObject:c forKey:[NSValue valueWithPointer:toplevel]];
    if (toplevel->xdg_surface) {
      c.surfaceLayer =
          [self createSurfaceLayerForSurface:toplevel->xdg_surface->wl_surface];
    }
    return c;
  }
}

- (WawonaWindowContainer *)windowForToplevel:
    (struct xdg_toplevel_impl *)toplevel {
  @synchronized(self) {
    return [_windowContainers objectForKey:[NSValue valueWithPointer:toplevel]];
  }
}

- (void)destroyWindowForToplevel:(struct xdg_toplevel_impl *)toplevel {
  @synchronized(self) {
    [_windowContainers removeObjectForKey:[NSValue valueWithPointer:toplevel]];
  }
}

// Helpers for popup not implemented fully in simplified version but stubbed
- (id)createPopup:(void *)popup
     parentWindow:(id)parent
         position:(CGPoint)pos
             size:(CGSize)size {
  return nil;
}
- (void)destroyPopup:(void *)popup {
}
- (void)setNeedsDisplayForAllSurfaces {
}

@end

//==============================================================================
// MARK: - C Bridge Functions
//==============================================================================

#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR

void macos_create_window_for_toplevel(struct xdg_toplevel_impl *toplevel) {
  // Capture values synchronously to avoid dereferencing raw pointers in block
  // (thread safety)
  WawonaDecorationMode mode = (toplevel->decoration_mode == 1)
                                  ? WawonaDecorationModeCSD
                                  : WawonaDecorationModeSSD;
  CGSize size = CGSizeMake(toplevel->width > 0 ? toplevel->width : 800,
                           toplevel->height > 0 ? toplevel->height : 600);

  // We must pass 'toplevel' as a value (pointer) to the method, but beware
  // validity. However, xdg_toplevel's lifecycle is managed by xdg_surface.

  dispatch_async(dispatch_get_main_queue(), ^{
    WawonaWindowContainer *c =
        [[WawonaSurfaceManager sharedManager] createWindowForToplevel:toplevel
                                                       decorationMode:mode
                                                                 size:size];

    NSWindow *win = c.window;
    Class cvClass = NSClassFromString(@"CompositorView");
    if (cvClass) {
      NSView *cv = [[cvClass alloc] initWithFrame:win.contentView.bounds];
      [c replaceContentView:cv];
      // Set renderer
      id<RenderingBackend> r =
          [RenderingBackendFactory createBackend:RENDERING_BACKEND_METAL
                                        withView:cv];
      if ([cv respondsToSelector:@selector(setRenderer:)])
        [cv performSelector:@selector(setRenderer:) withObject:r];

      // Set inputHandler for input event dispatch
      if ([cv respondsToSelector:@selector(setInputHandler:)] &&
          g_wl_compositor_instance.inputHandler) {
        [cv performSelector:@selector(setInputHandler:)
                 withObject:g_wl_compositor_instance.inputHandler];
      }

      // Populate Compositor Map for Input/Lookup compatibility
      if (g_wl_compositor_instance) {
        [g_wl_compositor_instance.mapLock lock];
        [g_wl_compositor_instance.windowToToplevelMap
            setObject:[NSValue valueWithPointer:toplevel]
               forKey:[NSValue valueWithPointer:(__bridge void *)win]];
        [g_wl_compositor_instance.mapLock unlock];
      }
    }

    [c show];
    log_printf("WINDOW", "Window shown\n");
  });
}

void macos_update_toplevel_decoration_mode(struct xdg_toplevel_impl *toplevel) {
  dispatch_async(dispatch_get_main_queue(), ^{
    WawonaWindowContainer *c =
        [[WawonaSurfaceManager sharedManager] windowForToplevel:toplevel];
    WawonaDecorationMode mode = (toplevel->decoration_mode == 1)
                                    ? WawonaDecorationModeCSD
                                    : WawonaDecorationModeSSD;
    [c updateDecorationMode:mode];
  });
}
// Add other stubs as needed
void macos_toplevel_set_maximized(struct xdg_toplevel_impl *t) {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[[[WawonaSurfaceManager sharedManager] windowForToplevel:t] window]
        zoom:nil];
  });
}
void macos_toplevel_set_minimized(struct xdg_toplevel_impl *t) {
  dispatch_async(dispatch_get_main_queue(), ^{
    [[[[WawonaSurfaceManager sharedManager] windowForToplevel:t] window]
        miniaturize:nil];
  });
}
void macos_update_toplevel_title(struct xdg_toplevel_impl *t) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (t->title)
      [[[[WawonaSurfaceManager sharedManager] windowForToplevel:t] window]
          setTitle:[NSString stringWithUTF8String:t->title]];
  });
}

void macos_start_toplevel_move(struct xdg_toplevel_impl *toplevel) {
  if (!toplevel || !toplevel->native_window)
    return;
  dispatch_async(dispatch_get_main_queue(), ^{
    NSWindow *window = (__bridge NSWindow *)toplevel->native_window;
    [window performWindowDragWithEvent:[NSApp currentEvent]];
  });
}

void macos_start_toplevel_resize(struct xdg_toplevel_impl *toplevel,
                                 uint32_t edges) {
  if (!toplevel)
    return;
  dispatch_async(dispatch_get_main_queue(), ^{
    WawonaWindowContainer *c =
        [[WawonaSurfaceManager sharedManager] windowForToplevel:toplevel];
    if (!c || c.decorationMode != WawonaDecorationModeCSD)
      return;

    // Map Wayland edges to NSRectEdge
    // Wayland: 1=top, 2=bottom, 4=left, 8=right
    NSRectEdge edge = (NSRectEdge)-1;
    if (edges == 1)
      edge = NSMaxYEdge; // Top (in flipped coords? No, AppKit is bottom-left
                         // origin usually, but 0,0 is bottom-left)
    // Actually, detecting the edge from the point is safer and more consistent
    // with standard macOS behavior But for CSD initiated resize (e.g.
    // keybinding), we might need this. For now, let's just trigger the resize
    // loop if possible or rely on client-side hit testing.

    // Simpler implementation: Just use the container's logic if point
    // available, but here we only have edges. A full implementation would
    // programmatically start a resize. For CSD, we can rely on
    // `detectResizeEdgeAtPoint` called from input handler. If this is called,
    // it means client wants to start resize (e.g. from a click on a decoration
    // it drew).

    // We need the mouse location to start tracking.
    NSPoint mouseLoc = [NSEvent mouseLocation];
    // Convert to window coordinates?
    // Actually, logic is better handled in InputHandler or by mapping edges.

    // Since we implemented simplified CSD resize in WindowContainer that relies
    // on `beginResize`, let's just pass it through if we can determine the
    // edge.

    if (edges & 4 && edges & 1)
      edge = NSMinXEdge; // Top-Left (Simplified)
                         // ... extensive mapping ...

    // Fallback: This is often triggered by mouse down on edge.
    // We can synthesize the start.
    // For MVP, logging or simple pass-through.
  });
}

void macos_toplevel_close(struct xdg_toplevel_impl *toplevel) {
  dispatch_async(dispatch_get_main_queue(), ^{
    WawonaWindowContainer *c =
        [[WawonaSurfaceManager sharedManager] windowForToplevel:toplevel];
    [c close];
  });
}

void macos_toplevel_set_fullscreen(struct xdg_toplevel_impl *toplevel) {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSWindow *window = (__bridge NSWindow *)toplevel->native_window;
    if (!([window styleMask] & NSWindowStyleMaskFullScreen)) {
      [window toggleFullScreen:nil];
    }
  });
}

void macos_toplevel_unset_fullscreen(struct xdg_toplevel_impl *toplevel) {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSWindow *window = (__bridge NSWindow *)toplevel->native_window;
    if ([window styleMask] & NSWindowStyleMaskFullScreen) {
      [window toggleFullScreen:nil];
    }
  });
}

void macos_toplevel_unset_maximized(struct xdg_toplevel_impl *toplevel) {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSWindow *window = (__bridge NSWindow *)toplevel->native_window;
    if ([window isZoomed]) {
      [window zoom:nil];
    }
  });
}

void macos_toplevel_set_max_size(struct xdg_toplevel_impl *toplevel,
                                 int32_t width, int32_t height) {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSWindow *window = (__bridge NSWindow *)toplevel->native_window;
    window.contentMaxSize =
        NSMakeSize(width > 0 ? width : FLT_MAX, height > 0 ? height : FLT_MAX);
  });
}

void macos_toplevel_set_min_size(struct xdg_toplevel_impl *toplevel,
                                 int32_t width, int32_t height) {
  dispatch_async(dispatch_get_main_queue(), ^{
    NSWindow *window = (__bridge NSWindow *)toplevel->native_window;
    window.contentMinSize = NSMakeSize(width, height);
  });
}

void macos_unregister_toplevel(struct xdg_toplevel_impl *toplevel) {
  // Synchronously remove from map to prevent race conditions
  if (g_wl_compositor_instance) {
    [g_wl_compositor_instance.mapLock lock];
    NSArray *keys =
        [g_wl_compositor_instance.windowToToplevelMap keyEnumerator].allObjects;
    for (NSValue *k in keys) {
      NSValue *v =
          [g_wl_compositor_instance.windowToToplevelMap objectForKey:k];
      if ([v pointerValue] == toplevel) {
        [g_wl_compositor_instance.windowToToplevelMap removeObjectForKey:k];
        break;
      }
    }
    [g_wl_compositor_instance.mapLock unlock];
  }

  // Dispatch window destruction to main thread
  dispatch_async(dispatch_get_main_queue(), ^{
    [[WawonaSurfaceManager sharedManager] destroyWindowForToplevel:toplevel];
  });
}

#endif
