#pragma once

#include <stdbool.h>
#include <stdint.h>
#include <wayland-server-protocol.h>
#include <wayland-server.h>

// Forward declarations
struct wl_display;
struct wl_resource;
struct wl_client;
struct wl_array;

// Render callback type
struct wl_surface_impl;
typedef void (*wl_surface_render_callback_t)(struct wl_surface_impl *surface);

// Title update callback type
typedef void (*wl_title_update_callback_t)(struct wl_client *client);

// Frame callback requested callback type
typedef void (*wl_frame_callback_requested_t)(void);

// Compositor global
struct wl_compositor_impl {
  struct wl_global *global;
  struct wl_display *display;
  wl_surface_render_callback_t render_callback;
  wl_title_update_callback_t update_title_callback;
  wl_frame_callback_requested_t frame_callback_requested;
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
  bool configured;
  uint32_t pending_configure_serial;

  // Damage management
  struct wl_array pending_damage;

  // Callbacks
  struct wl_resource *frame_callback;

  // Viewport
  void *viewport;

  // User data
  void *user_data;

  // Tree structure
  struct wl_surface_impl *parent;

  // Color management
  void *color_management;
};

// Global compositor and surface list (shared across WawonaCompositor.m and
// wayland_compositor.c)
extern struct wl_surface_impl *g_wl_surface_list;
extern struct wl_compositor_impl *g_wl_compositor;

// Core protocol initialization
struct wl_compositor_impl *wl_compositor_create(struct wl_display *display);
void wl_compositor_destroy(struct wl_compositor_impl *compositor);

// Surface management
struct wl_surface_impl *wl_get_all_surfaces(void);

// Frame callback management
int wl_send_frame_callbacks(void);
bool wl_has_pending_frame_callbacks(void);

// Internal C-accessible functions
void macos_compositor_handle_client_connect(void);
void macos_compositor_handle_client_disconnect(void);
void wl_compositor_lock_surfaces(void);
void wl_compositor_unlock_surfaces(void);
void remove_surface_from_renderer(struct wl_surface_impl *surface);
int macos_compositor_get_client_count(void);
bool macos_compositor_multiple_clients_enabled(void);

// Surface iterator
typedef void (*wl_surface_iterator_func_t)(struct wl_surface_impl *surface,
                                           void *data);
void wl_compositor_for_each_surface(wl_surface_iterator_func_t iterator,
                                    void *data);

// Core protocol interfaces
extern const struct wl_surface_interface surface_interface;
extern const struct wl_region_interface region_interface;
extern const struct wl_compositor_interface compositor_interface;

// Buffer querying
bool is_dmabuf_buffer(struct wl_resource *buffer);
struct metal_dmabuf_buffer *dmabuf_buffer_get(struct wl_resource *buffer);
struct egl_buffer_handler *macos_compositor_get_egl_buffer_handler(void);
