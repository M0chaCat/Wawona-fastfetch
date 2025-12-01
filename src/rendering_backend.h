#pragma once

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

// Forward declaration
struct wl_surface_impl;

// Rendering Backend Interface
// Abstract interface for different rendering backends (SurfaceRenderer, MetalRenderer, etc.)

@protocol RenderingBackend <NSObject>

@required
- (void)renderSurface:(struct wl_surface_impl *)surface;
- (void)removeSurface:(struct wl_surface_impl *)surface;
- (void)setNeedsDisplay;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)drawSurfacesInRect:(CGRect)dirtyRect;
#else
- (void)drawSurfacesInRect:(NSRect)dirtyRect;
#endif

@optional
- (void)initialize;
- (void)cleanup;

@end


// Rendering Backend Types
typedef NS_ENUM(NSInteger, RenderingBackendType) {
    RENDERING_BACKEND_SURFACE,    // SurfaceRenderer (Cocoa/UIKit drawing)
    RENDERING_BACKEND_METAL,      // MetalRenderer (Metal GPU rendering)
    RENDERING_BACKEND_VULKAN      // VulkanRenderer (future implementation)
};

// Rendering Backend Factory
@interface RenderingBackendFactory : NSObject

+ (id<RenderingBackend>)createBackend:(RenderingBackendType)type 
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
                         withView:(UIView *)view;
#else
                         withView:(NSView *)view;
#endif

@end
