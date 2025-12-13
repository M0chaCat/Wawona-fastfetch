#pragma once

#include <wayland-server-core.h>
#include <wayland-server.h>

struct wl_subcompositor_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wl_subcompositor_impl *wl_subcompositor_create(struct wl_display *display);
void wl_subcompositor_destroy(struct wl_subcompositor_impl *subcompositor);

