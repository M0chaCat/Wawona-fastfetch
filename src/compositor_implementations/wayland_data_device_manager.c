#include "wayland_data_device_manager.h"
#include <wayland-server-protocol.h>
#include <stdlib.h>

static void
create_data_source(struct wl_client *client, struct wl_resource *resource, uint32_t id)
{
    (void)client;
    (void)resource;
    (void)id;
    // Stub implementation - data source creation
    // For now, just acknowledge the request
}

static void
get_data_device(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *seat)
{
    (void)client;
    (void)resource;
    (void)id;
    (void)seat;
    // Stub implementation - data device creation
    // For now, just acknowledge the request
}

static const struct wl_data_device_manager_interface data_device_manager_interface = {
    .create_data_source = create_data_source,
    .get_data_device = get_data_device,
};

static void
bind_data_device_manager(struct wl_client *client, void *data, uint32_t version, uint32_t id)
{
    struct wl_data_device_manager_impl *manager = data;
    struct wl_resource *resource;

    resource = wl_resource_create(client, &wl_data_device_manager_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }

    wl_resource_set_implementation(resource, &data_device_manager_interface, manager, NULL);
}

struct wl_data_device_manager_impl *
wl_data_device_manager_create(struct wl_display *display)
{
    struct wl_data_device_manager_impl *manager = calloc(1, sizeof(struct wl_data_device_manager_impl));
    if (!manager) return NULL;

    manager->display = display;
    
    // Create global for wl_data_device_manager interface (version 3 is standard)
    manager->global = wl_global_create(display, &wl_data_device_manager_interface, 3, manager, bind_data_device_manager);
    if (!manager->global) {
        free(manager);
        return NULL;
    }
    
    return manager;
}
