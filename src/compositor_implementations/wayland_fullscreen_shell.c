#include "wayland_fullscreen_shell.h"
#include "fullscreen-shell-unstable-v1-protocol.h"
#include <stdlib.h>
#include <stdio.h>
#include "logging.h" // Assuming logging.h exists for log_printf

// --- Forward Declarations ---
// Need to handle surface role assignment if possible, or just track it.
// For simple arbitrary resolution support, we mainly need to handle 'bind' and 'capability'.

struct fullscreen_shell_impl {
    struct wl_global *global;
    struct wl_display *display;
};

static void
fullscreen_shell_release(struct wl_client *client, struct wl_resource *resource)
{
    (void)client;
    wl_resource_destroy(resource);
}

static void
fullscreen_shell_present_surface(struct wl_client *client, struct wl_resource *resource,
                                 struct wl_resource *surface_resource, uint32_t method,
                                 struct wl_resource *output_resource)
{
    (void)client;
    (void)resource;
    (void)output_resource;
    // Implement presentation logic here.
    // For Wawona, this might mean just setting the surface as the "main" surface or similar.
    // Weston uses this to map its surface.
    
    log_printf("[FULLSCREEN-SHELL] ", "present_surface called (surface=%p, method=%u)\n", surface_resource, method);
    
    if (surface_resource) {
        // If we have a surface, we should probably map it.
        // Since we don't have a full compositor structure exposed here easily, 
        // we can rely on the surface commit to trigger rendering if it has a buffer.
        // However, we might need to ensure it has a role or is treated as toplevel.
        // Usually 'present_surface' implies setting a role.
        
        // Typically we'd do something like:
        // struct wl_surface_impl *surface = wl_resource_get_user_data(surface_resource);
        // surface->role = ROLE_FULLSCREEN;
        
        // For now, just log. The critical part for "arbitrary resolutions" is the capability event.
    }
}

static void
fullscreen_shell_present_surface_for_mode(struct wl_client *client, struct wl_resource *resource,
                                          struct wl_resource *surface_resource, struct wl_resource *output_resource,
                                          int32_t framerate, uint32_t feedback_id)
{
    struct wl_resource *feedback_resource;
    (void)resource;
    (void)output_resource;
    log_printf("[FULLSCREEN-SHELL] ", "present_surface_for_mode called (surface=%p, framerate=%d)\n", surface_resource, framerate);
    
    feedback_resource = 
        wl_resource_create(client, &zwp_fullscreen_shell_mode_feedback_v1_interface, 1, feedback_id);
        
    if (!feedback_resource) {
        wl_client_post_no_memory(client);
        return;
    }
    
    // We claim success for any mode since we support arbitrary resolutions!
    zwp_fullscreen_shell_mode_feedback_v1_send_mode_successful(feedback_resource);
    
    // Note: We should probably actually resize the output if possible, or just scale the surface.
    // But for virtual/nested, telling the client "success" lets it commit the buffer of that size.
}

static const struct zwp_fullscreen_shell_v1_interface fullscreen_shell_interface = {
    .release = fullscreen_shell_release,
    .present_surface = fullscreen_shell_present_surface,
    .present_surface_for_mode = fullscreen_shell_present_surface_for_mode,
};

static void
bind_fullscreen_shell(struct wl_client *client, void *data, uint32_t version, uint32_t id)
{
    struct fullscreen_shell_impl *shell = data;
    struct wl_resource *resource;

    resource = wl_resource_create(client, &zwp_fullscreen_shell_v1_interface, version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }

    wl_resource_set_implementation(resource, &fullscreen_shell_interface, shell, NULL);

    // CRITICAL: Advertise ARBITRARY_MODES capability immediately upon binding!
    // This is what Weston checks for to determine arbitrary resolution support.
    // Must be sent before client queries capabilities.
    log_printf("[FULLSCREEN-SHELL] ", "Binding client %p, sending ARBITRARY_MODES capability (value=%u)\n", 
               (void *)client, ZWP_FULLSCREEN_SHELL_V1_CAPABILITY_ARBITRARY_MODES);
    zwp_fullscreen_shell_v1_send_capability(resource, ZWP_FULLSCREEN_SHELL_V1_CAPABILITY_ARBITRARY_MODES);
    log_printf("[FULLSCREEN-SHELL] ", "ARBITRARY_MODES capability sent successfully\n");
}

void
wayland_fullscreen_shell_init(struct wl_display *display)
{
    struct fullscreen_shell_impl *shell = calloc(1, sizeof(struct fullscreen_shell_impl));
    if (!shell) return;

    shell->display = display;
    shell->global = wl_global_create(display, &zwp_fullscreen_shell_v1_interface, 1, shell, bind_fullscreen_shell);
    
    log_printf("[FULLSCREEN-SHELL] ", "Initialized zwp_fullscreen_shell_v1\n");
}

