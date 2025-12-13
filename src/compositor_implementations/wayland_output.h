#pragma once

#include <wayland-server-core.h>
#include <wayland-server.h>

struct wl_output_impl {
    struct wl_global *global;
    struct wl_display *display;
    
    int32_t width, height;
    int32_t scale;
    int32_t transform;
    int32_t refresh_rate;
    const char *name;
    const char *description;
    
    // List of all wl_output resources bound to this output
    // Used to send mode change events to all clients when output size changes
    struct wl_list resource_list;
};

struct wl_output_impl *wl_output_create(struct wl_display *display, int32_t width, int32_t height, int32_t scale, const char *name);
void wl_output_destroy(struct wl_output_impl *output);
void wl_output_update_size(struct wl_output_impl *output, int32_t width, int32_t height, int32_t scale);

