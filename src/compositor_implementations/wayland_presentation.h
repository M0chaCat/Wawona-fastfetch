#pragma once
#include <wayland-server.h>

struct wp_presentation_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wp_presentation_impl *wp_presentation_create(struct wl_display *display);
