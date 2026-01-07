#include "wayland_compositor.h"
#include "egl_buffer_handler.h"
#include "metal_dmabuf.h"
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <wayland-server-core.h>
#include <wayland-server-protocol.h>
#include <wayland-server.h>

#include "logging.h"

// Static globals moved from WawonaCompositor.m
struct wl_surface_impl *g_wl_surface_list = NULL;
struct wl_compositor_impl *g_wl_compositor = NULL;

// --- Forward Declarations ---
static void surface_destroy_resource(struct wl_resource *resource);
static void region_destroy_resource(struct wl_resource *resource);

// --- Region Implementation ---

struct wl_region_impl {
  struct wl_resource *resource;
};

static void region_destroy(struct wl_client *client,
                           struct wl_resource *resource) {
  (void)client;
  wl_resource_destroy(resource);
}

static void region_add(struct wl_client *client, struct wl_resource *resource,
                       int32_t x, int32_t y, int32_t width, int32_t height) {
  (void)client;
  (void)resource;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
}

static void region_subtract(struct wl_client *client,
                            struct wl_resource *resource, int32_t x, int32_t y,
                            int32_t width, int32_t height) {
  (void)client;
  (void)resource;
  (void)x;
  (void)y;
  (void)width;
  (void)height;
}

const struct wl_region_interface region_interface = {region_destroy, region_add,
                                                     region_subtract};

static void region_destroy_resource(struct wl_resource *resource) {
  struct wl_region_impl *region = wl_resource_get_user_data(resource);
  free(region);
}

static void compositor_destroy_bound_resource(struct wl_resource *resource) {
  (void)resource;
  macos_compositor_handle_client_disconnect();
}

// --- Surface Implementation ---

static void surface_destroy(struct wl_client *client,
                            struct wl_resource *resource) {
  (void)client;
  wl_resource_destroy(resource);
}

static void surface_attach(struct wl_client *client,
                           struct wl_resource *resource,
                           struct wl_resource *buffer, int32_t x, int32_t y) {
  (void)client;
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);

  if (surface->buffer_resource && surface->buffer_resource != buffer &&
      !surface->buffer_release_sent) {
    struct wl_client *old_buffer_client =
        wl_resource_get_client(surface->buffer_resource);
    if (old_buffer_client) {
      wl_buffer_send_release(surface->buffer_resource);
      surface->buffer_release_sent = true;
    }
  }

  surface->buffer_resource = buffer;
  if (buffer) {
    surface->buffer_release_sent = false;
  }
  surface->x = x;
  surface->y = y;
}

static void surface_damage(struct wl_client *client,
                           struct wl_resource *resource, int32_t x, int32_t y,
                           int32_t width, int32_t height) {
  (void)client;
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
  if (surface) {
    int32_t *rect = wl_array_add(&surface->pending_damage, sizeof(int32_t) * 4);
    if (rect) {
      rect[0] = x;
      rect[1] = y;
      rect[2] = width;
      rect[3] = height;
    }
  }
}

static void frame_callback_destructor(struct wl_resource *resource) {
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
  if (surface && surface->frame_callback == resource) {
    surface->frame_callback = NULL;
  }
}

static void surface_frame(struct wl_client *client,
                          struct wl_resource *resource, uint32_t callback) {
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);

  struct wl_resource *callback_resource =
      wl_resource_create(client, &wl_callback_interface, 1, callback);
  if (!callback_resource) {
    wl_resource_post_no_memory(resource);
    return;
  }

  if (surface->frame_callback) {
    wl_resource_destroy(surface->frame_callback);
  }

  surface->frame_callback = callback_resource;

  wl_resource_set_implementation(callback_resource, NULL, surface,
                                 frame_callback_destructor);

  static int frame_request_count = 0;
  frame_request_count++;
  if (frame_request_count <= 20 || frame_request_count % 100 == 0) {
    log_printf(
        "SURFACE",
        "Frame callback requested (surface=%p, callback=%p, request #%d)\n",
        (void *)surface, (void *)callback_resource, frame_request_count);
  }

  if (g_wl_compositor && g_wl_compositor->frame_callback_requested) {
    g_wl_compositor->frame_callback_requested();
  }
}

static void surface_set_opaque_region(struct wl_client *client,
                                      struct wl_resource *resource,
                                      struct wl_resource *region_resource) {
  (void)client;
  (void)resource;
  (void)region_resource;
}

static void surface_set_input_region(struct wl_client *client,
                                     struct wl_resource *resource,
                                     struct wl_resource *region_resource) {
  (void)client;
  (void)resource;
  (void)region_resource;
}

static void surface_commit(struct wl_client *client,
                           struct wl_resource *resource) {
  (void)client;
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);

  surface->committed = true;

  if (surface->buffer_resource) {
    struct wl_shm_buffer *shm_buffer =
        wl_shm_buffer_get(surface->buffer_resource);
    if (shm_buffer) {
      surface->buffer_width = wl_shm_buffer_get_width(shm_buffer);
      surface->buffer_height = wl_shm_buffer_get_height(shm_buffer);
      surface->width = surface->buffer_width;
      surface->height = surface->buffer_height;
    } else {
      if (is_dmabuf_buffer(surface->buffer_resource)) {
        struct metal_dmabuf_buffer *dmabuf_buffer =
            dmabuf_buffer_get(surface->buffer_resource);
        if (dmabuf_buffer) {
          surface->buffer_width = dmabuf_buffer->width;
          surface->buffer_height = dmabuf_buffer->height;
          surface->width = dmabuf_buffer->width;
          surface->height = dmabuf_buffer->height;
        }
      } else {
        struct egl_buffer_handler *egl_handler =
            macos_compositor_get_egl_buffer_handler();
        if (egl_handler) {
          int32_t width, height;
          EGLint format;
          if (egl_buffer_handler_query_buffer(egl_handler,
                                              surface->buffer_resource, &width,
                                              &height, &format) == 0) {
            surface->buffer_width = width;
            surface->buffer_height = height;
            surface->width = width;
            surface->height = height;
          }
        }
      }
    }

    if (surface->buffer_scale < 1)
      surface->buffer_scale = 1;
    surface->width = surface->buffer_width / surface->buffer_scale;
    surface->height = surface->buffer_height / surface->buffer_scale;
  }
  wl_array_release(&surface->pending_damage);
  wl_array_init(&surface->pending_damage);

  if (g_wl_compositor && g_wl_compositor->render_callback) {
    g_wl_compositor->render_callback(surface);
  }
}

static void surface_set_buffer_transform(struct wl_client *client,
                                         struct wl_resource *resource,
                                         int32_t transform) {
  (void)client;
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
  if (surface) {
    surface->buffer_transform = transform;
  }
}

static void surface_set_buffer_scale(struct wl_client *client,
                                     struct wl_resource *resource,
                                     int32_t scale) {
  (void)client;
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
  if (surface) {
    surface->buffer_scale = scale;
  }
}

static void surface_damage_buffer(struct wl_client *client,
                                  struct wl_resource *resource, int32_t x,
                                  int32_t y, int32_t width, int32_t height) {
  (void)client;
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
  if (surface) {
    int32_t *rect = wl_array_add(&surface->pending_damage, sizeof(int32_t) * 4);
    if (rect) {
      rect[0] = x;
      rect[1] = y;
      rect[2] = width;
      rect[3] = height;
    }
  }
}

const struct wl_surface_interface surface_interface = {
    surface_destroy,
    surface_attach,
    surface_damage,
    surface_frame,
    surface_set_opaque_region,
    surface_set_input_region,
    surface_commit,
    surface_set_buffer_transform,
    surface_set_buffer_scale,
    surface_damage_buffer};

static void surface_destroy_resource(struct wl_resource *resource) {
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);

  log_printf("COMPOSITOR",
             "⚠️ Destroying surface %p (resource=%p, g_wl_surface_list=%p)\n",
             (void *)surface, (void *)resource, (void *)g_wl_surface_list);

  if (surface->frame_callback) {
    surface->frame_callback = NULL;
  }

  macos_compositor_handle_client_disconnect();

  wl_compositor_lock_surfaces();

  surface->resource = NULL;

  if (g_wl_surface_list == surface) {
    g_wl_surface_list = surface->next;
  } else {
    struct wl_surface_impl *prev = g_wl_surface_list;
    while (prev && prev->next != surface) {
      prev = prev->next;
    }
    if (prev) {
      prev->next = surface->next;
    }
  }
  surface->next = NULL;

  wl_compositor_unlock_surfaces();

  log_printf("COMPOSITOR",
             "   Surface removed from list, g_wl_surface_list=%p\n",
             (void *)g_wl_surface_list);

  remove_surface_from_renderer(surface);

  log_printf("COMPOSITOR", "   Surface destroyed\n");

  wl_array_release(&surface->pending_damage);
  free(surface);
}

static void compositor_create_surface(struct wl_client *client,
                                      struct wl_resource *resource,
                                      uint32_t id) {
  (void)client;
  (void)resource;
  (void)id;

  struct wl_surface_impl *surface = calloc(1, sizeof(struct wl_surface_impl));
  if (!surface) {
    wl_resource_post_no_memory(resource);
    return;
  }

  surface->resource = wl_resource_create(client, &wl_surface_interface,
                                         wl_resource_get_version(resource), id);
  if (!surface->resource) {
    free(surface);
    wl_resource_post_no_memory(resource);
    return;
  }

  wl_resource_set_implementation(surface->resource, &surface_interface, surface,
                                 surface_destroy_resource);

  surface->next = g_wl_surface_list;
  g_wl_surface_list = surface;

  surface->buffer_scale = 1;
  surface->buffer_transform = WL_OUTPUT_TRANSFORM_NORMAL;
  surface->configured = false;
  surface->pending_configure_serial = 0;
  wl_array_init(&surface->pending_damage);

  log_printf("COMPOSITOR",
             "✓ Created surface %p (resource id=%u, g_wl_surface_list=%p)\n",
             (void *)surface, id, (void *)g_wl_surface_list);
}

static void compositor_create_region(struct wl_client *client,
                                     struct wl_resource *resource,
                                     uint32_t id) {
  struct wl_region_impl *region = calloc(1, sizeof(struct wl_region_impl));
  if (!region) {
    wl_resource_post_no_memory(resource);
    return;
  }

  region->resource = wl_resource_create(client, &wl_region_interface,
                                        wl_resource_get_version(resource), id);
  if (!region->resource) {
    free(region);
    wl_resource_post_no_memory(resource);
    return;
  }

  wl_resource_set_implementation(region->resource, &region_interface, region,
                                 region_destroy_resource);
}

const struct wl_compositor_interface compositor_interface = {
    compositor_create_surface, compositor_create_region};

static void compositor_bind(struct wl_client *client, void *data,
                            uint32_t version, uint32_t id) {
  struct wl_compositor_impl *compositor = data;
  if (!macos_compositor_multiple_clients_enabled() &&
      macos_compositor_get_client_count() > 0) {
    log_printf("COMPOSITOR", "🚫 Additional client connection rejected: "
                             "multiple clients disabled\n");
    wl_client_destroy(client);
    return;
  }
  struct wl_resource *resource =
      wl_resource_create(client, &wl_compositor_interface, version, id);
  if (!resource) {
    wl_client_post_no_memory(client);
    return;
  }
  wl_resource_set_implementation(resource, &compositor_interface, compositor,
                                 compositor_destroy_bound_resource);
  macos_compositor_handle_client_connect();
}

struct wl_compositor_impl *wl_compositor_create(struct wl_display *display) {
  struct wl_compositor_impl *compositor =
      calloc(1, sizeof(struct wl_compositor_impl));
  if (!compositor)
    return NULL;

  compositor->display = display;
  compositor->global = wl_global_create(display, &wl_compositor_interface, 4,
                                        compositor, compositor_bind);

  if (!compositor->global) {
    free(compositor);
    return NULL;
  }

  g_wl_compositor = compositor;
  return compositor;
}

void wl_compositor_destroy(struct wl_compositor_impl *compositor) {
  if (g_wl_compositor == compositor)
    g_wl_compositor = NULL;
  if (compositor->global)
    wl_global_destroy(compositor->global);
  free(compositor);
}

struct wl_surface_impl *wl_get_all_surfaces(void) { return g_wl_surface_list; }

int wl_send_frame_callbacks(void) {
  if (!g_wl_surface_list) {
    return 0;
  }

  int count = 0;
  struct wl_surface_impl *surface = g_wl_surface_list;
  while (surface) {
    struct wl_surface_impl *next_surface = surface->next;

    if (surface->frame_callback) {
      uintptr_t callback_addr = (uintptr_t)surface->frame_callback;
      if (callback_addr < 0x1000 || callback_addr > 0x7FFFFFFFFFFFF000) {
        surface->frame_callback = NULL;
        surface = next_surface;
        continue;
      }

      if (!surface->resource) {
        surface->frame_callback = NULL;
        surface = next_surface;
        continue;
      }

      void *surface_user_data = wl_resource_get_user_data(surface->resource);
      if (surface_user_data != surface) {
        surface->frame_callback = NULL;
        surface = next_surface;
        continue;
      }

      struct wl_client *surface_client =
          wl_resource_get_client(surface->resource);
      if (!surface_client) {
        surface->frame_callback = NULL;
        surface = next_surface;
        continue;
      }

      void *cb_user_data = wl_resource_get_user_data(surface->frame_callback);
      if (cb_user_data != surface) {
        surface->frame_callback = NULL;
        surface = next_surface;
        continue;
      }

      struct timespec ts;
      clock_gettime(CLOCK_MONOTONIC, &ts);
      uint32_t time = (uint32_t)(ts.tv_sec * 1000 + ts.tv_nsec / 1000000);

      wl_callback_send_done(surface->frame_callback, time);
      wl_resource_destroy(surface->frame_callback);
      surface->frame_callback = NULL;
      count++;
    }
    surface = next_surface;
  }
  return count;
}

bool wl_has_pending_frame_callbacks(void) {
  if (!g_wl_surface_list) {
    return false;
  }

  struct wl_surface_impl *surface = g_wl_surface_list;
  while (surface) {
    if (surface->frame_callback) {
      void *cb_user_data = wl_resource_get_user_data(surface->frame_callback);
      if (!cb_user_data) {
        surface->frame_callback = NULL;
        continue;
      }

      if (surface->resource) {
        void *surface_user_data = wl_resource_get_user_data(surface->resource);
        if (surface_user_data == surface) {
          struct wl_client *client = wl_resource_get_client(surface->resource);
          if (client) {
            return true;
          }
        }
      }
    }
    surface = surface->next;
  }
  return false;
}
