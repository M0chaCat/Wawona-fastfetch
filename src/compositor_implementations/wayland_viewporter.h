#pragma once
#include <wayland-server.h>

struct wp_viewporter_impl {
    struct wl_global *global;
    struct wl_display *display;
};

// Per-surface viewport state
struct wl_viewport_impl {
    struct wl_resource *resource;
    struct wl_surface_impl *surface;
    bool has_source;
    float src_x;
    float src_y;
    float src_width;
    float src_height;
    bool has_destination;
    int32_t dst_width;
    int32_t dst_height;
};

struct wp_viewporter_impl *wp_viewporter_create(struct wl_display *display);

// Helper to access viewport from a wl_surface (may be NULL)
struct wl_viewport_impl *wl_viewport_from_surface(struct wl_surface_impl *surface);
