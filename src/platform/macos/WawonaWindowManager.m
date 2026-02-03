// WawonaWindowManager.m - Window sizing and display management implementation
// Extracted from WawonaCompositor.m for better organization

#import "WawonaWindowManager.h"
#import "WawonaCompositor.h"
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import "WawonaCompositorView_ios.h"
#else
#import "WawonaCompositorView_macos.h"
#endif
#import "../compositor_implementations/wayland_output.h"
#import "../compositor_implementations/xdg_shell.h"
#include "../logging/logging.h"

@implementation WawonaWindowManager {
  WawonaCompositor *_compositor;
}

- (instancetype)initWithCompositor:(WawonaCompositor *)compositor {
  self = [super init];
  if (self) {
    _compositor = compositor;
  }
  return self;
}

- (void)showAndSizeWindowForFirstClient:(int32_t)width height:(int32_t)height {
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  CGRect windowFrame = CGRectMake(0, 0, width, height);
  _compositor.window.frame = windowFrame;
#else
  // macOS: Calculate window frame with titlebar
  NSRect contentRect = NSMakeRect(0, 0, width, height);
  NSRect windowFrame = [_compositor.window frameRectForContentRect:contentRect];

  // Center window on screen
  NSScreen *screen = [NSScreen mainScreen];
  NSRect screenFrame =
      screen ? screen.visibleFrame : NSMakeRect(0, 0, 1920, 1080);
  CGFloat x = screenFrame.origin.x +
              (screenFrame.size.width - windowFrame.size.width) / 2;
#endif
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // iOS: Ensure view matches window (respecting safe area if enabled)
  UIView *contentView = _compositor.window.rootViewController.view;

  // Check if we should respect safe area
  BOOL respectSafeArea =
      [[NSUserDefaults standardUserDefaults] boolForKey:@"RespectSafeArea"];
  if ([[NSUserDefaults standardUserDefaults] objectForKey:@"RespectSafeArea"] ==
      nil) {
    respectSafeArea = YES; // Default to YES
  }

  if (respectSafeArea && [contentView isKindOfClass:[CompositorView class]]) {
    CompositorView *compositorView = (CompositorView *)contentView;
    [compositorView setNeedsLayout];
    [compositorView layoutIfNeeded];

    // Calculate safe area frame
    CGRect windowBounds = _compositor.window.bounds;
    CGRect safeAreaFrame = windowBounds;

    UILayoutGuide *safeArea = _compositor.window.safeAreaLayoutGuide;
    safeAreaFrame = safeArea.layoutFrame;
    if (CGRectIsEmpty(safeAreaFrame)) {
      UIEdgeInsets insets = compositorView.safeAreaInsets;
      if (insets.top != 0 || insets.left != 0 || insets.bottom != 0 ||
          insets.right != 0) {
        safeAreaFrame = UIEdgeInsetsInsetRect(windowBounds, insets);
      }
    }

    compositorView.frame = safeAreaFrame;
    compositorView.autoresizingMask = UIViewAutoresizingNone;
    NSLog(@"🔵 CompositorView frame set to safe area in "
          @"showAndSizeWindowForFirstClient: (%.0f, %.0f) %.0fx%.0f",
          safeAreaFrame.origin.x, safeAreaFrame.origin.y,
          safeAreaFrame.size.width, safeAreaFrame.size.height);
  } else {
    contentView.frame = _compositor.window.bounds;
    if ([contentView isKindOfClass:[CompositorView class]]) {
      CompositorView *compositorView = (CompositorView *)contentView;
      compositorView.autoresizingMask =
          (UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight);
    }
  }
#else
  CGFloat y = screenFrame.origin.y +
              (screenFrame.size.height - windowFrame.size.height) / 2;
  windowFrame.origin = NSMakePoint(x, y);

  // Set window frame
  [_compositor.window
      setFrame:windowFrame
       display:YES]; // Use display:YES to ensure immediate update

  // CRITICAL: Ensure content view frame matches window content rect
  // The content view might have been initialized with a different size
  // (800x600)
  NSView *contentView = _compositor.window.contentView;
  NSRect contentViewFrame =
      [_compositor.window contentRectForFrameRect:windowFrame];
  contentViewFrame.origin =
      NSMakePoint(0, 0); // Content view origin is always (0,0)
  contentView.frame = contentViewFrame;
#endif
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
  NSLog(@"[WINDOW] Content view resized to: %.0fx%.0f",
        contentViewFrame.size.width, contentViewFrame.size.height);
#endif

  // Ensure Metal view (if exists) matches window size before showing
  if ([contentView isKindOfClass:[CompositorView class]]) {
    CompositorView *compositorView = (CompositorView *)contentView;

    // If Metal view exists, ensure it matches the window content size
    if (_compositor.backendType == 1 && compositorView.metalView) {
      // Metal view frame should match content view bounds (in points)
      // CRITICAL: Do NOT manually set bounds - MTKView handles this
      // automatically Setting bounds manually interferes with MTKView's
      // Retina scaling logic
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
      CGRect contentBounds = compositorView.bounds;
      compositorView.metalView.frame = contentBounds;
      [compositorView.metalView setNeedsDisplay];
#else
      NSRect contentBounds = compositorView.bounds;
      compositorView.metalView.frame = contentBounds;
      [compositorView.metalView setNeedsDisplay:YES];
#endif
      // MTKView automatically sets bounds to match frame - don't override!
      // The drawableSize will be automatically calculated based on frame size
      // and Retina scale
      NSLog(@"[WINDOW] Metal view sized to match window content: "
            @"frame=%.0fx%.0f (MTKView handles bounds/drawable automatically)",
            contentBounds.size.width, contentBounds.size.height);
    }
  }

  // Update output size (respecting Safe Area on iOS)
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  // Use the actual contentView size (which may be safe area if respecting)
  UIView *contentViewForSize = _compositor.window.rootViewController.view;
  [self updateOutputSize:contentViewForSize.bounds.size];
#else
  if (_compositor.window) {
    [self updateOutputSize:_compositor.window.contentView.bounds.size];
  } else {
    // If no main window, use the first client's size as the initial output
    // size
    [self updateOutputSize:NSMakeSize(width, height)];
  }
#endif

  if (_compositor.xdg_wm_base) {
    xdg_wm_base_set_output_size(_compositor.xdg_wm_base, width, height);
  }

  // Show window and make it key
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  _compositor.window.hidden = NO;
  [_compositor.window makeKeyWindow];
#else
  [_compositor.window makeKeyAndOrderFront:nil];
  [NSApp activateIgnoringOtherApps:YES];
  [_compositor.window becomeKeyWindow];

  // Make the compositor view first responder to receive keyboard events
  // (contentView already declared above)
  if ([contentView isKindOfClass:[CompositorView class]]) {
    [_compositor.window makeFirstResponder:contentView];
    NSLog(@"[INPUT] View set as first responder when window shown");
  }
#endif

  _compositor.windowShown = YES;

  NSLog(@"[WINDOW] Window shown and sized to %dx%d", width, height);
}

- (void)updateOutputSize:(CGSize)size {
  CompositorView *compositorView = nil;
  CGRect outputRect;
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  UIView *containerView = _compositor.window.rootViewController.view;
  for (UIView *subview in containerView.subviews) {
    if ([subview isKindOfClass:[CompositorView class]]) {
      compositorView = (CompositorView *)subview;
      break;
    }
  }
  if (!compositorView && [containerView isKindOfClass:[CompositorView class]]) {
    compositorView = (CompositorView *)containerView;
  }
  if (compositorView) {
    [compositorView setNeedsLayout];
    [compositorView layoutIfNeeded];
    outputRect = compositorView.bounds;
  } else {
    outputRect = CGRectMake(0, 0, size.width, size.height);
  }
#else
  NSView *contentView = _compositor.window.contentView;
  if ([contentView isKindOfClass:[CompositorView class]]) {
    compositorView = (CompositorView *)contentView;
    outputRect = compositorView.bounds;
  } else {
    outputRect = CGRectMake(0, 0, size.width, size.height);
  }

  // Fallback if output size is still empty (e.g. headless init)
  if (outputRect.size.width <= 0 || outputRect.size.height <= 0) {
    outputRect = CGRectMake(0, 0, 1920, 1080);
  }
#endif

  // Convert points to pixels for Retina displays
  // CRITICAL: Use the screen's actual scale factor for proper DPI/Retina
  // scaling
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
  CGFloat scale = [UIScreen mainScreen].scale;
  if (scale <= 0) {
    scale = 1.0;
  }
#else
  CGFloat scale = _compositor.window.backingScaleFactor;
  if (scale <= 0) {
    scale = 1.0;
  }
#endif

  // Calculate pixel dimensions: points * scale = pixels
  // Example: 375 points * 3 scale = 1125 pixels (iPhone 14 Pro)
  int32_t pixelWidth = (int32_t)round(outputRect.size.width * scale);
  int32_t pixelHeight = (int32_t)round(outputRect.size.height * scale);
  int32_t scaleInt = (int32_t)scale;

  NSLog(@"🔵 Output scaling: %.0fx%.0f points @ %.0fx scale = %dx%d pixels",
        outputRect.size.width, outputRect.size.height, scale, pixelWidth,
        pixelHeight);

  // Store logical dimensions (points) for Wayland xdg-shell protocol
  // Wayland specifies dimensions in logical coordinates.
  _compositor.pending_resize_width = (int32_t)outputRect.size.width;
  _compositor.pending_resize_height = (int32_t)outputRect.size.height;
  _compositor.pending_resize_scale = scaleInt;
  _compositor.needs_resize_configure = YES;
}

@end
