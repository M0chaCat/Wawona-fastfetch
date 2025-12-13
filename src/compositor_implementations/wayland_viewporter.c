#include "wayland_viewporter.h"
#include <stdlib.h>

#include <wayland-server-core.h>
#include <wayland-server.h>
#include "wayland_viewporter.h"
#include "WawonaCompositor.h"

// Forward declarations
static void bind_viewporter(struct wl_client *client, void *data, uint32_t version, uint32_t id);
static void viewport_destroy(struct wl_client *client, struct wl_resource *resource);
static void viewport_set_source(struct wl_client *client, struct wl_resource *resource,
                                wl_fixed_t x, wl_fixed_t y, wl_fixed_t width, wl_fixed_t height);
static void viewport_set_destination(struct wl_client *client, struct wl_resource *resource,
                                     int32_t width, int32_t height);

// Interface implementations (generated protocol symbols)
extern const struct wl_interface wp_viewporter_interface;
extern const struct wl_interface wp_viewport_interface;

// Viewporter interface implementation
static void viewporter_destroy(struct wl_client *client, struct wl_resource *resource) {
    wl_resource_destroy(resource);
}

static const struct {
    void (*destroy)(struct wl_client *, struct wl_resource *);
    void (*set_source)(struct wl_client *, struct wl_resource *, wl_fixed_t, wl_fixed_t, wl_fixed_t, wl_fixed_t);
    void (*set_destination)(struct wl_client *, struct wl_resource *, int32_t, int32_t);
} viewport_interface_impl = {
    .destroy = viewport_destroy,
    .set_source = viewport_set_source,
    .set_destination = viewport_set_destination,
};

static void viewporter_get_viewport(struct wl_client *client, struct wl_resource *resource,
                                    uint32_t id, struct wl_resource *surface_resource) {
    struct wp_viewporter_impl *viewporter = wl_resource_get_user_data(resource);
    struct wl_surface_impl *surface;
    struct wl_resource *vp_res;
    struct wl_viewport_impl *vp;
    
    (void)viewporter;

    surface = wl_resource_get_user_data(surface_resource);
    if (!surface) {
        wl_resource_post_error(resource, 0, "Invalid wl_surface for viewport");
        return;
    }

    vp_res = wl_resource_create(client, &wp_viewport_interface,
                                                    wl_resource_get_version(resource), id);
    if (!vp_res) {
        wl_client_post_no_memory(client);
        return;
    }

    vp = calloc(1, sizeof(struct wl_viewport_impl));
    if (!vp) {
        wl_client_post_no_memory(client);
        wl_resource_destroy(vp_res);
        return;
    }

    vp->resource = vp_res;
    vp->surface = surface;
    vp->has_source = false;
    vp->has_destination = false;

    // Attach viewport to surface
    surface->viewport = vp;

    wl_resource_set_implementation(vp_res, (const void *)&viewport_interface_impl, vp, NULL);
}

// Bind function for wp_viewporter global
static const struct {
    void (*destroy)(struct wl_client *, struct wl_resource *);
    void (*get_viewport)(struct wl_client *, struct wl_resource *, uint32_t, struct wl_resource *);
} viewporter_impl = {
    .destroy = viewporter_destroy,
    .get_viewport = viewporter_get_viewport,
};

static void bind_viewporter(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wp_viewporter_impl *viewporter = data;
    struct wl_resource *res = wl_resource_create(client, &wp_viewporter_interface, (int)version, id);
    if (!res) {
        wl_client_post_no_memory(client);
        return;
    }

    // Minimal interface for wp_viewporter
    wl_resource_set_implementation(res, (const void *)&viewporter_impl, viewporter, NULL);
}

// Public create function
struct wp_viewporter_impl *
wp_viewporter_create(struct wl_display *display)
{
    struct wp_viewporter_impl *vp = calloc(1, sizeof(struct wp_viewporter_impl));
    if (!vp) return NULL;

    vp->display = display;
    vp->global = wl_global_create(display, &wp_viewporter_interface, 1, vp, bind_viewporter);
    if (!vp->global) {
        free(vp);
        return NULL;
    }
    return vp;
}

// Helpers
struct wl_viewport_impl *wl_viewport_from_surface(struct wl_surface_impl *surface) {
    if (!surface) return NULL;
    return (struct wl_viewport_impl *)surface->viewport;
}

// Viewport methods
static void viewport_destroy(struct wl_client *client, struct wl_resource *resource) {
    struct wl_viewport_impl *vp;
    (void)client;
    vp = wl_resource_get_user_data(resource);
    if (vp) {
        if (vp->surface && vp->surface->viewport == vp) {
            vp->surface->viewport = NULL;
        }
        free(vp);
    }
    wl_resource_destroy(resource);
}

static void viewport_set_source(struct wl_client *client, struct wl_resource *resource,
                                wl_fixed_t x, wl_fixed_t y, wl_fixed_t width, wl_fixed_t height) {
    struct wl_viewport_impl *vp;
    (void)client;
    vp = wl_resource_get_user_data(resource);
    if (!vp) return;
    // Convert from wl_fixed to float
    vp->src_x = (float)wl_fixed_to_double(x);
    vp->src_y = (float)wl_fixed_to_double(y);
    vp->src_width = (float)wl_fixed_to_double(width);
    vp->src_height = (float)wl_fixed_to_double(height);
    vp->has_source = (vp->src_width > 0.0f && vp->src_height > 0.0f);
}

static void viewport_set_destination(struct wl_client *client, struct wl_resource *resource,
                                     int32_t width, int32_t height) {
    struct wl_viewport_impl *vp;
    (void)client;
    vp = wl_resource_get_user_data(resource);
    if (!vp) return;
    vp->dst_width = width;
    vp->dst_height = height;
    vp->has_destination = (width > 0 && height > 0);
}
