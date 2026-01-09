// WawonaSurfaceManager.h - CALayer-based Wayland Surface Management
// Implements the compositor architecture from docs/2026-xdg-decoration.md
//
// Key architectural principles:
// - All Wayland surfaces map to CALayers
// - Only SSD toplevels get NSWindow
// - CSD toplevels use borderless NSWindow + custom layers
// - Shadows are separate click-through layers for CSD
// - Multi-surface support via CALayer hierarchy

#pragma once

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

#include <wayland-server-core.h>

// Forward declarations
struct wl_surface_impl;
struct xdg_toplevel_impl;
struct xdg_popup_impl;

// Decoration mode enum (matches xdg-decoration protocol)
typedef NS_ENUM(NSUInteger, WawonaDecorationMode) {
  WawonaDecorationModeUnset = 0,
  WawonaDecorationModeCSD = 1, // Client-Side Decorations
  WawonaDecorationModeSSD = 2  // Server-Side Decorations
};

// Constants for CSD resize detection and shadow margins
extern const CGFloat kResizeEdgeInset;  // pixels from edge
extern const CGFloat kResizeCornerSize; // corner region size
extern const CGFloat kCSDShadowMargin;  // Margin for client-side shadows

// Surface layer representation
// Each Wayland surface gets its own layer tree
@interface WawonaSurfaceLayer : NSObject

@property(nonatomic, readonly) struct wl_surface_impl *surface;

// Layer hierarchy
@property(nonatomic, strong) CALayer *rootLayer; // Root container
@property(nonatomic, strong)
    CAMetalLayer *contentLayer; // Surface content (GPU)
@property(nonatomic, strong)
    NSMutableArray<CALayer *> *subsurfaceLayers; // Child surfaces

// Surface state
@property(nonatomic, assign) CGRect geometry;
@property(nonatomic, assign) BOOL needsDisplay;
@property(nonatomic, assign) BOOL isMapped;

- (instancetype)initWithSurface:(struct wl_surface_impl *)surface;
- (void)updateContentWithSize:(CGSize)size;
- (void)addSubsurfaceLayer:(CALayer *)sublayer atIndex:(NSInteger)index;
- (void)removeSubsurfaceLayer:(CALayer *)sublayer;
- (void)setNeedsRedisplay;

@end

// Window representation for toplevels
// Manages the NSWindow and its surface layers
@interface WawonaWindowContainer : NSObject

@property(nonatomic, readonly) struct xdg_toplevel_impl *toplevel;
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong)
    CALayer *rootContainerLayer; // Root container for both shadow and content
@property(nonatomic, strong)
    CALayer *csdShadowLayer; // Shadow (CSD only, click-through)
@property(nonatomic, strong) WawonaSurfaceLayer *surfaceLayer;
@property(nonatomic, assign) WawonaDecorationMode decorationMode;

// CSD-specific properties
@property(nonatomic, assign) BOOL isResizing;
@property(nonatomic, assign) NSRectEdge resizeEdge;
@property(nonatomic, assign) CGPoint resizeStartPoint;
@property(nonatomic, assign) CGRect resizeStartFrame;

- (instancetype)initWithToplevel:(struct xdg_toplevel_impl *)toplevel
                  decorationMode:(WawonaDecorationMode)mode
                            size:(CGSize)size;

// Replaces the content view while preserving the layer hierarchy
- (void)replaceContentView:(NSView *)newView;

// Window management
- (void)show;
- (void)hide;
- (void)close;
- (void)minimize;
- (void)maximize;
- (void)updateDecorationMode:(WawonaDecorationMode)mode;
- (void)setTitle:(NSString *)title;
- (void)resize:(CGSize)newSize;

// CSD resize handling
- (NSRectEdge)detectResizeEdgeAtPoint:(CGPoint)point;
- (void)beginResizeWithEdge:(NSRectEdge)edge atPoint:(CGPoint)point;
- (void)continueResizeToPoint:(CGPoint)point;
- (void)endResize;

// Lifecycle safety
- (void)invalidateToplevel;

@end

// Popup window representation
// Handles xdg_popup surfaces as floating layers or child windows
@interface WawonaPopupContainer : NSObject

@property(nonatomic, readonly) struct xdg_popup_impl *popup;
@property(nonatomic, strong) WawonaSurfaceLayer *surfaceLayer;
@property(nonatomic, weak) WawonaWindowContainer *parentWindow;

// Popup can be either a floating layer or a child window
@property(nonatomic, strong)
    NSWindow *childWindow; // Optional: for popups that need separate window
@property(nonatomic, assign) CGPoint position; // Position relative to parent

- (instancetype)initWithPopup:(struct xdg_popup_impl *)popup
                 parentWindow:(WawonaWindowContainer *)parent
                     position:(CGPoint)position
                         size:(CGSize)size;

- (void)show;
- (void)hide;
- (void)updatePosition:(CGPoint)newPosition;

@end

// Main surface manager
// Manages all surface layers and window containers
@interface WawonaSurfaceManager : NSObject

// Surface registry
@property(nonatomic, strong)
    NSMapTable<NSValue *, WawonaSurfaceLayer *> *surfaceLayers;
@property(nonatomic, strong)
    NSMapTable<NSValue *, WawonaWindowContainer *> *windowContainers;
@property(nonatomic, strong)
    NSMapTable<NSValue *, WawonaPopupContainer *> *popupContainers;

+ (instancetype)sharedManager;

// Surface lifecycle
- (WawonaSurfaceLayer *)createSurfaceLayerForSurface:
    (struct wl_surface_impl *)surface;
- (void)destroySurfaceLayer:(struct wl_surface_impl *)surface;
- (WawonaSurfaceLayer *)layerForSurface:(struct wl_surface_impl *)surface;

// Toplevel window management
- (WawonaWindowContainer *)createWindowForToplevel:
                               (struct xdg_toplevel_impl *)toplevel
                                    decorationMode:(WawonaDecorationMode)mode
                                              size:(CGSize)size;
- (void)destroyWindowForToplevel:(struct xdg_toplevel_impl *)toplevel;
- (WawonaWindowContainer *)windowForToplevel:
    (struct xdg_toplevel_impl *)toplevel;

// Popup management
- (WawonaPopupContainer *)createPopup:(struct xdg_popup_impl *)popup
                         parentWindow:(WawonaWindowContainer *)parent
                             position:(CGPoint)position
                                 size:(CGSize)size;
- (void)destroyPopup:(struct xdg_popup_impl *)popup;

// Rendering
- (void)renderSurface:(struct wl_surface_impl *)surface;
- (void)setNeedsDisplayForAllSurfaces;

@end
