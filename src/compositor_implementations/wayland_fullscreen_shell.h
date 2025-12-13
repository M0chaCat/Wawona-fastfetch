#pragma once

#include <wayland-server.h>

struct wl_display;

void wayland_fullscreen_shell_init(struct wl_display *display);

