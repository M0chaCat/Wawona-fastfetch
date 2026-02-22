#import "RenderingBackend.h"
#import "renderer_apple.h"

@implementation RenderingBackendFactory

+ (id<RenderingBackend>)createBackend:(RenderingBackendType)type
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
                             withView:(UIView *)view
#else
                             withView:(NSView *)view
#endif
{
  // Map requests to platform-specific renderers
  // Use the unified Apple renderer
  return [[WWNRendererApple alloc] initWithView:view];
}

@end
