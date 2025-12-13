#pragma once
#include <wayland-server.h>

struct wl_decoration_manager_impl {
    struct wl_global *global;
};

struct wl_toplevel_icon_manager_impl {
    struct wl_global *global;
};

struct wl_activation_manager_impl {
    struct wl_global *global;
};

struct wl_fractional_scale_manager_impl {
    struct wl_global *global;
};

struct wl_cursor_shape_manager_impl {
    struct wl_global *global;
};

struct wl_text_input_manager_impl {
    struct wl_global *global;
};

struct wl_text_input_manager_v1_impl {
    struct wl_global *global;
};

struct zwp_primary_selection_device_manager_v1_impl {
    struct wl_global *global;
};

// Forward declarations - full definitions in individual header files
struct zwp_tablet_manager_v2_impl;
struct ext_idle_notifier_v1_impl;
struct zwp_keyboard_shortcuts_inhibit_manager_v1_impl;
struct gtk_shell1_impl { struct wl_global *global; };
struct org_kde_plasma_shell_impl { struct wl_global *global; };
struct qt_surface_extension_impl { struct wl_global *global; };
struct qt_windowmanager_impl { struct wl_global *global; };

void register_protocol_stubs(struct wl_display *display);

struct wl_decoration_manager_impl *wl_decoration_create(struct wl_display *display);
struct wl_toplevel_icon_manager_impl *wl_toplevel_icon_create(struct wl_display *display);
struct wl_activation_manager_impl *wl_activation_create(struct wl_display *display);
struct wl_fractional_scale_manager_impl *wl_fractional_scale_create(struct wl_display *display);
struct wl_cursor_shape_manager_impl *wl_cursor_shape_create(struct wl_display *display);
struct wl_text_input_manager_impl *wl_text_input_create(struct wl_display *display);
struct wl_text_input_manager_v1_impl *wl_text_input_v1_create(struct wl_display *display);
struct zwp_primary_selection_device_manager_v1_impl *zwp_primary_selection_device_manager_v1_create(struct wl_display *display);

struct zwp_tablet_manager_v2_impl *zwp_tablet_manager_v2_create(struct wl_display *display);
struct ext_idle_notifier_v1_impl *ext_idle_notifier_v1_create(struct wl_display *display);
struct zwp_keyboard_shortcuts_inhibit_manager_v1_impl *zwp_keyboard_shortcuts_inhibit_manager_v1_create(struct wl_display *display);
struct gtk_shell1_impl *gtk_shell1_create(struct wl_display *display);
struct org_kde_plasma_shell_impl *org_kde_plasma_shell_create(struct wl_display *display);
struct qt_surface_extension_impl *qt_surface_extension_create(struct wl_display *display);
struct qt_windowmanager_impl *qt_windowmanager_create(struct wl_display *display);
