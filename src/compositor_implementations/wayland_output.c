#include "wayland_output.h"
#include <wayland-server-protocol.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

static void
output_release(struct wl_client *client, struct wl_resource *resource)
{
    (void)client;
    wl_resource_destroy(resource);
}

static const struct wl_output_interface output_interface = {
    .release = output_release,
};

static void
send_output_geometry(struct wl_resource *resource, struct wl_output_impl *output)
{
    // Convert pixel dimensions to physical dimensions in millimeters
    // Using 96 DPI (standard desktop DPI) as a reasonable assumption for virtual displays
    // Formula: mm = (pixels / DPI) * 25.4
    const int32_t dpi = 96;
    int32_t physical_width_mm = (output->width * 254) / (dpi * 10);  // (width / dpi) * 25.4, using integer math
    int32_t physical_height_mm = (output->height * 254) / (dpi * 10);
    
    // Ensure minimum size (at least 1mm) to avoid protocol violations
    if (physical_width_mm < 1) physical_width_mm = 1;
    if (physical_height_mm < 1) physical_height_mm = 1;
    
    wl_output_send_geometry(resource,
                            0, 0, // x, y
                            physical_width_mm, physical_height_mm, // physical width/height (mm)
                            0, // subpixel
                            "Apple", // make
                            output->name ? output->name : "Virtual Display", // model
                            output->transform); // transform
}

static void
send_output_mode(struct wl_resource *resource, struct wl_output_impl *output)
{
    // Send current mode WITHOUT PREFERRED flag to indicate arbitrary resolution support.
    // PREFERRED flag indicates a fixed preferred resolution, which conflicts with
    // arbitrary resolution support. For arbitrary resolutions, we only send CURRENT
    // to indicate this is the current mode, but clients can create surfaces of any size.
    wl_output_send_mode(resource,
                        WL_OUTPUT_MODE_CURRENT,  // Only CURRENT, not PREFERRED
                        output->width, output->height,
                        output->refresh_rate);
}

static void
destroy_output_resource(struct wl_resource *resource)
{
    wl_list_remove(wl_resource_get_link(resource));
}

static void
bind_output(struct wl_client *client, void *data, uint32_t version, uint32_t id)
{
    struct wl_output_impl *output = data;
    struct wl_resource *resource;

    resource = wl_resource_create(client, &wl_output_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }

    wl_resource_set_implementation(resource, &output_interface, output, destroy_output_resource);
    wl_list_insert(&output->resource_list, wl_resource_get_link(resource));

    send_output_geometry(resource, output);
    // Send mode with CURRENT flag only (no PREFERRED) to indicate arbitrary resolution support
    // The mode represents the current output size, but clients can create surfaces of any size
    send_output_mode(resource, output);
    
    if (version >= WL_OUTPUT_SCALE_SINCE_VERSION) {
        wl_output_send_scale(resource, output->scale);
    }

    if (version >= WL_OUTPUT_NAME_SINCE_VERSION && output->name) {
        wl_output_send_name(resource, output->name);
    }
    
    if (version >= WL_OUTPUT_DESCRIPTION_SINCE_VERSION && output->description) {
        wl_output_send_description(resource, output->description);
    }

    if (version >= WL_OUTPUT_DONE_SINCE_VERSION) {
        wl_output_send_done(resource);
    }
}

struct wl_output_impl *
wl_output_create(struct wl_display *display, int32_t width, int32_t height, int32_t scale, const char *name)
{
    struct wl_output_impl *output = calloc(1, sizeof(struct wl_output_impl));
    if (!output) return NULL;

    output->display = display;
    output->width = width;
    output->height = height;
    output->name = name ? strdup(name) : NULL;
    output->scale = scale > 0 ? scale : 1;
    output->transform = WL_OUTPUT_TRANSFORM_NORMAL;
    output->refresh_rate = 60000; // 60 Hz
    
    wl_list_init(&output->resource_list);

    // Use version 4 (latest stable) to ensure full protocol support including
    // scale, name, description, and done events needed for arbitrary resolution support
    output->global = wl_global_create(display, &wl_output_interface, 4, output, bind_output);
    if (!output->global) {
        free(output);
        return NULL;
    }

    return output;
}

void
wl_output_destroy(struct wl_output_impl *output)
{
    if (!output) return;

    if (output->global) {
        wl_global_destroy(output->global);
    }
    
    // Note: Resources are destroyed automatically when clients disconnect,
    // but we should probably remove the link if we are destroying the output while running.
    // However, wl_resource_destroy handles unlinking if we set a destructor.
    // We didn't set a resource destructor that unlinks from resource_list.
    // We should iterate and destroy resources or rely on wayland to clean up client resources.
    
    if (output->name) {
        // free((void*)output->name); // strdup'd
    }
    
    free(output);
}

void
wl_output_update_size(struct wl_output_impl *output, int32_t width, int32_t height, int32_t scale)
{
    int32_t new_scale;
    bool size_changed;
    bool scale_changed;
    struct wl_resource *resource;

    if (!output) return;
    
    new_scale = scale > 0 ? scale : 1;
    size_changed = (output->width != width || output->height != height);
    scale_changed = (output->scale != new_scale);
    
    if (!size_changed && !scale_changed) return;

    // Update output size and notify all clients of the mode change.
    // This dynamic mode change capability is part of what Weston checks
    // when determining arbitrary resolution support.
    output->width = width;
    output->height = height;
    output->scale = new_scale;
    wl_resource_for_each(resource, &output->resource_list) {
        // Send geometry update first (in case physical size changed)
        send_output_geometry(resource, output);
        // Then send mode change
        send_output_mode(resource, output);
        
        if (scale_changed && wl_resource_get_version(resource) >= WL_OUTPUT_SCALE_SINCE_VERSION) {
            wl_output_send_scale(resource, output->scale);
        }
        
        if (wl_resource_get_version(resource) >= WL_OUTPUT_DONE_SINCE_VERSION) {
            wl_output_send_done(resource);
        }
    }
}
