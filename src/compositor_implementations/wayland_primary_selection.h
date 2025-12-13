#pragma once
#include <wayland-server.h>

struct wp_primary_selection_device_manager_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wp_primary_selection_device_manager_impl *wp_primary_selection_device_manager_create(struct wl_display *display);
