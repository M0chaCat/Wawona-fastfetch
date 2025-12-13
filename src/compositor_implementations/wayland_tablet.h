#pragma once
#include <wayland-server.h>

struct zwp_tablet_manager_v2_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct zwp_tablet_manager_v2_impl *zwp_tablet_manager_v2_create(struct wl_display *display);
