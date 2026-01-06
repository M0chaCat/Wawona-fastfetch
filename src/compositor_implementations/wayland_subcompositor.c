#include "wayland_subcompositor.h"
#include "../core/WawonaCompositor.h"
#include <stdio.h>
#include <stdlib.h>
#include <wayland-server-protocol.h>

static void subcompositor_destroy(struct wl_client *client,
                                  struct wl_resource *resource) {
  (void)client;
  wl_resource_destroy(resource);
}

static void subsurface_destroy(struct wl_client *client,
                               struct wl_resource *resource) {
  wl_resource_destroy(resource);
}

static void subsurface_set_position(struct wl_client *client,
                                    struct wl_resource *resource, int32_t x,
                                    int32_t y) {
  struct wl_surface_impl *surface = wl_resource_get_user_data(resource);
  if (surface) {
    surface->x = x;
    surface->y = y;
    printf("[SUBCOMPOSITOR] Set subsurface %p position to %d,%d\n",
           (void *)surface, x, y);
  }
}

static void subsurface_place_above(struct wl_client *client,
                                   struct wl_resource *resource,
                                   struct wl_resource *sibling) {
  (void)client;
  (void)resource;
  (void)sibling;
  // TODO: Implement subsurface stacking
}

static void subsurface_place_below(struct wl_client *client,
                                   struct wl_resource *resource,
                                   struct wl_resource *sibling) {
  (void)client;
  (void)resource;
  (void)sibling;
  // TODO: Implement subsurface stacking
}

static void subsurface_set_sync(struct wl_client *client,
                                struct wl_resource *resource) {
  (void)client;
  (void)resource;
  // TODO: Implement sync mode
}

static void subsurface_set_desync(struct wl_client *client,
                                  struct wl_resource *resource) {
  (void)client;
  (void)resource;
  // TODO: Implement desync mode
}

static const struct wl_subsurface_interface subsurface_interface = {
    .destroy = subsurface_destroy,
    .set_position = subsurface_set_position,
    .place_above = subsurface_place_above,
    .place_below = subsurface_place_below,
    .set_sync = subsurface_set_sync,
    .set_desync = subsurface_set_desync,
};

static void subcompositor_get_subsurface(struct wl_client *client,
                                         struct wl_resource *resource,
                                         uint32_t id,
                                         struct wl_resource *surface_resource,
                                         struct wl_resource *parent_resource) {
  struct wl_resource *subsurface_resource;
  struct wl_surface_impl *surface = wl_resource_get_user_data(surface_resource);
  struct wl_surface_impl *parent = wl_resource_get_user_data(parent_resource);

  subsurface_resource = wl_resource_create(
      client, &wl_subsurface_interface, wl_resource_get_version(resource), id);
  if (!subsurface_resource) {
    wl_resource_post_no_memory(resource);
    return;
  }

  // Set parent pointer to link subsurface to its parent
  // This is used by xdg_shell to find the toplevel window for subsurfaces
  if (surface && parent) {
    surface->parent = parent;
    printf("[SUBCOMPOSITOR] Linked surface %p to parent %p\n", (void *)surface,
           (void *)parent);
  }

  // Set implementation to prevent NULL implementation crashes
  wl_resource_set_implementation(subsurface_resource, &subsurface_interface,
                                 surface, NULL);
  printf("[SUBCOMPOSITOR] Created subsurface resource %d for surface %p\n", id,
         (void *)surface);
}

static const struct wl_subcompositor_interface subcompositor_interface = {
    .destroy = subcompositor_destroy,
    .get_subsurface = subcompositor_get_subsurface,
};

static void bind_subcompositor(struct wl_client *client, void *data,
                               uint32_t version, uint32_t id) {
  struct wl_subcompositor_impl *subcompositor = data;
  struct wl_resource *resource;

  resource =
      wl_resource_create(client, &wl_subcompositor_interface, (int)version, id);
  if (!resource) {
    wl_client_post_no_memory(client);
    return;
  }

  wl_resource_set_implementation(resource, &subcompositor_interface,
                                 subcompositor, NULL);
}

struct wl_subcompositor_impl *
wl_subcompositor_create(struct wl_display *display) {
  struct wl_subcompositor_impl *sub =
      calloc(1, sizeof(struct wl_subcompositor_impl));
  if (!sub)
    return NULL;

  sub->display = display;

  sub->global = wl_global_create(display, &wl_subcompositor_interface, 1, sub,
                                 bind_subcompositor);
  if (!sub->global) {
    free(sub);
    return NULL;
  }

  return sub;
}

void wl_subcompositor_destroy(struct wl_subcompositor_impl *sub) {
  if (!sub)
    return;
  if (sub->global)
    wl_global_destroy(sub->global);
  free(sub);
}
