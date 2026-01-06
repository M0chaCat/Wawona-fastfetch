#pragma once

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#include "WawonaCompositor.h"
#import <CoreGraphics/CoreGraphics.h>

// Forward declaration
@class SurfaceImage;

// Surface Renderer - Converts Wayland buffers to Cocoa/UIKit drawing
// Uses NSView/UIView drawing (like OWL compositor) instead of CALayer
@interface SurfaceRenderer : NSObject <RenderingBackend>

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@property(nonatomic, weak)
    UIView *compositorView; // The view we draw into (weak to prevent dangling
                            // pointer in ARC)
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber *, SurfaceImage *> *surfaceImages;

- (instancetype)initWithCompositorView:(UIView *)view;
- (void)renderSurface:(struct wl_surface_impl *)surface;
- (void)removeSurface:(struct wl_surface_impl *)surface;
- (void)drawSurfacesInRect:(CGRect)dirtyRect; // Called from drawRect:
#else
@property(nonatomic, weak)
    NSView *compositorView; // The view we draw into (weak to prevent dangling
                            // pointer in ARC)
@property(nonatomic, weak)
    NSWindow *window; // Associated window for filtering surfaces
@property(nonatomic, strong)
    NSMutableDictionary<NSNumber *, SurfaceImage *> *surfaceImages;

- (instancetype)initWithCompositorView:(NSView *)view;
- (void)renderSurface:(struct wl_surface_impl *)surface;
- (void)removeSurface:(struct wl_surface_impl *)surface;
- (void)drawSurfacesInRect:(NSRect)dirtyRect; // Called from drawRect:
#endif

@end
