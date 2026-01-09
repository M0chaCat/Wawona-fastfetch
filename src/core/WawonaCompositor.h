#pragma once
#include <stdint.h>
#include <wayland-server-protocol.h>
#include <wayland-server.h>

#ifndef WAWONA_COMPOSITOR_TYPE_DEFINED
#define WAWONA_COMPOSITOR_TYPE_DEFINED
#ifdef __OBJC__
@class WawonaCompositor;
#else
typedef struct WawonaCompositor WawonaCompositor;
#endif
#endif

#include "../compositor_implementations/wayland_compositor.h"

// Clear buffer reference from surfaces (called when buffer is destroyed)
void wl_compositor_clear_buffer_reference(struct wl_resource *buffer_resource);

// Destroy all tracked clients (for shutdown) - explicitly disconnects all
// clients including waypipe
void wl_compositor_destroy_all_clients(void);

// C function to check if window should be hidden (called when client
// disconnects)
void macos_compositor_check_and_hide_window_if_needed(void);

// C function to set CSD mode for a toplevel (hide/show macOS window
// decorations)
struct xdg_toplevel_impl;
void macos_compositor_set_csd_mode_for_toplevel(
    struct xdg_toplevel_impl *toplevel, bool csd);

// C function to activate/raise the window (called from activation protocol)
void macos_compositor_activate_window(void);

// C function to update window title when no clients are connected
void macos_compositor_update_title_no_clients(void);
// C function to manage window states
void macos_toplevel_set_minimized(struct xdg_toplevel_impl *toplevel);
void macos_toplevel_set_maximized(struct xdg_toplevel_impl *toplevel);
void macos_toplevel_unset_maximized(struct xdg_toplevel_impl *toplevel);
void macos_toplevel_close(struct xdg_toplevel_impl *toplevel);
void macos_start_toplevel_resize(struct xdg_toplevel_impl *toplevel,
                                 uint32_t edges);
void macos_start_toplevel_move(struct xdg_toplevel_impl *toplevel);
void macos_toplevel_set_fullscreen(struct xdg_toplevel_impl *toplevel);
void macos_toplevel_unset_fullscreen(struct xdg_toplevel_impl *toplevel);
void macos_toplevel_set_min_size(struct xdg_toplevel_impl *toplevel,
                                 int32_t width, int32_t height);
void macos_toplevel_set_max_size(struct xdg_toplevel_impl *toplevel,
                                 int32_t width, int32_t height);
void macos_unregister_toplevel(struct xdg_toplevel_impl *toplevel);

// C function to flush clients and trigger immediate frame callback
void wl_compositor_flush_and_trigger_frame(void);

// C function to create a native window for a toplevel
void macos_create_window_for_toplevel(struct xdg_toplevel_impl *toplevel);

#ifdef __OBJC__
@class WawonaCompositor;
@class CompositorView;
@class WawonaEventLoopManager;
@class WawonaClientManager;
@class WawonaProtocolSetup;
@class WawonaWindowManager;
@class WawonaRenderManager;
@class WawonaStartupManager;
@class WawonaShutdownManager;
#else
typedef struct WawonaCompositor WawonaCompositor;
#endif
extern WawonaCompositor *g_wl_compositor_instance;

#ifdef __OBJC__
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#include "../input/input_handler.h"
#include "../input/wayland_seat.h"
#include "RenderingBackend.h"
#include "launcher/WawonaAppScanner.h"
#include "wayland_color_management.h"
#include "wayland_data_device_manager.h"
#include "wayland_decoration.h"
#include "wayland_output.h"
#include "wayland_presentation.h"
#include "wayland_shm.h"
#include "wayland_subcompositor.h"
#include "xdg_shell.h"

// macOS Wayland Compositor Backend
// This is a from-scratch implementation - no WLRoots

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@interface WawonaCompositor : NSObject
@property(nonatomic, strong) UIWindow *window;
#else
@interface WawonaCompositor : NSObject <NSWindowDelegate>
@property(nonatomic, strong) NSWindow *window;
#endif
@property(nonatomic, assign) struct wl_display *display;
@property(nonatomic, assign) struct wl_event_loop *eventLoop;
@property(nonatomic, strong) NSThread *eventThread;

// Dispatch a block to be executed on the Wayland event thread
- (void)dispatchToEventThread:(void (^)(void))block;

// fixCSDWindowResizing: is declared in WawonaCompositor_macos.h
// (macOS-specific)

@property(nonatomic, assign)
    int tcp_listen_fd; // TCP listening socket (for manual accept)
@property(nonatomic, strong) id<RenderingBackend>
    renderingBackend; // Rendering backend (SurfaceRenderer or MetalRenderer)
@property(nonatomic, assign) RenderingBackendType
    backendType; // RENDERING_BACKEND_SURFACE or RENDERING_BACKEND_METAL
@property(nonatomic, strong) InputHandler *inputHandler;
@property(nonatomic, strong) WawonaAppScanner *launcher; // App scanner

// Wayland protocol implementations
@property(nonatomic, assign) struct wl_compositor_impl *compositor;
@property(nonatomic, assign) struct wl_output_impl *output;
@property(nonatomic, assign) struct wl_seat_impl *seat;
@property(nonatomic, assign) struct wl_shm_impl *shm;
@property(nonatomic, assign) struct wl_subcompositor_impl *subcompositor;
@property(nonatomic, assign)
    struct wl_decoration_manager_impl *decoration_manager;
@property(nonatomic, assign)
    struct wl_data_device_manager_impl *data_device_manager;
@property(nonatomic, assign) struct xdg_wm_base_impl *xdg_wm_base;
@property(nonatomic, assign) struct wp_color_manager_impl *color_manager;
@property(nonatomic, assign)
    struct wl_text_input_manager_impl *text_input_manager;

// Event loop integration
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@property(nonatomic, strong) CADisplayLink *displayLink;
#else
@property(nonatomic, assign) CVDisplayLinkRef displayLink;
#endif
@property(nonatomic, assign) BOOL shouldStopEventThread;
@property(nonatomic, strong) WawonaEventLoopManager *eventLoopManager;
@property(nonatomic, strong) WawonaWindowManager *windowManager;
@property(nonatomic, strong) WawonaRenderManager *renderManager;
@property(nonatomic, strong) WawonaStartupManager *startupManager;
@property(nonatomic, strong) WawonaShutdownManager *shutdownManager;
@property(nonatomic, assign) struct wl_event_source *frame_callback_source;
@property(nonatomic, assign) int32_t pending_resize_width;
@property(nonatomic, assign) int32_t pending_resize_height;
@property(nonatomic, assign) int32_t pending_resize_scale;
@property(nonatomic, assign) volatile BOOL needs_resize_configure;
@property(nonatomic, assign) BOOL
    windowShown; // Track if window has been shown (delayed until first client)
@property(nonatomic, assign)
    BOOL isFullscreen; // Track if window is in fullscreen mode
@property(nonatomic, strong) NSTimer
    *fullscreenExitTimer; // Timer to exit fullscreen after client disconnects
@property(nonatomic, assign)
    NSUInteger connectedClientCount; // Track number of connected clients
@property(nonatomic, strong) NSMutableDictionary
    *windowToToplevelMap; // Map NSWindow to xdg_toplevel_impl
@property(atomic, strong) NSMutableArray<NSWindow *> *nativeWindows;
// Map toplevel struct pointers to RenderingBackend objects
// Key: NSValue(pointer: toplevel), Value: id<RenderingBackend>
@property(atomic, strong)
    NSMutableDictionary *toplevelToRendererMap; // Array of NSWindow (strong) to
                                                // retain created windows
@property(nonatomic, strong) CompositorView *mainCompositorView;
@property(nonatomic, strong)
    NSRecursiveLock *mapLock; // Lock for windowToToplevelMap
@property(nonatomic, assign) BOOL isLiveResizing;
@property(nonatomic, assign) NSRect liveResizeStartFrame;
@property(nonatomic, assign) uint32_t activeResizeEdges;
@property(nonatomic, assign) BOOL stopped;

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (instancetype)initWithDisplay:(struct wl_display *)display
                         window:(UIWindow *)window;
#else
- (instancetype)initWithDisplay:(struct wl_display *)display
                         window:(NSWindow *)window;
#endif
- (BOOL)start;
- (void)stop;
- (BOOL)processWaylandEvents; // Returns YES if events were processed
- (void)renderFrame;
- (void)sendFrameCallbacksImmediately; // Force immediate frame callback
                                       // dispatch (for input events)
- (void)switchToMetalBackend; // Switch to Metal rendering for full compositors
- (void)updateWindowTitleForClient:
    (struct wl_client *)client; // Update window title with client name
- (void)showAndSizeWindowForFirstClient:(int32_t)width
                                 height:(int32_t)
                                            height; // Show and size window when
                                                    // first client connects
- (void)updateOutputSize:
    (CGSize)size; // Update output size and notify clients (called on resize)

@end

// C function to get EGL buffer handler (for rendering EGL buffers)
#endif // __OBJC__
