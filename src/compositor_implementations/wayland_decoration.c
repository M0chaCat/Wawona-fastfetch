// wayland_decoration.c - XDG Decoration Protocol Implementation
// Implements zxdg_decoration_manager_v1 for server-side/client-side decoration negotiation
// Respects the "Force Server-Side Decorations" setting in Wawona

#include "wayland_decoration.h"
#include "../protocols/xdg-decoration-protocol.h"
#include "../core/WawonaSettings.h"
#include "../logging/logging.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// --- Toplevel Decoration Implementation ---

struct toplevel_decoration_impl {
    struct wl_resource *resource;
    struct wl_resource *toplevel;
    struct wl_decoration_manager_impl *manager;
    uint32_t pending_mode;
    uint32_t current_mode;
};

static void
toplevel_decoration_destroy(struct wl_client *client, struct wl_resource *resource)
{
    (void)client;
    wl_resource_destroy(resource);
}

static void
toplevel_decoration_set_mode(struct wl_client *client, struct wl_resource *resource, uint32_t mode)
{
    (void)client;
    struct toplevel_decoration_impl *decoration = wl_resource_get_user_data(resource);
    if (!decoration) return;
    
    log_printf("DECORATION", "Client requested decoration mode: %s\n",
               mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE ? "client-side" :
               mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE ? "server-side" : "unknown");
    
    // Check the Force Server-Side Decorations setting
    bool force_ssd = WawonaSettings_GetForceServerSideDecorations();
    
    uint32_t final_mode;
    if (force_ssd) {
        // Force server-side decorations regardless of client preference
        final_mode = ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE;
        log_printf("DECORATION", "Force SSD enabled - using server-side decorations\n");
    } else {
        // Honor client preference
        final_mode = mode;
        log_printf("DECORATION", "Force SSD disabled - honoring client request: %s\n",
                   mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE ? "CSD" : "SSD");
    }
    
    decoration->current_mode = final_mode;
    
    // Send configure event with the decided mode
    zxdg_toplevel_decoration_v1_send_configure(resource, final_mode);
    log_printf("DECORATION", "Sent configure with mode: %s\n",
               final_mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE ? "client-side" : "server-side");
}

static void
toplevel_decoration_unset_mode(struct wl_client *client, struct wl_resource *resource)
{
    (void)client;
    struct toplevel_decoration_impl *decoration = wl_resource_get_user_data(resource);
    if (!decoration) return;
    
    log_printf("DECORATION", "Client unset decoration mode (using compositor preference)\n");
    
    // When mode is unset, use compositor preference
    bool force_ssd = WawonaSettings_GetForceServerSideDecorations();
    uint32_t mode = force_ssd ? ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE 
                              : ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;
    
    decoration->current_mode = mode;
    zxdg_toplevel_decoration_v1_send_configure(resource, mode);
}

static const struct zxdg_toplevel_decoration_v1_interface toplevel_decoration_implementation = {
    .destroy = toplevel_decoration_destroy,
    .set_mode = toplevel_decoration_set_mode,
    .unset_mode = toplevel_decoration_unset_mode,
};

static void
toplevel_decoration_destroy_resource(struct wl_resource *resource)
{
    struct toplevel_decoration_impl *decoration = wl_resource_get_user_data(resource);
    if (decoration) {
        free(decoration);
    }
}

// --- Decoration Manager Implementation ---

struct wl_decoration_manager_impl {
    struct wl_global *global;
    struct wl_display *display;
};

static void
decoration_manager_destroy(struct wl_client *client, struct wl_resource *resource)
{
    (void)client;
    wl_resource_destroy(resource);
}

static void
decoration_manager_get_toplevel_decoration(struct wl_client *client, struct wl_resource *resource,
                                           uint32_t id, struct wl_resource *toplevel)
{
    struct wl_decoration_manager_impl *manager = wl_resource_get_user_data(resource);
    
    struct wl_resource *decoration_resource = wl_resource_create(
        client, &zxdg_toplevel_decoration_v1_interface, 
        wl_resource_get_version(resource), id);
    
    if (!decoration_resource) {
        wl_resource_post_no_memory(resource);
        return;
    }
    
    struct toplevel_decoration_impl *decoration = calloc(1, sizeof(struct toplevel_decoration_impl));
    if (!decoration) {
        wl_resource_destroy(decoration_resource);
        wl_resource_post_no_memory(resource);
        return;
    }
    
    decoration->resource = decoration_resource;
    decoration->toplevel = toplevel;
    decoration->manager = manager;
    decoration->pending_mode = 0;
    decoration->current_mode = 0;
    
    wl_resource_set_implementation(decoration_resource, &toplevel_decoration_implementation, 
                                   decoration, toplevel_decoration_destroy_resource);
    
    // Send initial configure with compositor preference
    bool force_ssd = WawonaSettings_GetForceServerSideDecorations();
    uint32_t initial_mode = force_ssd ? ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE 
                                      : ZXDG_TOPLEVEL_DECORATION_V1_MODE_CLIENT_SIDE;
    
    decoration->current_mode = initial_mode;
    zxdg_toplevel_decoration_v1_send_configure(decoration_resource, initial_mode);
    
    log_printf("DECORATION", "Created toplevel decoration for toplevel %p, initial mode: %s (Force SSD: %s)\n",
               (void *)toplevel, 
               initial_mode == ZXDG_TOPLEVEL_DECORATION_V1_MODE_SERVER_SIDE ? "server-side" : "client-side",
               force_ssd ? "enabled" : "disabled");
}

static const struct zxdg_decoration_manager_v1_interface decoration_manager_implementation = {
    .destroy = decoration_manager_destroy,
    .get_toplevel_decoration = decoration_manager_get_toplevel_decoration,
};

static void
bind_decoration_manager(struct wl_client *client, void *data, uint32_t version, uint32_t id)
{
    struct wl_decoration_manager_impl *manager = data;
    
    struct wl_resource *resource = wl_resource_create(client, &zxdg_decoration_manager_v1_interface, 
                                                       version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(resource, &decoration_manager_implementation, manager, NULL);
    
    log_printf("DECORATION", "Client bound to decoration manager (version %u)\n", version);
}

struct wl_decoration_manager_impl *
wl_decoration_create(struct wl_display *display)
{
    struct wl_decoration_manager_impl *manager = calloc(1, sizeof(struct wl_decoration_manager_impl));
    if (!manager) return NULL;
    
    manager->display = display;
    manager->global = wl_global_create(display, &zxdg_decoration_manager_v1_interface, 1, 
                                       manager, bind_decoration_manager);
    
    if (!manager->global) {
        free(manager);
        return NULL;
    }
    
    bool force_ssd = WawonaSettings_GetForceServerSideDecorations();
    log_printf("DECORATION", "✓ zxdg_decoration_manager_v1 initialized (Force SSD: %s)\n",
               force_ssd ? "enabled" : "disabled");
    
    return manager;
}

void
wl_decoration_destroy(struct wl_decoration_manager_impl *manager)
{
    if (!manager) return;
    
    if (manager->global) {
        wl_global_destroy(manager->global);
    }
    free(manager);
}

