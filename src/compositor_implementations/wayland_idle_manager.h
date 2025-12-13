#pragma once
#include <wayland-server.h>

struct org_kde_kwin_idle_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct org_kde_kwin_idle_impl *org_kde_kwin_idle_create(struct wl_display *display);
