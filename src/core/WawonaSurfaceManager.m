// WawonaSurfaceManager.m - CALayer-based Wayland Surface Management
// Implementation

#import "WawonaSurfaceManager.h"
#import "../compositor_implementations/wayland_compositor.h"
#import "../compositor_implementations/xdg_shell.h"
#import "../logging/WawonaLog.h"
#import "RenderingBackend.h"
#import "metal_dmabuf.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>

// Constants for CSD resize detection and shadow margins
const CGFloat kResizeEdgeInset = 8.0;   // pixels from edge
const CGFloat kResizeCornerSize = 20.0; // corner region size
const CGFloat kCSDShadowMargin = 30.0;  // Margin for client-side shadows

//==============================================================================
// MARK: - WawonaSurfaceLayer Implementation
//==============================================================================

@implementation WawonaSurfaceLayer

- (instancetype)initWithSurface:(struct wl_surface_impl *)surface {
  self = [super init];
  if (self) {
    _surface = surface;
    _isMapped = NO;
    _needsDisplay = YES;
    _subsurfaceLayers = [NSMutableArray array];

    // Create root layer (container for everything)
    _rootLayer = [CALayer layer];
    _rootLayer.masksToBounds = NO; // Allow content to extend
    _rootLayer.anchorPoint = CGPointMake(0, 0);

    // Create content layer (GPU-accelerated Metal layer)
    _contentLayer = [CAMetalLayer layer];
    _contentLayer.device = MTLCreateSystemDefaultDevice();
    _contentLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
    _contentLayer.framebufferOnly = NO; // Allow reading for waypipe/screenshots
    _contentLayer.presentsWithTransaction = NO; // Manual presentation
    _contentLayer.anchorPoint = CGPointMake(0, 0);

    [_rootLayer addSublayer:_contentLayer];

    WLog(@"SURFACE", @"Created surface layer for surface %p", surface);
  }
  return self;
}

- (void)updateContentWithSize:(CGSize)size {
  // CRITICAL: Force layer to match window size exactly.
  // We use masksToBounds to ensure that if the buffer is larger/smaller during
  // resize, it doesn't bleed out or look weird.
  self.rootLayer.masksToBounds = YES;

  // Position is managed by the caller (e.g. WawonaWindowContainer)
  // to account for margins if necessary.

  // Update bounds
  self.rootLayer.bounds = CGRectMake(0, 0, size.width, size.height);
  self.contentLayer.bounds = CGRectMake(0, 0, size.width, size.height);

  // IMPORTANT: Do NOT update drawableSize here if unnecessary.
  // Metal drawable size should match the buffer size usually.
  // If we stretch it, we might get scaling artifacts, BUT it keeps the frame
  // aligned. Let's rely on the renderer to update drawableSize based on buffer.
  // We JUST want to ensure the layer frame itself is correct.

  self.needsDisplay = YES;
}

- (void)addSubsurfaceLayer:(CALayer *)sublayer atIndex:(NSInteger)index {
  [self.subsurfaceLayers insertObject:sublayer atIndex:index];
  [self.rootLayer addSublayer:sublayer];
  WLog(@"SURFACE", @"Added subsurface layer at index %ld", (long)index);
}

- (void)removeSubsurfaceLayer:(CALayer *)sublayer {
  [self.subsurfaceLayers removeObject:sublayer];
  [sublayer removeFromSuperlayer];
  WLog(@"SURFACE", @"Removed subsurface layer");
}

- (void)setNeedsRedisplay {
  self.needsDisplay = YES;
  [self.contentLayer setNeedsDisplay];
}

- (void)dealloc {
  WLog(@"SURFACE", @"Deallocating surface layer for surface %p", _surface);
}

@end

//==============================================================================
// MARK: - WawonaWindowContainer Implementation
//==============================================================================

@interface WawonaWindowContainer () <NSWindowDelegate>
@property(nonatomic, strong) NSView *contentView;
@end

@implementation WawonaWindowContainer

- (instancetype)initWithToplevel:(struct xdg_toplevel_impl *)toplevel
                  decorationMode:(WawonaDecorationMode)mode
                            size:(CGSize)size {
  self = [super init];
  if (self) {
    _toplevel = toplevel;
    _decorationMode = mode;
    _isResizing = NO;

    [self createWindowWithSize:size];
  }
  return self;
}

- (void)createWindowWithSize:(CGSize)size {
  NSRect contentRect = NSMakeRect(100, 100, size.width, size.height);
  NSWindowStyleMask styleMask;

  if (self.decorationMode == WawonaDecorationModeCSD) {
    // CSD: Borderless window (no macOS chrome)
    styleMask = NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable |
                NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskClosable;

    // Add margin for shadow
    CGFloat margin = kCSDShadowMargin;
    contentRect.size.width += (margin * 2);
    contentRect.size.height += (margin * 2);

    WLog(@"WINDOW", @"Creating CSD (borderless) window for toplevel %p",
         _toplevel);
  } else {
    // SSD: Standard macOS window with chrome
    styleMask = NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable;

    WLog(@"WINDOW", @"Creating SSD (titled) window for toplevel %p", _toplevel);
  }

  self.window = [[NSWindow alloc] initWithContentRect:contentRect
                                            styleMask:styleMask
                                              backing:NSBackingStoreBuffered
                                                defer:NO];

  self.window.delegate = self;
  self.window.acceptsMouseMovedEvents = YES;
  self.window.releasedWhenClosed = NO;

  if (self.decorationMode == WawonaDecorationModeCSD) {
    // CSD-specific window setup
    self.window.backgroundColor = [NSColor clearColor];
    self.window.opaque = NO;
    self.window.hasShadow = NO; // We'll draw our own shadow layer
    self.window.movableByWindowBackground = NO; // Client handles move
  } else {
    // SSD-specific window setup
    self.window.backgroundColor = [NSColor windowBackgroundColor];
    self.window.opaque = YES;
    self.window.hasShadow = YES; // Native macOS shadow
  }

  // Create content view (layer-backed)
  NSRect viewFrame = [self.window contentRectForFrameRect:self.window.frame];
  self.contentView = [[NSView alloc] initWithFrame:viewFrame];
  self.contentView.wantsLayer = YES;
  self.contentView.layer.masksToBounds = NO; // Allow shadow overflow for CSD

  self.window.contentView = self.contentView;

  // Store window reference in toplevel
  _toplevel->native_window = (__bridge void *)self.window;
}

- (void)replaceContentView:(NSView *)newView {
  if (!newView || newView == self.contentView) {
    return;
  }

  WLog(@"WINDOW", @"Replacing content view for window %p",
       (__bridge void *)self.window);

  // Transfer layers from old content view to new content view
  if (self.rootContainerLayer) {
    [self.rootContainerLayer removeFromSuperlayer];
    [newView.layer addSublayer:self.rootContainerLayer];
    self.rootContainerLayer.frame = newView.bounds;
  }

  // Update reference
  self.contentView = newView;

  // Ensure new view is layer-backed if it wasn't already (CompositorView is
  // usually layer-backed)
  if (!self.contentView.wantsLayer) {
    self.contentView.wantsLayer = YES;
  }
  self.contentView.layer.masksToBounds = NO; // Important for shadow/overflow

  // Set on window
  self.window.contentView = self.contentView;
}

- (void)setSurfaceLayer:(WawonaSurfaceLayer *)surfaceLayer {
  _surfaceLayer = surfaceLayer;

  if (surfaceLayer) {
    if (!self.rootContainerLayer) {
      self.rootContainerLayer = [CALayer layer];
      self.rootContainerLayer.name = @"WawonaRootContainer";
      [self.contentView.layer addSublayer:self.rootContainerLayer];
    }

    self.rootContainerLayer.frame = self.contentView.bounds;

    // Window Layer: Add Wayland surface content
    if (surfaceLayer.rootLayer.superlayer != self.rootContainerLayer) {
      [self.rootContainerLayer addSublayer:surfaceLayer.rootLayer];
    }

    if (self.decorationMode == WawonaDecorationModeCSD) {
      // Create shadow if needed
      if (!self.csdShadowLayer) {
        [self setupCSDShadowLayer];
      }

      CGFloat margin = kCSDShadowMargin;
      CGFloat w = self.contentView.bounds.size.width - (margin * 2);
      CGFloat h = self.contentView.bounds.size.height - (margin * 2);
      if (w < 1)
        w = 1;
      if (h < 1)
        h = 1;

      [surfaceLayer updateContentWithSize:CGSizeMake(w, h)];
      surfaceLayer.rootLayer.position = CGPointMake(margin, margin);

      [self updateCSDShadowLayer];
    } else {
      // SSD: Fill window
      [surfaceLayer updateContentWithSize:self.contentView.bounds.size];
      surfaceLayer.rootLayer.position = CGPointMake(0, 0);

      if (self.csdShadowLayer) {
        [self.csdShadowLayer removeFromSuperlayer];
        self.csdShadowLayer = nil;
      }
    }
  }
}

- (void)setupCSDShadowLayer {
  if (!self.rootContainerLayer) {
    return;
  }

  // Create shadow layer (click-through, below content)
  self.csdShadowLayer = [CALayer layer];
  self.csdShadowLayer.name = @"WawonaCSDShadow";
  self.csdShadowLayer.shadowOpacity = 0.5;
  self.csdShadowLayer.shadowRadius = 20.0;
  self.csdShadowLayer.shadowOffset = CGSizeMake(0, -5);
  self.csdShadowLayer.shadowColor = [[NSColor blackColor] CGColor];
  self.csdShadowLayer.backgroundColor =
      [[NSColor greenColor] colorWithAlphaComponent:0.5].CGColor;
  self.csdShadowLayer.masksToBounds = NO;
  self.csdShadowLayer.actions = @{
    @"bounds" : [NSNull null],
    @"position" : [NSNull null],
    @"shadowPath" : [NSNull null]
  };

  // Insert shadow layer below surface content layer
  [self.rootContainerLayer insertSublayer:self.csdShadowLayer atIndex:0];

  [self updateCSDShadowLayer];

  WLog(@"WINDOW", @"Created modular CSD shadow layer for window %p",
       (__bridge void *)self.window);
}

- (void)updateCSDShadowLayer {
  if (!self.csdShadowLayer || !self.surfaceLayer) {
    return;
  }

  // Match shadow to the visual content bounds
  CGRect contentFrame = self.surfaceLayer.rootLayer.frame;
  self.csdShadowLayer.frame = contentFrame;

  // Create shadow path matching the surface content rectangle
  // This ensures the shadow follows the window exactly
  CGRect shadowBounds =
      CGRectMake(0, 0, contentFrame.size.width, contentFrame.size.height);
  CGPathRef shadowPath = CGPathCreateWithRect(shadowBounds, NULL);
  self.csdShadowLayer.shadowPath = shadowPath;
  CGPathRelease(shadowPath);
}

- (void)show {
  [self.window makeKeyAndOrderFront:nil];
  WLog(@"WINDOW", @"Showed window %p", (__bridge void *)self.window);
}

- (void)hide {
  [self.window orderOut:nil];
  WLog(@"WINDOW", @"Hid window %p", (__bridge void *)self.window);
}

- (void)close {
  WLog(@"WINDOW", @"Closing window %p", (__bridge void *)self.window);

  // Send close event to Wayland client
  if (self.toplevel && self.toplevel->resource) {
    extern void xdg_toplevel_send_close(struct wl_resource * resource);
    xdg_toplevel_send_close(self.toplevel->resource);
  }
}

- (void)minimize {
  WLog(@"WINDOW", @"Minimizing window %p (macOS API)",
       (__bridge void *)self.window);
  [self.window miniaturize:nil];

  // Notify Wayland client of minimized state
  // This would typically be done through xdg_toplevel.configure with
  // minimized state
}

- (void)maximize {
  WLog(@"WINDOW", @"Maximizing window %p (macOS zoom API)",
       (__bridge void *)self.window);
  [self.window zoom:nil];

  // Notify Wayland client of maximized state
  // This would be done through xdg_toplevel.configure with maximized state
}

- (void)invalidateToplevel {
  WLog(@"WINDOW", @"Invalidating toplevel reference %p", (void *)_toplevel);
  _toplevel = NULL;
}

- (void)updateDecorationMode:(WawonaDecorationMode)mode {
  if (self.decorationMode == mode)
    return;

  WLog(@"WINDOW", @"Updating decoration mode from %d to %d",
       (int)self.decorationMode, (int)mode);

  // Save current content rect to maintain size
  NSRect contentRect = [self.window contentRectForFrameRect:self.window.frame];

  self.decorationMode = mode;

  // Recreate window with new style
  NSWindow *oldWindow = self.window;
  [self createWindowWithSize:contentRect.size];

  // Transfer surface layer to new window
  if (self.surfaceLayer) {
    [self.surfaceLayer.rootLayer removeFromSuperlayer];
    [self.contentView.layer addSublayer:self.surfaceLayer.rootLayer];

    if (mode == WawonaDecorationModeCSD) {
      [self setupCSDShadowLayer];
    } else {
      // Remove shadow layer for SSD
      if (self.csdShadowLayer) {
        [self.csdShadowLayer removeFromSuperlayer];
        self.csdShadowLayer = nil;
      }
    }
  }

  // Show new window and close old one
  [self.window setFrame:[oldWindow frame] display:YES];
  [self show];
  [oldWindow close];
}

- (void)setTitle:(NSString *)title {
  self.window.title = title ?: @"Wawona Client";
}

- (void)resize:(CGSize)newSize {
  CGSize windowSize = newSize;

  if (self.decorationMode == WawonaDecorationModeCSD) {
    CGFloat margin = kCSDShadowMargin;
    windowSize.width += (margin * 2);
    windowSize.height += (margin * 2);
  }

  NSRect currentFrame = self.window.frame;
  NSRect newContentRect =
      NSMakeRect(currentFrame.origin.x, currentFrame.origin.y, windowSize.width,
                 windowSize.height);
  // Important: Use frameRectForContentRect to get full window frame including
  // titlebar (if SSD)
  NSRect newFrame = [self.window frameRectForContentRect:newContentRect];

  [self.window setFrame:newFrame display:YES animate:NO];

  // Update layers
  if (self.rootContainerLayer) {
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.rootContainerLayer.frame = self.contentView.bounds;
    [CATransaction commit];
  }

  if (self.surfaceLayer) {
    [self.surfaceLayer updateContentWithSize:newSize]; // Internal buffer size

    // Update layer positions and shadow if CSD
    if (self.decorationMode == WawonaDecorationModeCSD) {
      CGFloat margin = kCSDShadowMargin;
      self.surfaceLayer.rootLayer.position = CGPointMake(margin, margin);
      [self updateCSDShadowLayer];
    } else {
      self.surfaceLayer.rootLayer.position = CGPointMake(0, 0);
    }
  }
}

//==============================================================================
// MARK: - CSD Resize Detection and Handling
//==============================================================================

- (NSRectEdge)detectResizeEdgeAtPoint:(CGPoint)point {
  if (self.decorationMode != WawonaDecorationModeCSD) {
    return (NSRectEdge)-1; // Not CSD, no custom resize
  }

  // Get the visual window bounds (excluding shadow)
  CGFloat margin = kCSDShadowMargin;
  CGRect bounds = self.contentView.bounds;
  CGRect visualRect = CGRectInset(bounds, margin, margin);
  CGFloat kResizeThreshold = 10.0;

  // Hit test against the VISUAL edge (which is at 'margin')
  // We want to allow resizing slightly outside (in the shadow area) and
  // slightly inside
  BOOL nearLeft = fabs(point.x - visualRect.origin.x) < kResizeThreshold;
  BOOL nearRight =
      fabs(point.x - (visualRect.origin.x + visualRect.size.width)) <
      kResizeThreshold;
  BOOL nearBottom =
      fabs(point.y - visualRect.origin.y) <
      kResizeThreshold; // Cocoa bottom-left origin? Wait, NSView coordinates.
  BOOL nearTop =
      fabs(point.y - (visualRect.origin.y + visualRect.size.height)) <
      kResizeThreshold;

  // Check if point is completely outside the "interaction zone" (too far into
  // shadow) If point is 0, margin is 30. fabs(0-30) = 30 > 10. No hit.
  // Correct. The shadow click-through is handled by valid hit testing here
  // returning -1.

  // Check valid Y range for X edges and valid X range for Y edges to avoid
  // "infinite lines" Allow corners to be detected even if slightly outside,
  // but generally clamp
  BOOL inYRange = (point.y >= visualRect.origin.y - kResizeThreshold) &&
                  (point.y <= visualRect.origin.y + visualRect.size.height +
                                  kResizeThreshold);
  BOOL inXRange = (point.x >= visualRect.origin.x - kResizeThreshold) &&
                  (point.x <= visualRect.origin.x + visualRect.size.width +
                                  kResizeThreshold);

  if (!inYRange)
    nearLeft = nearRight = NO;
  if (!inXRange)
    nearTop = nearBottom = NO;

  // Check corners first (priority over edges)
  if (nearLeft && nearBottom)
    return NSMinXEdge | NSMinYEdge; // Cocoa: Bottom-Left? NSMinY is Bottom in
                                    // flipped? No, NSView is usually valid.
  // NOTE: NSMinYEdge in standard Cocoa coords is BOTTOM.
  // However, CSD might expect top-left origin?
  // Let's assume standard behavior:
  // NSMinX = Left, NSMaxX = Right
  // NSMinY = Bottom, NSMaxY = Top (in standard cartesian)
  // BUT! NSWindow coordinates usually have (0,0) at bottom-left.
  // `detectResizeEdgeAtPoint` takes `point`. where does it come from?
  // It comes from `mouseLocation` converted to `contentView`.
  // We should assume standard Cocoa (0,0 is bottom-left).

  if (nearLeft && nearBottom)
    return 9; // Custom encoding or just handle separately?
  // Wait, NSRectEdge is: NSMinXEdge=0, NSMinYEdge=1, NSMaxXEdge=2,
  // NSMaxYEdge=3. There isn't a single enum for corners in NSRectEdge
  // usually? Actually `beginResizeWithEdge` takes NSRectEdge. Wawona likely
  // maps corners to a specific enum or handles 2 edges? Looking at previous
  // code: "if (nearLeft && nearBottom) return NSMinXEdge" -> It returned
  // Edge, not Corner? This is weird. Usually corners are handled by sending
  // BOTH edges to Wayland? Or maybe we accept just one for the cursor? Let's
  // stick to the previous return values but with correct logic. Previous
  // code: if (nearLeft
  // && nearBottom) return NSMinXEdge; // Bottom-left -> Left? if (nearRight
  // && nearBottom) return NSMaxXEdge; // Bottom-right -> Right?

  // Let's improve this: Just return a dominant edge if corner?
  // Or better, logic for corners usually requires knowledge of direction.
  // Let's keep it simple and consistent with previous code but corrected
  // bounds.

  if (nearLeft && nearBottom)
    return NSMinXEdge; // Emulate specific internal behavior if needed, or
                       // just return an edge.
  if (nearRight && nearBottom)
    return NSMaxXEdge;
  if (nearLeft && nearTop)
    return NSMinXEdge;
  if (nearRight && nearTop)
    return NSMaxXEdge;

  // Check edges
  if (nearLeft)
    return NSMinXEdge;
  if (nearRight)
    return NSMaxXEdge;
  if (nearTop)
    return NSMaxYEdge;
  if (nearBottom)
    return NSMinYEdge;

  return (NSRectEdge)-1; // Not near any edge
}

- (void)beginResizeWithEdge:(NSRectEdge)edge atPoint:(CGPoint)point {
  self.isResizing = YES;
  self.resizeEdge = edge;
  self.resizeStartPoint = [self.window convertPointToScreen:point];
  self.resizeStartFrame = self.window.frame;

  WLog(@"WINDOW", @"Begin CSD resize: edge=%ld", (long)edge);
}

- (void)continueResizeToPoint:(CGPoint)screenPoint {
  if (!self.isResizing)
    return;

  CGFloat deltaX = screenPoint.x - self.resizeStartPoint.x;
  CGFloat deltaY = screenPoint.y - self.resizeStartPoint.y;

  NSRect newFrame = self.resizeStartFrame;

  // Apply deltas based on resize edge
  switch (self.resizeEdge) {
  case NSMinXEdge: // Left edge
    newFrame.origin.x += deltaX;
    newFrame.size.width -= deltaX;
    break;
  case NSMaxXEdge: // Right edge
    newFrame.size.width += deltaX;
    break;
  case NSMinYEdge: // Bottom edge
    newFrame.origin.y += deltaY;
    newFrame.size.height -= deltaY;
    break;
  case NSMaxYEdge: // Top edge
    newFrame.size.height += deltaY;
    break;
  }

  // Enforce minimum size
  if (newFrame.size.width < 100)
    newFrame.size.width = 100;
  if (newFrame.size.height < 100)
    newFrame.size.height = 100;

  [self.window setFrame:newFrame display:YES animate:NO];

  // Send configure event to Wayland client (CSD: full frame size)
  if (self.toplevel && self.toplevel->resource && self.toplevel->xdg_surface) {
    extern void xdg_toplevel_send_configure(struct wl_resource * resource,
                                            int32_t width, int32_t height,
                                            struct wl_array *states);
    extern void xdg_surface_send_configure(struct wl_resource * resource,
                                           uint32_t serial);

    struct wl_array states;
    wl_array_init(&states);

    // Add resizing state
    uint32_t *state = wl_array_add(&states, sizeof(uint32_t));
    if (state) {
      *state = 8; // XDG_TOPLEVEL_STATE_RESIZING
    }
    // Add activated state
    state = wl_array_add(&states, sizeof(uint32_t));
    if (state) {
      *state = 4; // XDG_TOPLEVEL_STATE_ACTIVATED
    }

    // For CSD, send full window size (client draws decorations)
    // BUT we must subtract the shadow margin we added, effectively sending
    // the SURFACE size
    NSRect contentRect = [self.window contentRectForFrameRect:newFrame];
    int32_t width = (int32_t)contentRect.size.width;
    int32_t height = (int32_t)contentRect.size.height;

    if (self.decorationMode == WawonaDecorationModeCSD) {
      CGFloat margin = kCSDShadowMargin;
      width -= (margin * 2);
      height -= (margin * 2);

      // Immediately sync layer frames for CSD (content is deferred)
      [CATransaction begin];
      [CATransaction setDisableActions:YES];
      self.rootContainerLayer.frame = self.contentView.bounds;
      [self updateCSDShadowLayer];
      [CATransaction commit];
    }

    // Clamp to minimum 1x1, UNLESS it's 0 (meaning "client decides" or
    // empty). Actually, xdg_shell says 0 means "let client decide". If we
    // have just margins (window size ~60), width becomes 0. If we force 1,
    // client makes 1x1 surface, causing tiny window. If we send 0, client
    // picks preferred size. Clamp to minimum 1x1. We previously allowed 0,
    // but since we now default initial windows to 800x600, we should enforce
    // a strict minimum for resize events to avoid "tiny window" glitches if
    // the user tries to shrink it too much.
    if (width < 1)
      width = 1;
    if (height < 1)
      height = 1;
    if (height < 1)
      height = 1;

    xdg_toplevel_send_configure(self.toplevel->resource, width, height,
                                &states);

    uint32_t serial = ++self.toplevel->xdg_surface->configure_serial;
    xdg_surface_send_configure(self.toplevel->xdg_surface->resource, serial);

    self.toplevel->width = width;
    self.toplevel->height = height;

    wl_array_release(&states);
  }
}

- (void)endResize {
  self.isResizing = NO;
  WLog(@"WINDOW", @"End CSD resize");
}

//==============================================================================
// MARK: - NSWindowDelegate Methods
//==============================================================================

- (void)windowDidResize:(NSNotification *)notification {
  if (self.isResizing) {
    return; // Already handling in continueResizeToPoint
  }

  // Window resized by user (SSD) or programmatically
  NSRect contentRect = [self.window contentRectForFrameRect:self.window.frame];

  WLog(@"WINDOW", @"Window resized to %.0fx%.0f (mode=%d)",
       contentRect.size.width, contentRect.size.height,
       (int)self.decorationMode);

  // Send configure to Wayland client
  if (self.toplevel && self.toplevel->resource && self.toplevel->xdg_surface) {
    extern void xdg_toplevel_send_configure(struct wl_resource * resource,
                                            int32_t width, int32_t height,
                                            struct wl_array *states);
    extern void xdg_surface_send_configure(struct wl_resource * resource,
                                           uint32_t serial);

    // Build states array (activated, resizing if applicable)
    struct wl_array states;
    wl_array_init(&states);

    // Add activated state (window is active)
    uint32_t *state = wl_array_add(&states, sizeof(uint32_t));
    if (state) {
      *state = 4; // XDG_TOPLEVEL_STATE_ACTIVATED
    }

    // For SSD: Send content rect size (client should NOT render decorations)
    // For CSD: Send full window size (client renders everything) MINUS shadow
    // margin
    int32_t configureWidth = (int32_t)contentRect.size.width;
    int32_t configureHeight = (int32_t)contentRect.size.height;

    if (self.decorationMode == WawonaDecorationModeCSD) {
      CGFloat margin = kCSDShadowMargin;
      configureWidth -= (margin * 2);
      configureHeight -= (margin * 2);
    }

    // Clamp to minimum 1x1 for safety, BUT if 0, allow 0 (client decides).
    // However, for user-initiated resize, we usually want to enforce the
    // size. But for initial show, it might be 0. Clamp to minimum 1x1.
    if (configureWidth < 1)
      configureWidth = 1;
    if (configureHeight < 1)
      configureHeight = 1;

    // Send xdg_toplevel.configure with new size
    xdg_toplevel_send_configure(self.toplevel->resource, configureWidth,
                                configureHeight, &states);

    // CRITICAL: Must send xdg_surface.configure to complete the transaction
    uint32_t serial = ++self.toplevel->xdg_surface->configure_serial;
    xdg_surface_send_configure(self.toplevel->xdg_surface->resource, serial);

    // Update toplevel size tracking
    self.toplevel->width = configureWidth;
    self.toplevel->height = configureHeight;

    wl_array_release(&states);

    WLog(@"WINDOW", @"Sent configure: %dx%d serial=%u", configureWidth,
         configureHeight, serial);
  }

  // Update surface layer
  // For SSD: Update immediately since we control the size
  // For CSD: DON'T update immediately - wait for client to commit new buffer
  // Otherwise the window snaps back to old size before client renders

  [CATransaction begin];
  [CATransaction setDisableActions:YES];

  if (self.rootContainerLayer) {
    self.rootContainerLayer.frame = self.contentView.bounds;
  }

  if (self.decorationMode == WawonaDecorationModeCSD) {
    [self updateCSDShadowLayer];
  }

  if (self.surfaceLayer && self.decorationMode == WawonaDecorationModeSSD) {
    [self.surfaceLayer updateContentWithSize:contentRect.size];
    self.surfaceLayer.rootLayer.position = CGPointMake(0, 0);
  } else if (self.surfaceLayer &&
             self.decorationMode == WawonaDecorationModeCSD) {
    // For CSD, we only update the layer position to match the margin
    CGFloat margin = kCSDShadowMargin;
    self.surfaceLayer.rootLayer.position = CGPointMake(margin, margin);
  }

  [CATransaction commit];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
  [self close];
  return NO; // We handle close via Wayland protocol
}

- (void)windowDidMiniaturize:(NSNotification *)notification {
  WLog(@"WINDOW", @"Window miniaturized");
  // Could send minimized state to client here
}

- (void)windowDidDeminiaturize:(NSNotification *)notification {
  WLog(@"WINDOW", @"Window deminiaturized");
  // Could remove minimized state from client here
}

- (void)dealloc {
  WLog(@"WINDOW", @"Deallocating window container for toplevel %p", _toplevel);
  if (_window) {
    [_window close];
  }
}

@end

//==============================================================================
// MARK: - WawonaPopupContainer Implementation
//==============================================================================

@implementation WawonaPopupContainer

- (instancetype)initWithPopup:(struct xdg_popup_impl *)popup
                 parentWindow:(WawonaWindowContainer *)parent
                     position:(CGPoint)position
                         size:(CGSize)size {
  self = [super init];
  if (self) {
    _popup = popup;
    _parentWindow = parent;
    _position = position;

    // Create surface layer for popup
    // _surfaceLayer would be set externally after creation

    // For now, create a simple floating layer
    // In production, decide between floating layer vs child window based on
    // needs
    WLog(@"POPUP", @"Created popup container at (%.0f, %.0f)", position.x,
         position.y);
  }
  return self;
}

- (void)show {
  if (self.childWindow) {
    [self.childWindow orderFront:nil];
  } else if (self.surfaceLayer) {
    self.surfaceLayer.isMapped = YES;
    [self.surfaceLayer setNeedsRedisplay];
  }
  WLog(@"POPUP", @"Showed popup %p", _popup);
}

- (void)hide {
  if (self.childWindow) {
    [self.childWindow orderOut:nil];
  } else if (self.surfaceLayer) {
    self.surfaceLayer.isMapped = NO;
  }
  WLog(@"POPUP", @"Hid popup %p", _popup);
}

- (void)updatePosition:(CGPoint)newPosition {
  self.position = newPosition;

  if (self.childWindow) {
    // Update child window position
    NSRect parentFrame = self.parentWindow.window.frame;
    NSPoint screenPoint = NSMakePoint(parentFrame.origin.x + newPosition.x,
                                      parentFrame.origin.y + newPosition.y);
    [self.childWindow setFrameOrigin:screenPoint];
  } else if (self.surfaceLayer) {
    // Update layer position
    self.surfaceLayer.rootLayer.position = newPosition;
  }

  WLog(@"POPUP", @"Updated popup position to (%.0f, %.0f)", newPosition.x,
       newPosition.y);
}

@end

//==============================================================================
// MARK: - WawonaSurfaceManager Implementation
//==============================================================================

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
    // Use NSMapTable with pointer keys (non-retaining)
    _surfaceLayers =
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory |
                                           NSPointerFunctionsOpaquePersonality
                              valueOptions:NSPointerFunctionsStrongMemory];

    _windowContainers =
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory |
                                           NSPointerFunctionsOpaquePersonality
                              valueOptions:NSPointerFunctionsStrongMemory];

    _popupContainers =
        [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaqueMemory |
                                           NSPointerFunctionsOpaquePersonality
                              valueOptions:NSPointerFunctionsStrongMemory];

    WLog(@"SURFACE_MGR", @"Initialized surface manager");
  }
  return self;
}

- (WawonaSurfaceLayer *)createSurfaceLayerForSurface:
    (struct wl_surface_impl *)surface {
  if (!surface)
    return nil;

  NSValue *key = [NSValue valueWithPointer:surface];
  WawonaSurfaceLayer *existing = [self.surfaceLayers objectForKey:key];
  if (existing) {
    WLog(@"SURFACE_MGR", @"Surface layer already exists for %p", surface);
    return existing;
  }

  WawonaSurfaceLayer *layer =
      [[WawonaSurfaceLayer alloc] initWithSurface:surface];
  [self.surfaceLayers setObject:layer forKey:key];

  WLog(@"SURFACE_MGR", @"Created surface layer for surface %p", surface);
  return layer;
}

- (void)destroySurfaceLayer:(struct wl_surface_impl *)surface {
  if (!surface)
    return;

  NSValue *key = [NSValue valueWithPointer:surface];
  [self.surfaceLayers removeObjectForKey:key];

  WLog(@"SURFACE_MGR", @"Destroyed surface layer for surface %p", surface);
}

- (WawonaSurfaceLayer *)layerForSurface:(struct wl_surface_impl *)surface {
  if (!surface)
    return nil;

  NSValue *key = [NSValue valueWithPointer:surface];
  return [self.surfaceLayers objectForKey:key];
}

- (WawonaWindowContainer *)createWindowForToplevel:
                               (struct xdg_toplevel_impl *)toplevel
                                    decorationMode:(WawonaDecorationMode)mode
                                              size:(CGSize)size {
  if (!toplevel)
    return nil;

  NSValue *key = [NSValue valueWithPointer:toplevel];
  WawonaWindowContainer *existing = [self.windowContainers objectForKey:key];
  if (existing) {
    WLog(@"SURFACE_MGR", @"Window container already exists for toplevel %p",
         toplevel);
    return existing;
  }

  WawonaWindowContainer *container =
      [[WawonaWindowContainer alloc] initWithToplevel:toplevel
                                       decorationMode:mode
                                                 size:size];
  [self.windowContainers setObject:container forKey:key];

  // Create surface layer for the toplevel's surface
  if (toplevel->xdg_surface && toplevel->xdg_surface->wl_surface) {
    WawonaSurfaceLayer *surfaceLayer =
        [self createSurfaceLayerForSurface:toplevel->xdg_surface->wl_surface];
    container.surfaceLayer = surfaceLayer;
  }

  WLog(@"SURFACE_MGR", @"Created window container for toplevel %p (mode=%d)",
       toplevel, (int)mode);
  return container;
}

- (void)destroyWindowForToplevel:(struct xdg_toplevel_impl *)toplevel {
  if (!toplevel)
    return;

  NSValue *key = [NSValue valueWithPointer:toplevel];
  WawonaWindowContainer *container = [self.windowContainers objectForKey:key];

  if (container) {
    // Destroy associated surface layer
    if (toplevel->xdg_surface && toplevel->xdg_surface->wl_surface) {
      [self destroySurfaceLayer:toplevel->xdg_surface->wl_surface];
    }

    [self.windowContainers removeObjectForKey:key];
    WLog(@"SURFACE_MGR", @"Destroyed window container for toplevel %p",
         toplevel);
  }
}

- (WawonaWindowContainer *)windowForToplevel:
    (struct xdg_toplevel_impl *)toplevel {
  if (!toplevel)
    return nil;

  NSValue *key = [NSValue valueWithPointer:toplevel];
  return [self.windowContainers objectForKey:key];
}

- (WawonaPopupContainer *)createPopup:(struct xdg_popup_impl *)popup
                         parentWindow:(WawonaWindowContainer *)parent
                             position:(CGPoint)position
                                 size:(CGSize)size {
  if (!popup)
    return nil;

  NSValue *key = [NSValue valueWithPointer:popup];
  WawonaPopupContainer *container =
      [[WawonaPopupContainer alloc] initWithPopup:popup
                                     parentWindow:parent
                                         position:position
                                             size:size];
  [self.popupContainers setObject:container forKey:key];

  // Create surface layer for popup
  if (popup->xdg_surface && popup->xdg_surface->wl_surface) {
    WawonaSurfaceLayer *surfaceLayer =
        [self createSurfaceLayerForSurface:popup->xdg_surface->wl_surface];
    container.surfaceLayer = surfaceLayer;
  }

  WLog(@"SURFACE_MGR", @"Created popup container for popup %p", popup);
  return container;
}

- (void)destroyPopup:(struct xdg_popup_impl *)popup {
  if (!popup)
    return;

  NSValue *key = [NSValue valueWithPointer:popup];
  WawonaPopupContainer *container = [self.popupContainers objectForKey:key];

  if (container) {
    // Destroy associated surface layer
    if (popup->xdg_surface && popup->xdg_surface->wl_surface) {
      [self destroySurfaceLayer:popup->xdg_surface->wl_surface];
    }

    [self.popupContainers removeObjectForKey:key];
    WLog(@"SURFACE_MGR", @"Destroyed popup container for popup %p", popup);
  }
}

- (void)renderSurface:(struct wl_surface_impl *)surface {
  WawonaSurfaceLayer *layer = [self layerForSurface:surface];
  if (layer && layer.isMapped) {
    [layer setNeedsRedisplay];
  }
}

- (void)setNeedsDisplayForAllSurfaces {
  for (WawonaSurfaceLayer *layer in [self.surfaceLayers objectEnumerator]) {
    if (layer.isMapped) {
      [layer setNeedsRedisplay];
    }
  }
}

@end
