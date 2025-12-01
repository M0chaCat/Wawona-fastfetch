#include "wayland_subcompositor.h"
#include <wayland-server-protocol.h>
#include <stdlib.h>
#include <stdio.h>

static void
subcompositor_destroy(struct wl_client *client, struct wl_resource *resource)
{
    (void)client;
    wl_resource_destroy(resource);
}

static void
subcompositor_get_subsurface(struct wl_client *client, struct wl_resource *resource, uint32_t id, struct wl_resource *surface, struct wl_resource *parent)
{
    (void)client; (void)surface; (void)parent;
    struct wl_resource *subsurface_resource = wl_resource_create(client, &wl_subsurface_interface, wl_resource_get_version(resource), id);
    if (!subsurface_resource) {
        wl_resource_post_no_memory(resource);
        return;
    }
    
    // We need to implement subsurface interface (configure, destroy, etc.)
    // But for now we just create the resource.
    // The surface/parent relation should be handled by the compositor implementation or subsurface impl.
    // For now, stub it.
    
    // wl_resource_set_implementation(subsurface_resource, &subsurface_interface, NULL, NULL);
}

static const struct wl_subcompositor_interface subcompositor_interface = {
    .destroy = subcompositor_destroy,
    .get_subsurface = subcompositor_get_subsurface,
};

static void
bind_subcompositor(struct wl_client *client, void *data, uint32_t version, uint32_t id)
{
    struct wl_subcompositor_impl *subcompositor = data;
    struct wl_resource *resource;

    resource = wl_resource_create(client, &wl_subcompositor_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }

    wl_resource_set_implementation(resource, &subcompositor_interface, subcompositor, NULL);
}

struct wl_subcompositor_impl *
wl_subcompositor_create(struct wl_display *display)
{
    struct wl_subcompositor_impl *sub = calloc(1, sizeof(struct wl_subcompositor_impl));
    if (!sub) return NULL;

    sub->display = display;
    
    sub->global = wl_global_create(display, &wl_subcompositor_interface, 1, sub, bind_subcompositor);
    if (!sub->global) {
        free(sub);
        return NULL;
    }

    return sub;
}

void
wl_subcompositor_destroy(struct wl_subcompositor_impl *sub)
{
    if (!sub) return;
    if (sub->global) wl_global_destroy(sub->global);
    free(sub);
}
