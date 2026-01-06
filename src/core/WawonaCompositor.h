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

// Forward declaration
struct wl_seat_impl;

// Wayland Compositor Protocol Implementation
// Implements wl_compositor, wl_surface, wl_output, wl_seat

struct wl_compositor_impl;
struct wl_surface_impl;
struct wl_output_impl;

// Render callback type - called when a surface is committed
typedef void (*wl_surface_render_callback_t)(struct wl_surface_impl *surface);

// Title update callback type - called when focus changes to update window title
typedef void (*wl_title_update_callback_t)(struct wl_client *client);

// Frame callback requested callback type - called when a client requests a
// frame callback
typedef void (*wl_frame_callback_requested_t)(void);

// Compositor global
struct wl_compositor_impl {
  struct wl_global *global;
  struct wl_display *display;
  wl_surface_render_callback_t
      render_callback; // Callback for immediate rendering
  wl_title_update_callback_t
      update_title_callback; // Callback for updating window title
  wl_frame_callback_requested_t
      frame_callback_requested; // Callback when frame callback is requested
};

// Surface implementation
struct wl_surface_impl {
  struct wl_resource *resource;
  struct wl_surface_impl *next;

  // Buffer management
  struct wl_resource *buffer_resource;
  int32_t width, height;
  int32_t buffer_width, buffer_height;
  int32_t buffer_scale;
  int32_t buffer_transform;
  bool buffer_release_sent;

  // Position and state
  int32_t x, y;
  bool committed;
  bool configured;                   // Track if xdg-shell surface is configured
  uint32_t pending_configure_serial; // Last sent configure serial

  // Damage management
  struct wl_array pending_damage;

  // Callbacks
  struct wl_resource *frame_callback;

  // Viewport (for viewporter protocol)
  void *viewport; // struct wl_viewport_impl *

  // User data (for linking to CALayer)
  void *user_data;

  // Tree structure for subsurfaces
  struct wl_surface_impl *parent;

  // Color management
  void *color_management; // struct wp_color_management_surface_impl *
};

// Function declarations
struct wl_compositor_impl *wl_compositor_create(struct wl_display *display);
void wl_compositor_destroy(struct wl_compositor_impl *compositor);
void wl_compositor_set_render_callback(struct wl_compositor_impl *compositor,
                                       wl_surface_render_callback_t callback);
void wl_compositor_set_title_update_callback(
    struct wl_compositor_impl *compositor, wl_title_update_callback_t callback);
void wl_compositor_set_frame_callback_requested(
    struct wl_compositor_impl *compositor,
    wl_frame_callback_requested_t callback);
void wl_compositor_set_seat(struct wl_seat_impl *seat);

// Thread-safe surface iteration
typedef void (*wl_surface_iterator_func_t)(struct wl_surface_impl *surface,
                                           void *data);
void wl_compositor_for_each_surface(wl_surface_iterator_func_t iterator,
                                    void *data);

// Lock/Unlock surfaces mutex (for external safe access)
void wl_compositor_lock_surfaces(void);
void wl_compositor_unlock_surfaces(void);

// Surface management
struct wl_surface_impl *wl_surface_from_resource(struct wl_resource *resource);
void wl_surface_damage(struct wl_surface_impl *surface, int32_t x, int32_t y,
                       int32_t width, int32_t height);
void wl_surface_commit(struct wl_surface_impl *surface);

// Buffer handling
void wl_surface_attach_buffer(struct wl_surface_impl *surface,
                              struct wl_resource *buffer);
void *wl_buffer_get_shm_data(struct wl_resource *buffer, int32_t *width,
                             int32_t *height, int32_t *stride);
void wl_buffer_end_shm_access(struct wl_resource *buffer);

// Surface iteration
struct wl_surface_impl *wl_get_all_surfaces(void);

// Send frame callbacks to all surfaces with pending callbacks
// Called at display refresh rate to synchronize with display
// Returns the number of callbacks sent
int wl_send_frame_callbacks(void);
bool wl_has_pending_frame_callbacks(void);

// Clear buffer reference from surfaces (called when buffer is destroyed)
void wl_compositor_clear_buffer_reference(struct wl_resource *buffer_resource);

// Destroy all tracked clients (for shutdown) - explicitly disconnects all
// clients including waypipe
void wl_compositor_destroy_all_clients(void);

// C function to remove surface from renderer (for cleanup)
void remove_surface_from_renderer(struct wl_surface_impl *surface);

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

// C function to handle client disconnection (may exit fullscreen if needed)
void macos_compositor_handle_client_disconnect(void);

// C function to handle new client connection (cancel fullscreen exit timer)
void macos_compositor_handle_client_connect(void);

// C function to update window title when no clients are connected
void macos_compositor_update_title_no_clients(void);

// C function to flush clients and trigger immediate frame callback
void wl_compositor_flush_and_trigger_frame(void);

// C function to create a native window for a toplevel
void macos_create_window_for_toplevel(struct xdg_toplevel_impl *toplevel);

#ifdef __OBJC__
@class WawonaCompositor;
@class CompositorView;
#else
typedef struct WawonaCompositor WawonaCompositor;
#endif
extern WawonaCompositor *g_compositor_instance;

#ifdef __OBJC__
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#include "../input/input_handler.h"
#include "../input/wayland_seat.h"
#include "launcher/WawonaAppScanner.h"
#include "rendering_backend.h"
#include "wayland_color_management.h"
#include "wayland_data_device_manager.h"
#include "wayland_output.h"
#include "wayland_presentation.h"
#include "wayland_shm.h"
#include "wayland_subcompositor.h"
#include "xdg_shell.h"
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#include "egl_buffer_handler.h"
#endif

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
    struct wl_data_device_manager_impl *data_device_manager;
@property(nonatomic, assign) struct xdg_wm_base_impl *xdg_wm_base;
@property(nonatomic, assign) struct wp_color_manager_impl *color_manager;
@property(nonatomic, assign)
    struct wl_text_input_manager_impl *text_input_manager;
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
@property(nonatomic, assign) struct egl_buffer_handler *egl_buffer_handler;
#endif

// Event loop integration
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
@property(nonatomic, strong) CADisplayLink *displayLink;
#else
@property(nonatomic, assign) CVDisplayLinkRef displayLink;
#endif
@property(nonatomic, strong) NSThread *eventThread;
@property(nonatomic, assign) BOOL shouldStopEventThread;
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
@property(nonatomic, strong) NSMutableArray
    *nativeWindows; // Array of NSWindow (strong) to retain created windows
@property(nonatomic, strong) CompositorView *mainCompositorView;
@property(nonatomic, strong)
    NSRecursiveLock *mapLock; // Lock for windowToToplevelMap
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
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
struct egl_buffer_handler *macos_compositor_get_egl_buffer_handler(void);
#endif

#endif // __OBJC__
