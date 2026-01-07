#pragma once
#include "metal_dmabuf.h"
#include <stdbool.h>
#include <wayland-server.h>

struct zwp_linux_dmabuf_v1_impl {
  struct wl_global *global;
  struct wl_display *display;
};

struct zwp_linux_dmabuf_v1_impl *
zwp_linux_dmabuf_v1_create(struct wl_display *display);

// Check if a buffer resource is a dmabuf buffer
bool is_dmabuf_buffer(struct wl_resource *resource);

// Get the underlying metal_dmabuf_buffer from a wl_buffer resource
struct metal_dmabuf_buffer *dmabuf_buffer_get(struct wl_resource *resource);
