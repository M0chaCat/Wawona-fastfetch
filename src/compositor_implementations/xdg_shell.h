#pragma once

#include <wayland-server-core.h>
#include <wayland-server.h>
#include "xdg-shell-protocol.h"

// xdg-shell protocol implementation
struct xdg_wm_base_impl {
    struct wl_global *global;
    struct wl_display *display;
    uint32_t version;
    int32_t output_width;
    int32_t output_height;
};

struct xdg_surface_impl {
    struct wl_resource *resource;
    struct wl_surface_impl *wl_surface;
    struct xdg_surface_impl *next;
    struct xdg_wm_base_impl *wm_base;  // Reference to wm_base for accessing output size
    
    // Surface state
    bool configured;
    uint32_t configure_serial;  // Most recent configure serial sent
    uint32_t last_acked_serial;   // Last acknowledged configure serial
    
    // Role (toplevel or popup)
    void *role;
    
    // Title and app_id stored in toplevel
};

struct xdg_toplevel_impl {
    struct wl_resource *resource;
    struct xdg_surface_impl *xdg_surface;
    
    // Window state
    char *title;
    char *app_id;
    uint32_t states;
    int32_t width, height;
    
    // Decoration mode: 0 = unset, 1 = CLIENT_SIDE, 2 = SERVER_SIDE
    uint32_t decoration_mode;
};

struct xdg_popup_impl {
    struct wl_resource *resource;
    struct xdg_surface_impl *xdg_surface;
    struct xdg_surface_impl *parent;
    struct xdg_positioner_impl *positioner;
    int32_t x, y;
    bool configured;
    uint32_t configure_serial;
};

struct xdg_wm_base_impl *xdg_wm_base_create(struct wl_display *display);
void xdg_wm_base_destroy(struct xdg_wm_base_impl *wm_base);
void xdg_wm_base_send_configure_to_all_toplevels(struct xdg_wm_base_impl *wm_base, int32_t width, int32_t height);
void xdg_wm_base_set_output_size(struct xdg_wm_base_impl *wm_base, int32_t width, int32_t height);

// Forward declaration
struct wl_surface_impl;
struct wl_client;
bool xdg_surface_is_toplevel(struct wl_surface_impl *wl_surface);
struct xdg_toplevel_impl *xdg_surface_get_toplevel_from_wl_surface(struct wl_surface_impl *wl_surface);

// Mark a client as a nested compositor (will auto-fullscreen its toplevels)
void xdg_shell_mark_nested_compositor(struct wl_client *client);

// Get the nested compositor client (for use by other modules like decoration manager)
struct wl_client *nested_compositor_client_from_xdg_shell(void);

// Global xdg_surfaces list (declared in xdg_shell.c)
extern struct xdg_surface_impl *xdg_surfaces;

