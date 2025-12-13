#pragma once
#include <wayland-server.h>

struct wl_drm_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wl_drm_impl *wl_drm_create(struct wl_display *display);
