#pragma once
#include <wayland-server.h>

struct wl_data_device_manager_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wl_data_device_manager_impl *wl_data_device_manager_create(struct wl_display *display);
