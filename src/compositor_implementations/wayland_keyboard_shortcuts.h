#pragma once
#include <wayland-server.h>

struct zwp_keyboard_shortcuts_inhibit_manager_v1_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct zwp_keyboard_shortcuts_inhibit_manager_v1_impl *zwp_keyboard_shortcuts_inhibit_manager_v1_create(struct wl_display *display);
