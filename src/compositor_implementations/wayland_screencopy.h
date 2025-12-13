#pragma once
#include <wayland-server.h>

struct zwlr_screencopy_manager_v1_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct zwlr_screencopy_manager_v1_impl *zwlr_screencopy_manager_v1_create(struct wl_display *display);
