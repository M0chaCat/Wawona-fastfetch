#pragma once

#include <wayland-server-core.h>
#include <wayland-server.h>

struct wl_shm_impl {
    struct wl_global *global;
    struct wl_display *display;
};

struct wl_shm_impl *wl_shm_create(struct wl_display *display);
void wl_shm_destroy(struct wl_shm_impl *shm);

