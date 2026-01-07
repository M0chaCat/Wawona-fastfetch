#include "xdg_shell.h"
#include "../core/WawonaCompositor.h"
#include "../core/WawonaSettings.h"
#include "../protocols/xdg-decoration-protocol.h"
#include "wayland_decoration.h"
#include <arpa/inet.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wayland-server-core.h>
#include <wayland-server-protocol.h>
#include <wayland-server.h>

#include "../logging/logging.h" // Include logging header

// Forward declaration for macOS window creation
extern void
macos_create_window_for_toplevel(struct xdg_toplevel_impl *toplevel);

struct xdg_surface_impl *xdg_surfaces = NULL;
static struct wl_client *nested_compositor_client = NULL;

// --- Forward Declarations ---
static void xdg_surface_destroy_resource(struct wl_resource *resource);
static void xdg_toplevel_destroy_resource(struct wl_resource *resource);

// --- Forward Declarations for Interface ---
static void xdg_surface_get_toplevel(struct wl_client *, struct wl_resource *,
                                     uint32_t);
static void xdg_surface_get_popup(struct wl_client *, struct wl_resource *,
                                  uint32_t, struct wl_resource *,
                                  struct wl_resource *);
static void xdg_surface_set_window_geometry(struct wl_client *,
                                            struct wl_resource *, int32_t,
                                            int32_t, int32_t, int32_t);
static void xdg_surface_ack_configure(struct wl_client *, struct wl_resource *,
                                      uint32_t);
static void xdg_toplevel_destroy(struct wl_client *, struct wl_resource *);
static void xdg_toplevel_set_parent(struct wl_client *, struct wl_resource *,
                                    struct wl_resource *);
static void xdg_toplevel_set_title(struct wl_client *, struct wl_resource *,
                                   const char *);
static void xdg_toplevel_set_app_id(struct wl_client *, struct wl_resource *,
                                    const char *);
static void xdg_toplevel_show_window_menu(struct wl_client *,
                                          struct wl_resource *,
                                          struct wl_resource *, uint32_t,
                                          int32_t, int32_t);
static void xdg_toplevel_move(struct wl_client *, struct wl_resource *,
                              struct wl_resource *, uint32_t);
static void xdg_toplevel_resize(struct wl_client *, struct wl_resource *,
                                struct wl_resource *, uint32_t, uint32_t);
static void xdg_toplevel_set_max_size(struct wl_client *, struct wl_resource *,
                                      int32_t, int32_t);
static void xdg_toplevel_set_min_size(struct wl_client *, struct wl_resource *,
                                      int32_t, int32_t);
static void xdg_toplevel_set_maximized(struct wl_client *,
                                       struct wl_resource *);
static void xdg_toplevel_unset_maximized(struct wl_client *,
                                         struct wl_resource *);
static void xdg_toplevel_set_fullscreen(struct wl_client *,
                                        struct wl_resource *,
                                        struct wl_resource *);
static void xdg_toplevel_unset_fullscreen(struct wl_client *,
                                          struct wl_resource *);
static void xdg_toplevel_set_minimized(struct wl_client *,
                                       struct wl_resource *);

// --- Interface Implementations ---
static const struct xdg_surface_interface xdg_surface_implementation = {
    .get_toplevel = xdg_surface_get_toplevel,
    .get_popup = xdg_surface_get_popup,
    .set_window_geometry = xdg_surface_set_window_geometry,
    .ack_configure = xdg_surface_ack_configure,
};

static const struct xdg_toplevel_interface xdg_toplevel_implementation = {
    .destroy = xdg_toplevel_destroy,
    .set_parent = xdg_toplevel_set_parent,
    .set_title = xdg_toplevel_set_title,
    .set_app_id = xdg_toplevel_set_app_id,
    .show_window_menu = xdg_toplevel_show_window_menu,
    .move = xdg_toplevel_move,
    .resize = xdg_toplevel_resize,
    .set_max_size = xdg_toplevel_set_max_size,
    .set_min_size = xdg_toplevel_set_min_size,
    .set_maximized = xdg_toplevel_set_maximized,
    .unset_maximized = xdg_toplevel_unset_maximized,
    .set_fullscreen = xdg_toplevel_set_fullscreen,
    .unset_fullscreen = xdg_toplevel_unset_fullscreen,
    .set_minimized = xdg_toplevel_set_minimized,
};

// --- XDG Toplevel ---

static void xdg_toplevel_set_parent(struct wl_client *client,
                                    struct wl_resource *resource,
                                    struct wl_resource *parent) {
  (void)client;
  (void)resource;
  (void)parent;
}

static void xdg_toplevel_set_title(struct wl_client *client,
                                   struct wl_resource *resource,
                                   const char *title) {
  (void)client;

  struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
  if (!toplevel) {
    return;
  }

  // Store the new title
  free(toplevel->title);
  toplevel->title = title ? strdup(title) : NULL;

  // Notify the compositor to update the window title
  // This will be handled by the Objective-C side
  extern void macos_update_toplevel_title(struct xdg_toplevel_impl * toplevel);
  macos_update_toplevel_title(toplevel);
}

static void xdg_toplevel_set_app_id(struct wl_client *client,
                                    struct wl_resource *resource,
                                    const char *app_id) {
  (void)client;

  struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
  if (!toplevel) {
    return;
  }

  // Store the app_id
  free(toplevel->app_id);
  toplevel->app_id = app_id ? strdup(app_id) : NULL;
}

static void xdg_toplevel_show_window_menu(struct wl_client *client,
                                          struct wl_resource *resource,
                                          struct wl_resource *seat,
                                          uint32_t serial, int32_t x,
                                          int32_t y) {
  (void)client;
  (void)resource;
  (void)seat;
  (void)serial;
  (void)x;
  (void)y;
}

static void xdg_toplevel_move(struct wl_client *client,
                              struct wl_resource *resource,
                              struct wl_resource *seat, uint32_t serial) {
  (void)client;
  (void)seat;
  (void)serial;
  struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
  if (toplevel) {
    macos_start_toplevel_move(toplevel);
  }
}

static void xdg_toplevel_set_minimized(struct wl_client *client,
                                       struct wl_resource *resource) {
  (void)client;
  struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
  if (toplevel) {
    macos_toplevel_set_minimized(toplevel);
  }
}

static void xdg_toplevel_resize(struct wl_client *client,
                                struct wl_resource *resource,
                                struct wl_resource *seat, uint32_t serial,
                                uint32_t edges) {
  (void)client;
  (void)seat;
  (void)serial;
  struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
  if (toplevel) {
    macos_start_toplevel_resize(toplevel, edges);
  }
}

static void xdg_toplevel_set_min_size(struct wl_client *client,
                                      struct wl_resource *resource,
                                      int32_t width, int32_t height) {
  // Accept any min size (including 0x0 which means no restriction)
  // This signals arbitrary resolution support - clients can create surfaces of
  // any size Log for debugging
  log_printf("XDG", "set_min_size: %dx%d (0x0 means no restriction)\n", width,
             height);
}

static void xdg_toplevel_set_max_size(struct wl_client *client,
                                      struct wl_resource *resource,
                                      int32_t width, int32_t height) {
  // Accept any max size (including 0x0 which means no restriction)
  // This signals arbitrary resolution support - clients can create surfaces of
  // any size Log for debugging
  log_printf("XDG", "set_max_size: %dx%d (0x0 means no restriction)\n", width,
             height);
}

static void xdg_toplevel_set_maximized(struct wl_client *client,
                                       struct wl_resource *resource) {
  (void)client;
  struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
  if (toplevel) {
    macos_toplevel_set_maximized(toplevel);
  }
}

static void xdg_toplevel_unset_maximized(struct wl_client *client,
                                         struct wl_resource *resource) {
  (void)client;
  struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
  if (toplevel) {
    macos_toplevel_unset_maximized(toplevel);
  }
}

static void xdg_toplevel_set_fullscreen(struct wl_client *client,
                                        struct wl_resource *resource,
                                        struct wl_resource *output) {
  (void)client;
  (void)output;
  struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
  if (toplevel) {
    macos_toplevel_set_fullscreen(toplevel);
  }
}

static void xdg_toplevel_unset_fullscreen(struct wl_client *client,
                                          struct wl_resource *resource) {
  (void)client;
  struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
  if (toplevel) {
    macos_toplevel_unset_fullscreen(toplevel);
  }
}

static void xdg_toplevel_destroy(struct wl_client *client,
                                 struct wl_resource *resource) {
  (void)client;
  (void)resource;
  // Stub - not implemented
}

static void xdg_surface_get_toplevel(struct wl_client *client,
                                     struct wl_resource *resource,
                                     uint32_t id) {
  struct xdg_surface_impl *xdg_surface;
  int requested_version;
  struct wl_resource *toplevel_resource;
  int toplevel_version;
  struct wl_array states;
  uint32_t *activated;
  uint32_t *maximized;
  uint32_t *fullscreen;
  int32_t cfg_width = 1024;
  int32_t cfg_height = 768;

  log_printf("XDG", "xdg_surface_get_toplevel called for resource %p\n",
             resource);
  xdg_surface = wl_resource_get_user_data(resource);
  // Use the same version as the xdg_surface (which matches wm_base version)
  // We can't use a higher version for child resources - Wayland protocol
  // requires version <= parent
  requested_version = wl_resource_get_version(resource);
  toplevel_resource = wl_resource_create(client, &xdg_toplevel_interface,
                                         requested_version, id);
  if (!toplevel_resource) {
    wl_resource_post_no_memory(resource);
    return;
  }

  struct xdg_toplevel_impl *toplevel =
      calloc(1, sizeof(struct xdg_toplevel_impl));
  if (!toplevel) {
    wl_resource_destroy(toplevel_resource);
    wl_resource_post_no_memory(resource);
    return;
  }

  toplevel->resource = toplevel_resource;
  toplevel->xdg_surface = xdg_surface;
  toplevel->decoration_data = NULL;

  // Initialize decoration mode based on compositor settings
  // 1 = CLIENT_SIDE (CSD), 2 = SERVER_SIDE (SSD)
  bool force_ssd = WawonaSettings_GetForceServerSideDecorations();
  toplevel->decoration_mode =
      force_ssd ? ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE
                : ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;

  xdg_surface->role = toplevel;

  wl_resource_set_implementation(toplevel_resource,
                                 &xdg_toplevel_implementation, toplevel, NULL);

  // Send initial configure event to unblock client

  // First send configure_bounds with 0x0 to signal no bounds restriction
  // (version 4+) Only send if client bound with version 4 or higher
  toplevel_version = wl_resource_get_version(toplevel_resource);
  if (toplevel_version >= XDG_TOPLEVEL_CONFIGURE_BOUNDS_SINCE_VERSION) {
    log_printf("XDG",
               "Sending configure_bounds 0x0 to toplevel %p (version %u, "
               "arbitrary resolution)\n",
               toplevel_resource, toplevel_version);
    xdg_toplevel_send_configure_bounds(toplevel_resource, 0, 0);
  } else {
    log_printf("XDG",
               "⚠️ Cannot send configure_bounds: toplevel_version=%u (need >=4, "
               "client bound with version %u)\n",
               toplevel_version, requested_version);
  }

  wl_array_init(&states);
  // Add activated state
  activated = wl_array_add(&states, sizeof(uint32_t));
  if (activated)
    *activated = XDG_TOPLEVEL_STATE_ACTIVATED;

  // Add maximized/fullscreen for initial state too
  maximized = wl_array_add(&states, sizeof(uint32_t));
  if (maximized)
    *maximized = XDG_TOPLEVEL_STATE_MAXIMIZED;

  fullscreen = wl_array_add(&states, sizeof(uint32_t));
  if (fullscreen)
    *fullscreen = XDG_TOPLEVEL_STATE_FULLSCREEN;

  // Choose a non-zero initial size to ensure clients render promptly
  // Prefer the wm_base's output size if known; otherwise fall back to 1024x768
  if (xdg_surface && xdg_surface->wm_base) {
    if (xdg_surface->wm_base->output_width > 0)
      cfg_width = xdg_surface->wm_base->output_width;
    if (xdg_surface->wm_base->output_height > 0)
      cfg_height = xdg_surface->wm_base->output_height;
  }
  log_printf("XDG", "Sending initial configure to toplevel %p (size: %dx%d)\n",
             toplevel_resource, cfg_width, cfg_height);
  toplevel->width = cfg_width;
  toplevel->height = cfg_height;
  xdg_toplevel_send_configure(toplevel_resource, cfg_width, cfg_height,
                              &states);
  wl_array_release(&states);

  xdg_surface_send_configure(resource, 1); // Serial 1

  // Create native window for this toplevel
  macos_create_window_for_toplevel(toplevel);
}

static void xdg_surface_get_popup(struct wl_client *client,
                                  struct wl_resource *resource, uint32_t id,
                                  struct wl_resource *parent,
                                  struct wl_resource *positioner) {
  (void)client;
  (void)resource;
  (void)id;
  (void)parent;
  (void)positioner;
}

static void xdg_surface_set_window_geometry(struct wl_client *client,
                                            struct wl_resource *resource,
                                            int32_t x, int32_t y, int32_t width,
                                            int32_t height) {
  (void)client;
  struct xdg_surface_impl *xdg_surface = wl_resource_get_user_data(resource);
  if (!xdg_surface) {
    return;
  }

  xdg_surface->geometry_x = x;
  xdg_surface->geometry_y = y;
  xdg_surface->geometry_width = width;
  xdg_surface->geometry_height = height;
  xdg_surface->has_geometry = true;

  log_printf("XDG", "set_window_geometry: %d,%d %dx%d\n", x, y, width, height);
}

static void xdg_surface_ack_configure(struct wl_client *client,
                                      struct wl_resource *resource,
                                      uint32_t serial) {
  struct xdg_surface_impl *xdg_surface;
  (void)client;
  xdg_surface = wl_resource_get_user_data(resource);
  if (xdg_surface) {
    xdg_surface->configured = true;
    xdg_surface->last_acked_serial = serial;

    // Sync to wl_surface_impl if it exists
    if (xdg_surface->wl_surface) {
      xdg_surface->wl_surface->configured = true;
    }
  }
}

static void wm_base_destroy_resource(struct wl_client *client,
                                     struct wl_resource *resource) {
  (void)client;
  wl_resource_destroy(resource);
}

static void wm_base_create_positioner(struct wl_client *client,
                                      struct wl_resource *resource,
                                      uint32_t id) {
  (void)client;
  (void)resource;
  (void)id;
}

static void wm_base_get_xdg_surface(struct wl_client *client,
                                    struct wl_resource *resource, uint32_t id,
                                    struct wl_resource *surface) {
  struct xdg_wm_base_impl *wm_base;
  struct wl_resource *xdg_resource;
  struct xdg_surface_impl *xdg_surface;

  log_printf("XDG", "wm_base_get_xdg_surface called\n");
  wm_base = wl_resource_get_user_data(resource);
  xdg_resource = wl_resource_create(client, &xdg_surface_interface,
                                    wl_resource_get_version(resource), id);
  if (!xdg_resource) {
    wl_resource_post_no_memory(resource);
    return;
  }

  xdg_surface = calloc(1, sizeof(struct xdg_surface_impl));
  if (!xdg_surface) {
    wl_resource_post_no_memory(resource);
    return;
  }
  xdg_surface->resource = xdg_resource;
  xdg_surface->wm_base = wm_base;
  xdg_surface->wl_surface = wl_resource_get_user_data(surface);
  xdg_surface->next = xdg_surfaces;
  xdg_surfaces = xdg_surface;

  wl_resource_set_implementation(xdg_resource, &xdg_surface_implementation,
                                 xdg_surface, NULL);
}

static void wm_base_pong(struct wl_client *client, struct wl_resource *resource,
                         uint32_t serial) {
  (void)client;
  (void)resource;
  (void)serial;
}

static const struct xdg_wm_base_interface wm_base_interface = {
    .destroy = wm_base_destroy_resource,
    .create_positioner = wm_base_create_positioner,
    .get_xdg_surface = wm_base_get_xdg_surface,
    .pong = wm_base_pong,
};

static void bind_wm_base(struct wl_client *client, void *data, uint32_t version,
                         uint32_t id) {
  struct xdg_wm_base_impl *wm_base = data;
  struct wl_resource *resource;

  resource =
      wl_resource_create(client, &xdg_wm_base_interface, (int)version, id);
  if (!resource) {
    wl_client_post_no_memory(client);
    return;
  }

  wl_resource_set_implementation(resource, &wm_base_interface, wm_base, NULL);
}

struct xdg_wm_base_impl *xdg_wm_base_create(struct wl_display *display) {
  struct xdg_wm_base_impl *wm_base = calloc(1, sizeof(struct xdg_wm_base_impl));
  if (!wm_base)
    return NULL;

  wm_base->display = display;
  wm_base->version = 4; // Use version 4 to support configure_bounds (needed for
                        // arbitrary resolution detection)

  wm_base->global = wl_global_create(display, &xdg_wm_base_interface, 4,
                                     wm_base, bind_wm_base);
  if (!wm_base->global) {
    free(wm_base);
    return NULL;
  }

  return wm_base;
}

void xdg_wm_base_destroy(struct xdg_wm_base_impl *wm_base) {
  if (!wm_base)
    return;
  if (wm_base->global)
    wl_global_destroy(wm_base->global);
  free(wm_base);
}

void xdg_wm_base_send_configure_to_all_toplevels(
    struct xdg_wm_base_impl *wm_base, int32_t width, int32_t height) {
  struct xdg_surface_impl *surface;
  if (!wm_base)
    return;

  // Update stored size
  wm_base->output_width = width;
  wm_base->output_height = height;

  // Iterate all surfaces
  surface = xdg_surfaces;
  while (surface) {
    // Store next pointer before any operations that might modify the list
    struct xdg_surface_impl *next_surface = surface->next;

    if (surface->wm_base == wm_base &&
        surface->role) { // Check it has a role (toplevel)
      struct xdg_toplevel_impl *toplevel =
          (struct xdg_toplevel_impl *)surface->role;
      struct wl_resource *toplevel_resource = toplevel->resource;
      uint32_t toplevel_version;
      uint32_t wm_base_version;
      struct wl_array states;
      uint32_t *activated;
      int32_t cfg_w;
      int32_t cfg_h;
      struct wl_client *client;

      // SAFETY: Validate the surface resource is still valid before sending
      if (!surface->resource) {
        surface = next_surface;
        continue;
      }

      // Validate the toplevel and its resource
      if (!toplevel || !toplevel_resource) {
        surface = next_surface;
        continue;
      }

      // Check if the client is still connected
      client = wl_resource_get_client(surface->resource);
      if (!client) {
        surface = next_surface;
        continue;
      }

      // Validate the toplevel resource has a valid client
      struct wl_client *toplevel_client =
          wl_resource_get_client(toplevel_resource);
      if (!toplevel_client) {
        surface = next_surface;
        continue;
      }

      // Only send if it's a toplevel (check interface or implementation)
      // For simplicity, assume role is toplevel if set (we only support
      // toplevel now)

      // Check if the toplevel resource is still valid
      if (!wl_resource_get_user_data(toplevel_resource)) {
        continue;
      }

      // CRITICAL: Check resource versions are valid before accessing (prevents
      // crash)
      if (wl_resource_get_version(toplevel_resource) == 0 ||
          wl_resource_get_version(surface->resource) == 0) {
        log_printf("XDG",
                   "⚠️ Skipping configure: invalid resource versions "
                   "(toplevel=%u, surface=%u)\n",
                   wl_resource_get_version(toplevel_resource),
                   wl_resource_get_version(surface->resource));
        continue;
      }

      // Send configure_bounds with 0x0 first (version 4+) to signal no bounds
      // restriction
      toplevel_version = wl_resource_get_version(toplevel_resource);
      wm_base_version = wl_resource_get_version(
          surface->resource); // xdg_surface version = wm_base version
      if (toplevel_version >= XDG_TOPLEVEL_CONFIGURE_BOUNDS_SINCE_VERSION &&
          wm_base_version >= XDG_TOPLEVEL_CONFIGURE_BOUNDS_SINCE_VERSION) {
        log_printf("XDG",
                   "Sending configure_bounds 0x0 to toplevel %p (version %u, "
                   "arbitrary resolution)\n",
                   toplevel_resource, toplevel_version);
        xdg_toplevel_send_configure_bounds(toplevel_resource, 0, 0);
      } else {
        log_printf("XDG",
                   "⚠️ Cannot send configure_bounds: toplevel_version=%u, "
                   "wm_base_version=%u (need >=4)\n",
                   toplevel_version, wm_base_version);
      }

      // Send configure with a concrete size hint to ensure clients render
      // Use provided width/height if non-zero; else fallback to wm_base stored
      // size; else 1024x768
      wl_array_init(&states);
      activated = wl_array_add(&states, sizeof(uint32_t));
      if (activated)
        *activated = XDG_TOPLEVEL_STATE_ACTIVATED;

      cfg_w = width > 0
                  ? width
                  : (wm_base->output_width > 0 ? wm_base->output_width : 1024);
      cfg_h = height > 0
                  ? height
                  : (wm_base->output_height > 0 ? wm_base->output_height : 768);
      log_printf("XDG", "Sending configure %dx%d to toplevel %p\n", cfg_w,
                 cfg_h, toplevel_resource);
      toplevel->width = cfg_w;
      toplevel->height = cfg_h;
      xdg_toplevel_send_configure(toplevel_resource, cfg_w, cfg_h, &states);
      wl_array_release(&states);

      // Also send decoration configure if attached
      wl_decoration_send_configure(toplevel);

      xdg_surface_send_configure(surface->resource,
                                 ++surface->configure_serial);
    }
    surface = next_surface;
  }
}

void xdg_wm_base_set_output_size(struct xdg_wm_base_impl *wm_base,
                                 int32_t width, int32_t height) {
  if (wm_base) {
    wm_base->output_width = width;
    wm_base->output_height = height;
  }
}

bool xdg_surface_is_toplevel(struct wl_surface_impl *wl_surface) {
  struct xdg_surface_impl *surface = xdg_surfaces;
  while (surface) {
    if (surface->wl_surface == wl_surface && surface->role) {
      return true;
    }
    surface = surface->next;
  }
  return false;
}

struct xdg_toplevel_impl *
xdg_surface_get_toplevel_from_wl_surface(struct wl_surface_impl *wl_surface) {
  struct wl_surface_impl *current = wl_surface;

  // Walk up the tree if this is a subsurface
  while (current && current->parent) {
    current = current->parent;
  }

  // Now find the xdg_surface for this root surface
  struct xdg_surface_impl *surface = xdg_surfaces;
  while (surface) {
    if (surface->wl_surface == current && surface->role) {
      return (struct xdg_toplevel_impl *)surface->role;
    }
    surface = surface->next;
  }
  return NULL;
}

void xdg_shell_mark_nested_compositor(struct wl_client *client) {
  nested_compositor_client = client;
}

struct wl_client *nested_compositor_client_from_xdg_shell(void) {
  return nested_compositor_client;
}

static void xdg_toplevel_destroy_resource(struct wl_resource *resource) {
  struct xdg_toplevel_impl *toplevel = wl_resource_get_user_data(resource);
  if (toplevel) {
    // Clear the native window reference to prevent use-after-free
    toplevel->native_window = NULL;

    // Free strings
    free(toplevel->title);
    free(toplevel->app_id);

    free(toplevel);
  }
}
