#pragma once

#import <Foundation/Foundation.h>
#if TARGET_OS_OSX
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#endif

// Forward declarations
struct wl_surface_impl;

// Platform-specific renderer interface
#import "RenderingBackend.h"

@interface WWNRendererApple : NSObject <RenderingBackend>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (instancetype)initWithView:(UIView *)view;
#else
- (instancetype)initWithView:(NSView *)view;
#endif

- (void)renderSurface:(struct wl_surface_impl *)surface;
- (void)removeSurface:(struct wl_surface_impl *)surface;
- (void)setNeedsDisplay;
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
- (void)drawSurfacesInRect:(NSRect)dirtyRect;
#endif
@end

#ifdef __cplusplus
extern "C" {
#endif

// Public C interface for compositor integration
// These functions handle the rendering pipeline for Wayland surfaces

// Callback function for Wayland surface commits
// Called when a client commits a new buffer to a surface
void wawona_render_surface_callback(struct wl_surface_impl *surface);

// Find the appropriate renderer for a given surface
// Returns the renderer associated with the surface's window, or the fallback
// renderer
id<RenderingBackend>
wawona_find_renderer_for_surface(struct wl_surface_impl *surface);

// Immediately render a surface to its associated window/renderer
// This is called from the render callback to trigger the actual rendering
void wawona_render_surface_immediate(struct wl_surface_impl *surface);

#ifdef __cplusplus
}
#endif
