#import "renderer_apple.h"
#import "../util/WWNLog.h"
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>

@implementation WWNRendererApple {
  id<MTLDevice> device;
  id<MTLCommandQueue> commandQueue;
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (instancetype)initWithView:(UIView *)view {
  self = [super init];
  if (self) {
    device = MTLCreateSystemDefaultDevice();
    commandQueue = [device newCommandQueue];
    WWNLog("RENDERER", @"WWNRendererApple initialized for iOS");
  }
  return self;
}
#else
- (instancetype)initWithView:(NSView *)view {
  self = [super init];
  if (self) {
    device = MTLCreateSystemDefaultDevice();
    commandQueue = [device newCommandQueue];
    WWNLog("RENDERER", @"WWNRendererApple initialized for macOS");
  }
  return self;
}
#endif

- (void)renderSurface:(struct wl_surface_impl *)surface {
  // Basic stub for surface rendering
  // On iOS, surface content is currently handled by CALayers in
  // WWNCompositorView_ios
  static BOOL loggedOnce = NO;
  if (!loggedOnce) {
    WWNLog("RENDERER", @"WWNRendererApple renderSurface called (Stub)");
    loggedOnce = YES;
  }
}

- (void)removeSurface:(struct wl_surface_impl *)surface {
  WWNLog("RENDERER", @"WWNRendererApple removeSurface called (Stub)");
}

- (void)setNeedsDisplay {
  // Trigger redraw
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)drawSurfacesInRect:(CGRect)dirtyRect {
  // iOS specific draw logic (Stub)
}
#else
- (void)drawSurfacesInRect:(NSRect)dirtyRect {
  // macOS specific draw logic
}
#endif

@end
