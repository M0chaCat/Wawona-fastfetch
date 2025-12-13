#pragma once
#include <wayland-server.h>

struct wl_shell_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wl_shell_impl *wl_shell_create(struct wl_display *display);
