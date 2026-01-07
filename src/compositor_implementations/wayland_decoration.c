// wayland_decoration.c - XDG Decoration Protocol Implementation
// Implements zxdg_decoration_manager_v1 for server-side/client-side decoration
// negotiation Respects the "Force Server-Side Decorations" setting in Wawona

#include "wayland_decoration.h"
#include "../core/WawonaSettings.h"
#include "../logging/logging.h"
#include "../protocols/xdg-decoration-protocol.h"
#include "../protocols/xdg-shell-protocol.h"
#include "xdg_shell.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-server-core.h>
#include <wayland-server.h>

// --- Toplevel Decoration Implementation ---

struct toplevel_decoration_impl {
  struct wl_resource *resource;
  struct wl_resource *toplevel;
  struct wl_decoration_manager_impl *manager;
  uint32_t pending_mode;
  uint32_t current_mode;
  uint32_t requested_mode;
  struct wl_list link;
};

static void toplevel_decoration_destroy(struct wl_client *client,
                                        struct wl_resource *resource) {
  (void)client;
  wl_resource_destroy(resource);
}

static void toplevel_decoration_set_mode(struct wl_client *client,
                                         struct wl_resource *resource,
                                         uint32_t mode) {
  (void)client;
  struct toplevel_decoration_impl *decoration =
      wl_resource_get_user_data(resource);
  if (!decoration)
    return;

  log_printf(
      "DECORATION", "Client requested decoration mode: %s\n",
      mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE   ? "client-side"
      : mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE ? "server-side"
                                                             : "unknown");

  // Check the Force Server-Side Decorations setting
  bool force_ssd = WawonaSettings_GetForceServerSideDecorations();

  uint32_t final_mode;
  if (force_ssd) {
    // Force server-side decorations regardless of client preference
    final_mode = ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
    log_printf("DECORATION",
               "Force SSD enabled - using server-side decorations\n");
  } else {
    // Honor client preference
    final_mode = mode;
    log_printf(
        "DECORATION", "Force SSD disabled - honoring client request: %s\n",
        mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE ? "CSD" : "SSD");
  }

  decoration->requested_mode = mode;
  decoration->current_mode = final_mode;

  // Update the xdg_toplevel_impl
  struct xdg_toplevel_impl *xdg_toplevel =
      wl_resource_get_user_data(decoration->toplevel);
  if (xdg_toplevel) {
    xdg_toplevel->decoration_mode = final_mode;

    // Notify the compositor to update the window decoration
    extern void macos_update_toplevel_decoration_mode(struct xdg_toplevel_impl *
                                                      toplevel);
    macos_update_toplevel_decoration_mode(xdg_toplevel);
  }

  // Send configure event with the decided mode
  zxdg_toplevel_decoration_v1_send_configure(resource, final_mode);

  // CRITICAL: Send xdg_surface.configure to signal the client that the
  // decoration mode update is complete and they can acknowledge it.
  if (xdg_toplevel && xdg_toplevel->xdg_surface &&
      xdg_toplevel->xdg_surface->resource) {
    xdg_surface_send_configure(xdg_toplevel->xdg_surface->resource,
                               ++xdg_toplevel->xdg_surface->configure_serial);
  }

  log_printf("DECORATION", "Sent configure with mode: %s\n",
             final_mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE
                 ? "client-side"
                 : "server-side");
}

static void toplevel_decoration_unset_mode(struct wl_client *client,
                                           struct wl_resource *resource) {
  (void)client;
  struct toplevel_decoration_impl *decoration =
      wl_resource_get_user_data(resource);
  if (!decoration)
    return;

  log_printf("DECORATION",
             "Client unset decoration mode (using compositor preference)\n");

  // When mode is unset, use compositor preference
  bool force_ssd = WawonaSettings_GetForceServerSideDecorations();
  uint32_t mode = force_ssd ? ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE
                            : ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;

  decoration->current_mode = mode;
  decoration->requested_mode = 0; // Clear requested mode

  // Update the xdg_toplevel_impl
  struct xdg_toplevel_impl *xdg_toplevel =
      wl_resource_get_user_data(decoration->toplevel);
  if (xdg_toplevel) {
    xdg_toplevel->decoration_mode = mode;

    // Notify the compositor to update the window decoration
    extern void macos_update_toplevel_decoration_mode(struct xdg_toplevel_impl *
                                                      toplevel);
    macos_update_toplevel_decoration_mode(xdg_toplevel);
  }

  zxdg_toplevel_decoration_v1_send_configure(resource, mode);

  // CRITICAL: Send xdg_surface.configure
  if (xdg_toplevel && xdg_toplevel->xdg_surface &&
      xdg_toplevel->xdg_surface->resource) {
    xdg_surface_send_configure(xdg_toplevel->xdg_surface->resource,
                               ++xdg_toplevel->xdg_surface->configure_serial);
  }
}

static const struct zxdg_toplevel_decoration_v1_interface
    toplevel_decoration_implementation = {
        .destroy = toplevel_decoration_destroy,
        .set_mode = toplevel_decoration_set_mode,
        .unset_mode = toplevel_decoration_unset_mode,
};

static void toplevel_decoration_destroy_resource(struct wl_resource *resource) {
  struct toplevel_decoration_impl *decoration =
      wl_resource_get_user_data(resource);
  if (decoration) {
    // Clear link in toplevel
    struct xdg_toplevel_impl *xdg_toplevel =
        wl_resource_get_user_data(decoration->toplevel);
    if (xdg_toplevel) {
      xdg_toplevel->decoration_data = NULL;
    }

    if (decoration->link.next && decoration->link.prev) {
      wl_list_remove(&decoration->link);
    }
    free(decoration);
  }
}

// --- Decoration Manager Implementation ---

struct wl_decoration_manager_impl {
  struct wl_global *global;
  struct wl_display *display;
  struct wl_list decorations;
};

static void decoration_manager_destroy(struct wl_client *client,
                                       struct wl_resource *resource) {
  (void)client;
  wl_resource_destroy(resource);
}

static void decoration_manager_get_toplevel_decoration(
    struct wl_client *client, struct wl_resource *resource, uint32_t id,
    struct wl_resource *toplevel_resource) {
  struct wl_decoration_manager_impl *manager =
      wl_resource_get_user_data(resource);

  struct wl_resource *decoration_resource =
      wl_resource_create(client, &zxdg_toplevel_decoration_v1_interface,
                         wl_resource_get_version(resource), id);

  if (!decoration_resource) {
    wl_resource_post_no_memory(resource);
    return;
  }

  struct toplevel_decoration_impl *decoration =
      calloc(1, sizeof(struct toplevel_decoration_impl));
  if (!decoration) {
    wl_resource_destroy(decoration_resource);
    wl_resource_post_no_memory(resource);
    return;
  }

  decoration->resource = decoration_resource;
  decoration->toplevel = toplevel_resource;
  decoration->manager = manager;
  decoration->pending_mode = 0;
  decoration->current_mode = 0;
  wl_list_init(&decoration->link);

  wl_resource_set_implementation(
      decoration_resource, &toplevel_decoration_implementation, decoration,
      toplevel_decoration_destroy_resource);

  wl_list_insert(&manager->decorations, &decoration->link);

  // Send initial configure with compositor preference
  bool force_ssd = WawonaSettings_GetForceServerSideDecorations();
  uint32_t initial_mode = force_ssd
                              ? ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE
                              : ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;

  decoration->current_mode = initial_mode;

  // Sync initial mode to xdg_toplevel_impl
  struct xdg_toplevel_impl *xdg_toplevel =
      wl_resource_get_user_data(toplevel_resource);
  if (xdg_toplevel) {
    xdg_toplevel->decoration_mode = initial_mode;
    xdg_toplevel->decoration_data = decoration;

    // Notify the compositor to update the window decoration immediately
    extern void macos_update_toplevel_decoration_mode(struct xdg_toplevel_impl *
                                                      toplevel);
    macos_update_toplevel_decoration_mode(xdg_toplevel);
  }

  zxdg_toplevel_decoration_v1_send_configure(decoration_resource, initial_mode);

  log_printf("DECORATION",
             "Created toplevel decoration for toplevel %p, initial mode: %s "
             "(Force SSD: %s)\n",
             (void *)toplevel_resource,
             initial_mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE
                 ? "server-side"
                 : "client-side",
             force_ssd ? "enabled" : "disabled");
}

static const struct zxdg_decoration_manager_v1_interface
    decoration_manager_implementation = {
        .destroy = decoration_manager_destroy,
        .get_toplevel_decoration = decoration_manager_get_toplevel_decoration,
};

static void bind_decoration_manager(struct wl_client *client, void *data,
                                    uint32_t version, uint32_t id) {
  struct wl_decoration_manager_impl *manager = data;

  struct wl_resource *resource = wl_resource_create(
      client, &zxdg_decoration_manager_v1_interface, version, id);
  if (!resource) {
    wl_client_post_no_memory(client);
    return;
  }

  wl_resource_set_implementation(resource, &decoration_manager_implementation,
                                 manager, NULL);

  log_printf("DECORATION", "Client bound to decoration manager (version %u)\n",
             version);
}

struct wl_decoration_manager_impl *
wl_decoration_create(struct wl_display *display) {
  struct wl_decoration_manager_impl *manager =
      calloc(1, sizeof(struct wl_decoration_manager_impl));
  if (!manager)
    return NULL;

  manager->display = display;
  wl_list_init(&manager->decorations);
  manager->global =
      wl_global_create(display, &zxdg_decoration_manager_v1_interface, 1,
                       manager, bind_decoration_manager);

  if (!manager->global) {
    free(manager);
    return NULL;
  }

  bool force_ssd = WawonaSettings_GetForceServerSideDecorations();
  log_printf("DECORATION",
             "✓ zxdg_decoration_manager_v1 initialized (Force SSD: %s)\n",
             force_ssd ? "enabled" : "disabled");

  return manager;
}

void wl_decoration_destroy(struct wl_decoration_manager_impl *manager) {
  if (!manager)
    return;

  if (manager->global) {
    wl_global_destroy(manager->global);
  }
  free(manager);
}

void wl_decoration_hot_reload(struct wl_decoration_manager_impl *manager) {
  if (!manager)
    return;

  log_printf("DECORATION", "Hot-reloading decorations for all clients...\n");

  bool force_ssd = WawonaSettings_GetForceServerSideDecorations();

  struct toplevel_decoration_impl *decoration;
  wl_list_for_each(decoration, &manager->decorations, link) {
    uint32_t final_mode;
    if (force_ssd) {
      final_mode = ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
    } else {
      // Revert to what client originally requested (or CSD if not forced)
      final_mode = decoration->requested_mode != 0
                       ? decoration->requested_mode
                       : ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;
    }

    if (decoration->current_mode == final_mode)
      continue;

    // Update the decided mode in the decoration implementation
    decoration->current_mode = final_mode;

    // Update the xdg_toplevel_impl
    struct xdg_toplevel_impl *xdg_toplevel =
        wl_resource_get_user_data(decoration->toplevel);
    if (xdg_toplevel) {
      xdg_toplevel->decoration_mode = final_mode;

      // Notify the compositor to update the window decoration immediately
      extern void macos_update_toplevel_decoration_mode(
          struct xdg_toplevel_impl * toplevel);
      macos_update_toplevel_decoration_mode(xdg_toplevel);
    }

    // Send configure event with the decided mode to the client
    zxdg_toplevel_decoration_v1_send_configure(decoration->resource,
                                               final_mode);

    log_printf("DECORATION",
               "Sent hot-reload configure with mode: %s to decoration %p\n",
               final_mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE
                   ? "client-side"
                   : "server-side",
               (void *)decoration);
  }
}
void wl_decoration_send_configure(struct xdg_toplevel_impl *toplevel) {
  if (!toplevel || !toplevel->decoration_data)
    return;

  struct toplevel_decoration_impl *decoration = toplevel->decoration_data;

  bool force_ssd = WawonaSettings_GetForceServerSideDecorations();
  uint32_t final_mode;

  if (force_ssd) {
    final_mode = ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
  } else {
    // Fallback to CSD if Force SSD is OFF and client hasn't requested anything
    final_mode = decoration->requested_mode != 0
                     ? decoration->requested_mode
                     : ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;
  }

  // Always update our internal state
  decoration->current_mode = final_mode;
  toplevel->decoration_mode = final_mode;

  // Send the configure event for the decoration
  zxdg_toplevel_decoration_v1_send_configure(decoration->resource, final_mode);

  log_printf("DECORATION",
             "Sent decoration configure with mode %s for toplevel %p\n",
             final_mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE ? "SSD"
                                                                        : "CSD",
             (void *)toplevel);
}
