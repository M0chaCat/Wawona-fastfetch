#include "wayland_protocol_stubs.h"
#include <stdlib.h>

void
register_protocol_stubs(struct wl_display *display)
{
    (void)display;
    // Register global interfaces for protocols we want to advertise but not fully implement yet
}

struct wl_decoration_manager_impl *
wl_decoration_create(struct wl_display *display)
{
    (void)display;
    // Stub implementation
    return NULL;
}

struct wl_toplevel_icon_manager_impl *
wl_toplevel_icon_create(struct wl_display *display)
{
    (void)display;
    // Stub implementation
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

struct wl_text_input_manager_impl *
wl_text_input_create(struct wl_display *display)
{
    (void)display;
    return NULL;
}

struct wl_text_input_manager_v1_impl *
wl_text_input_v1_create(struct wl_display *display)
{
    (void)display;
    return NULL;
}

struct zwp_primary_selection_device_manager_v1_impl *
zwp_primary_selection_device_manager_v1_create(struct wl_display *display)
{
    (void)display;
    return NULL;
}

// zwp_tablet_manager_v2_create is implemented in wayland_tablet.c
// zwp_keyboard_shortcuts_inhibit_manager_v1_create is implemented in wayland_keyboard_shortcuts.c
struct ext_idle_notifier_v1_impl *ext_idle_notifier_v1_create(struct wl_display *display) { (void)display; return NULL; }
struct gtk_shell1_impl *gtk_shell1_create(struct wl_display *display) { (void)display; return NULL; }
struct org_kde_plasma_shell_impl *org_kde_plasma_shell_create(struct wl_display *display) { (void)display; return NULL; }
struct qt_surface_extension_impl *qt_surface_extension_create(struct wl_display *display) { (void)display; return NULL; }
struct qt_windowmanager_impl *qt_windowmanager_create(struct wl_display *display) { (void)display; return NULL; }
