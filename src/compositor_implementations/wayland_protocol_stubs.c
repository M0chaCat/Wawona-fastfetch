#include "wayland_protocol_stubs.h"
#include "../protocols/text-input-v3-protocol.h"
#include "../protocols/text-input-v1-protocol.h"
#include <stdlib.h>
#include <string.h>

void
register_protocol_stubs(struct wl_display *display)
{
    (void)display;
    // Register global interfaces for protocols we want to advertise but not fully implement yet
}

// NOTE: wl_decoration_create is now implemented in wayland_decoration.c

struct wl_toplevel_icon_manager_impl *
wl_toplevel_icon_create(struct wl_display *display)
{
    (void)display;
    // Stub implementation - not critical
    return NULL;
}

struct wl_activation_manager_impl *
wl_activation_create(struct wl_display *display)
{
    (void)display;
    return NULL;
}

struct wl_fractional_scale_manager_impl *
wl_fractional_scale_create(struct wl_display *display)
{
    (void)display;
    return NULL;
}

struct wl_cursor_shape_manager_impl *
wl_cursor_shape_create(struct wl_display *display)
{
    (void)display;
    return NULL;
}

// ============================================================================
// Text Input v3 Implementation
// ============================================================================

static void text_input_v3_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void text_input_v3_enable(struct wl_client *client, struct wl_resource *resource) {
    (void)client; (void)resource;
    // Text input enabled - ready for input
}

static void text_input_v3_disable(struct wl_client *client, struct wl_resource *resource) {
    (void)client; (void)resource;
    // Text input disabled
}

static void text_input_v3_set_surrounding_text(struct wl_client *client, struct wl_resource *resource,
                                                const char *text, int32_t cursor, int32_t anchor) {
    (void)client; (void)resource; (void)text; (void)cursor; (void)anchor;
}

static void text_input_v3_set_text_change_cause(struct wl_client *client, struct wl_resource *resource,
                                                 uint32_t cause) {
    (void)client; (void)resource; (void)cause;
}

static void text_input_v3_set_content_type(struct wl_client *client, struct wl_resource *resource,
                                            uint32_t hint, uint32_t purpose) {
    (void)client; (void)resource; (void)hint; (void)purpose;
}

static void text_input_v3_set_cursor_rectangle(struct wl_client *client, struct wl_resource *resource,
                                                int32_t x, int32_t y, int32_t width, int32_t height) {
    (void)client; (void)resource; (void)x; (void)y; (void)width; (void)height;
}

static void text_input_v3_commit(struct wl_client *client, struct wl_resource *resource) {
    (void)client; (void)resource;
    // Commit current state - send done event
    zwp_text_input_v3_send_done(resource, 0);
}

static const struct zwp_text_input_v3_interface text_input_v3_impl = {
    .destroy = text_input_v3_destroy,
    .enable = text_input_v3_enable,
    .disable = text_input_v3_disable,
    .set_surrounding_text = text_input_v3_set_surrounding_text,
    .set_text_change_cause = text_input_v3_set_text_change_cause,
    .set_content_type = text_input_v3_set_content_type,
    .set_cursor_rectangle = text_input_v3_set_cursor_rectangle,
    .commit = text_input_v3_commit,
};

static void text_input_manager_v3_destroy(struct wl_client *client, struct wl_resource *resource) {
    (void)client;
    wl_resource_destroy(resource);
}

static void text_input_manager_v3_get_text_input(struct wl_client *client, struct wl_resource *resource,
                                                  uint32_t id, struct wl_resource *seat) {
    (void)seat;
    struct wl_resource *text_input = wl_resource_create(client, &zwp_text_input_v3_interface,
                                                         wl_resource_get_version(resource), id);
    if (!text_input) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(text_input, &text_input_v3_impl, NULL, NULL);
}

static const struct zwp_text_input_manager_v3_interface text_input_manager_v3_impl = {
    .destroy = text_input_manager_v3_destroy,
    .get_text_input = text_input_manager_v3_get_text_input,
};

static void bind_text_input_manager_v3(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_text_input_manager_impl *manager = data;
    struct wl_resource *resource = wl_resource_create(client, &zwp_text_input_manager_v3_interface, 
                                                       (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &text_input_manager_v3_impl, manager, NULL);
}

struct wl_text_input_manager_impl *
wl_text_input_create(struct wl_display *display)
{
    struct wl_text_input_manager_impl *manager = calloc(1, sizeof(struct wl_text_input_manager_impl));
    if (!manager) return NULL;
    
    manager->global = wl_global_create(display, &zwp_text_input_manager_v3_interface, 1, manager, bind_text_input_manager_v3);
    if (!manager->global) {
        free(manager);
        return NULL;
    }
    return manager;
}

// ============================================================================
// Text Input v1 Implementation (for weston-editor compatibility)
// ============================================================================

static void text_input_v1_activate(struct wl_client *client, struct wl_resource *resource,
                                    struct wl_resource *seat, struct wl_resource *surface) {
    (void)client; (void)resource; (void)seat; (void)surface;
}

static void text_input_v1_deactivate(struct wl_client *client, struct wl_resource *resource,
                                      struct wl_resource *seat) {
    (void)client; (void)resource; (void)seat;
}

static void text_input_v1_show_input_panel(struct wl_client *client, struct wl_resource *resource) {
    (void)client; (void)resource;
}

static void text_input_v1_hide_input_panel(struct wl_client *client, struct wl_resource *resource) {
    (void)client; (void)resource;
}

static void text_input_v1_reset(struct wl_client *client, struct wl_resource *resource) {
    (void)client; (void)resource;
}

static void text_input_v1_set_surrounding_text(struct wl_client *client, struct wl_resource *resource,
                                                const char *text, uint32_t cursor, uint32_t anchor) {
    (void)client; (void)resource; (void)text; (void)cursor; (void)anchor;
}

static void text_input_v1_set_content_type(struct wl_client *client, struct wl_resource *resource,
                                            uint32_t hint, uint32_t purpose) {
    (void)client; (void)resource; (void)hint; (void)purpose;
}

static void text_input_v1_set_cursor_rectangle(struct wl_client *client, struct wl_resource *resource,
                                                int32_t x, int32_t y, int32_t width, int32_t height) {
    (void)client; (void)resource; (void)x; (void)y; (void)width; (void)height;
}

static void text_input_v1_set_preferred_language(struct wl_client *client, struct wl_resource *resource,
                                                  const char *language) {
    (void)client; (void)resource; (void)language;
}

static void text_input_v1_commit_state(struct wl_client *client, struct wl_resource *resource,
                                        uint32_t serial) {
    (void)client; (void)resource; (void)serial;
}

static void text_input_v1_invoke_action(struct wl_client *client, struct wl_resource *resource,
                                         uint32_t button, uint32_t index) {
    (void)client; (void)resource; (void)button; (void)index;
}

static const struct zwp_text_input_v1_interface text_input_v1_impl = {
    .activate = text_input_v1_activate,
    .deactivate = text_input_v1_deactivate,
    .show_input_panel = text_input_v1_show_input_panel,
    .hide_input_panel = text_input_v1_hide_input_panel,
    .reset = text_input_v1_reset,
    .set_surrounding_text = text_input_v1_set_surrounding_text,
    .set_content_type = text_input_v1_set_content_type,
    .set_cursor_rectangle = text_input_v1_set_cursor_rectangle,
    .set_preferred_language = text_input_v1_set_preferred_language,
    .commit_state = text_input_v1_commit_state,
    .invoke_action = text_input_v1_invoke_action,
};

static void text_input_manager_v1_create_text_input(struct wl_client *client, struct wl_resource *resource,
                                                     uint32_t id) {
    struct wl_resource *text_input = wl_resource_create(client, &zwp_text_input_v1_interface,
                                                         wl_resource_get_version(resource), id);
    if (!text_input) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(text_input, &text_input_v1_impl, NULL, NULL);
}

static const struct zwp_text_input_manager_v1_interface text_input_manager_v1_impl = {
    .create_text_input = text_input_manager_v1_create_text_input,
};

static void bind_text_input_manager_v1(struct wl_client *client, void *data, uint32_t version, uint32_t id) {
    struct wl_text_input_manager_v1_impl *manager = data;
    struct wl_resource *resource = wl_resource_create(client, &zwp_text_input_manager_v1_interface,
                                                       (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }
    wl_resource_set_implementation(resource, &text_input_manager_v1_impl, manager, NULL);
}

struct wl_text_input_manager_v1_impl *
wl_text_input_v1_create(struct wl_display *display)
{
    struct wl_text_input_manager_v1_impl *manager = calloc(1, sizeof(struct wl_text_input_manager_v1_impl));
    if (!manager) return NULL;
    
    manager->global = wl_global_create(display, &zwp_text_input_manager_v1_interface, 1, manager, bind_text_input_manager_v1);
    if (!manager->global) {
        free(manager);
        return NULL;
    }
    return manager;
}

struct zwp_primary_selection_device_manager_v1_impl *
zwp_primary_selection_device_manager_v1_create(struct wl_display *display)
{
    (void)display;
    return NULL;
}

// These are now implemented in their respective files or are truly optional
struct ext_idle_notifier_v1_impl *ext_idle_notifier_v1_create(struct wl_display *display) { (void)display; return NULL; }

// GTK/KDE/Qt protocols - optional, not critical for basic functionality
struct gtk_shell1_impl *gtk_shell1_create(struct wl_display *display) { (void)display; return NULL; }
struct org_kde_plasma_shell_impl *org_kde_plasma_shell_create(struct wl_display *display) { (void)display; return NULL; }
struct qt_surface_extension_impl *qt_surface_extension_create(struct wl_display *display) { (void)display; return NULL; }
struct qt_windowmanager_impl *qt_windowmanager_create(struct wl_display *display) { (void)display; return NULL; }
