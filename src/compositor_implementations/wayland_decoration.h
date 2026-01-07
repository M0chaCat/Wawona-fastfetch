// wayland_decoration.h - XDG Decoration Protocol Header
// Implements zxdg_decoration_manager_v1 for server-side/client-side decoration
// negotiation

#ifndef WAYLAND_DECORATION_H
#define WAYLAND_DECORATION_H

#include <stdbool.h>
#include <wayland-server-core.h>

struct wl_decoration_manager_impl;

// Create and initialize the decoration manager global
struct wl_decoration_manager_impl *
wl_decoration_create(struct wl_display *display);

// Destroy the decoration manager
void wl_decoration_destroy(struct wl_decoration_manager_impl *manager);

// Hot-reload decorations for all active clients
void wl_decoration_hot_reload(struct wl_decoration_manager_impl *manager);

struct xdg_toplevel_impl;
void wl_decoration_send_configure(struct xdg_toplevel_impl *toplevel);

#endif // WAYLAND_DECORATION_H
