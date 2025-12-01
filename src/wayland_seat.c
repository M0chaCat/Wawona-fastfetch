#include "wayland_seat.h"
#include <wayland-server-protocol.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

// Pointer implementation
static void
pointer_set_cursor(struct wl_client *client, struct wl_resource *resource,
                   uint32_t serial, struct wl_resource *surface,
                   int32_t hotspot_x, int32_t hotspot_y)
{
    (void)client; (void)resource; (void)serial; (void)surface; (void)hotspot_x; (void)hotspot_y;
}

static void
pointer_release(struct wl_client *client, struct wl_resource *resource)
{
    (void)client;
    wl_resource_destroy(resource);
}

static const struct wl_pointer_interface pointer_implementation = {
    .set_cursor = pointer_set_cursor,
    .release = pointer_release,
};

// Keyboard implementation
static void
keyboard_release(struct wl_client *client, struct wl_resource *resource)
{
    (void)client;
    wl_resource_destroy(resource);
}

static const struct wl_keyboard_interface keyboard_implementation = {
    .release = keyboard_release,
};

// Touch implementation
static void
touch_release(struct wl_client *client, struct wl_resource *resource)
{
    (void)client;
    wl_resource_destroy(resource);
}

static const struct wl_touch_interface touch_implementation = {
    .release = touch_release,
};

static void
seat_get_pointer(struct wl_client *client, struct wl_resource *resource, uint32_t id)
{
    struct wl_seat_impl *seat = wl_resource_get_user_data(resource);
    struct wl_resource *pointer = wl_resource_create(client, &wl_pointer_interface, wl_resource_get_version(resource), id);
    if (!pointer) {
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(pointer, &pointer_implementation, seat, NULL);
    seat->pointer_resource = pointer; // Simple tracking (last one wins)
}

static void
seat_get_keyboard(struct wl_client *client, struct wl_resource *resource, uint32_t id)
{
    struct wl_seat_impl *seat = wl_resource_get_user_data(resource);
    struct wl_resource *keyboard = wl_resource_create(client, &wl_keyboard_interface, wl_resource_get_version(resource), id);
    if (!keyboard) {
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(keyboard, &keyboard_implementation, seat, NULL);
    seat->keyboard_resource = keyboard;
    
    // Send keymap if we have one (todo)
}

static void
seat_get_touch(struct wl_client *client, struct wl_resource *resource, uint32_t id)
{
    struct wl_seat_impl *seat = wl_resource_get_user_data(resource);
    struct wl_resource *touch = wl_resource_create(client, &wl_touch_interface, wl_resource_get_version(resource), id);
    if (!touch) {
        wl_client_post_no_memory(client);
        return;
    }
    
    wl_resource_set_implementation(touch, &touch_implementation, seat, NULL);
    seat->touch_resource = touch;
}

static void
seat_release(struct wl_client *client, struct wl_resource *resource)
{
    wl_resource_destroy(resource);
}

static const struct wl_seat_interface seat_interface = {
    .get_pointer = seat_get_pointer,
    .get_keyboard = seat_get_keyboard,
    .get_touch = seat_get_touch,
    .release = seat_release,
};

static void
bind_seat(struct wl_client *client, void *data, uint32_t version, uint32_t id)
{
    struct wl_seat_impl *seat = data;
    struct wl_resource *resource;

    resource = wl_resource_create(client, &wl_seat_interface, (int)version, id);
    if (!resource) {
        wl_client_post_no_memory(client);
        return;
    }

    wl_resource_set_implementation(resource, &seat_interface, seat, NULL);
    
    if (version >= WL_SEAT_CAPABILITIES_SINCE_VERSION) {
        wl_seat_send_capabilities(resource, seat->capabilities);
    }
    
    if (version >= WL_SEAT_NAME_SINCE_VERSION) {
        wl_seat_send_name(resource, "seat0");
    }
    
    seat->seat_resource = resource; // Track last bound resource (should be list)
}

struct wl_seat_impl *
wl_seat_create(struct wl_display *display)
{
    struct wl_seat_impl *seat = calloc(1, sizeof(struct wl_seat_impl));
    if (!seat) return NULL;

    seat->display = display;
    seat->capabilities = WL_SEAT_CAPABILITY_POINTER | WL_SEAT_CAPABILITY_KEYBOARD | WL_SEAT_CAPABILITY_TOUCH;
    seat->serial = 1;
    
    seat->global = wl_global_create(display, &wl_seat_interface, 7, seat, bind_seat);
    if (!seat->global) {
        free(seat);
        return NULL;
    }

    return seat;
}

void
wl_seat_destroy(struct wl_seat_impl *seat)
{
    if (!seat) return;
    if (seat->global) wl_global_destroy(seat->global);
    free(seat);
}

void
wl_seat_set_capabilities(struct wl_seat_impl *seat, uint32_t capabilities)
{
    if (!seat) return;
    seat->capabilities = capabilities;
    if (seat->seat_resource) {
        wl_seat_send_capabilities(seat->seat_resource, capabilities);
    }
}

uint32_t
wl_seat_get_serial(struct wl_seat_impl *seat)
{
    return seat ? seat->serial++ : 0;
}

void
wl_seat_set_focused_surface(struct wl_seat_impl *seat, void *surface)
{
    if (seat) seat->focused_surface = surface;
}

// Input event handlers
void wl_seat_send_pointer_enter(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial, double x, double y) {
    if (seat && seat->pointer_resource) {
        wl_pointer_send_enter(seat->pointer_resource, serial, surface, wl_fixed_from_double(x), wl_fixed_from_double(y));
    }
}
void wl_seat_send_pointer_leave(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial) {
    if (seat && seat->pointer_resource) {
        wl_pointer_send_leave(seat->pointer_resource, serial, surface);
    }
}
void wl_seat_send_pointer_motion(struct wl_seat_impl *seat, uint32_t time, double x, double y) {
    if (seat && seat->pointer_resource) {
        wl_pointer_send_motion(seat->pointer_resource, time, wl_fixed_from_double(x), wl_fixed_from_double(y));
    }
}
void wl_seat_send_pointer_button(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, uint32_t button, uint32_t state) {
    if (seat && seat->pointer_resource) {
        wl_pointer_send_button(seat->pointer_resource, serial, time, button, state);
    }
}
void wl_seat_send_pointer_frame(struct wl_seat_impl *seat) {
    if (seat && seat->pointer_resource) {
        if (wl_resource_get_version(seat->pointer_resource) >= WL_POINTER_FRAME_SINCE_VERSION) {
            wl_pointer_send_frame(seat->pointer_resource);
        }
    }
}
void wl_seat_send_keyboard_enter(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial, struct wl_array *keys) {
    if (seat && seat->keyboard_resource) {
        wl_keyboard_send_enter(seat->keyboard_resource, serial, surface, keys);
    }
}
void wl_seat_send_keyboard_leave(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial) {
    if (seat && seat->keyboard_resource) {
        wl_keyboard_send_leave(seat->keyboard_resource, serial, surface);
    }
}
void wl_seat_send_keyboard_key(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, uint32_t key, uint32_t state) {
    if (seat && seat->keyboard_resource) {
        wl_keyboard_send_key(seat->keyboard_resource, serial, time, key, state);
    }
}
void wl_seat_send_keyboard_modifiers(struct wl_seat_impl *seat, uint32_t serial) {
    if (seat && seat->keyboard_resource) {
        wl_keyboard_send_modifiers(seat->keyboard_resource, serial, 
                                   seat->mods_depressed, seat->mods_latched, seat->mods_locked, seat->group);
    }
}
void wl_seat_send_touch_down(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, struct wl_resource *surface, int32_t id, wl_fixed_t x, wl_fixed_t y) {
    if (seat && seat->touch_resource) {
        wl_touch_send_down(seat->touch_resource, serial, time, surface, id, x, y);
    }
}
void wl_seat_send_touch_up(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, int32_t id) {
    if (seat && seat->touch_resource) {
        wl_touch_send_up(seat->touch_resource, serial, time, id);
    }
}
void wl_seat_send_touch_motion(struct wl_seat_impl *seat, uint32_t time, int32_t id, wl_fixed_t x, wl_fixed_t y) {
    if (seat && seat->touch_resource) {
        wl_touch_send_motion(seat->touch_resource, time, id, x, y);
    }
}
void wl_seat_send_touch_frame(struct wl_seat_impl *seat) {
    if (seat && seat->touch_resource) {
        wl_touch_send_frame(seat->touch_resource);
    }
}
void wl_seat_send_touch_cancel(struct wl_seat_impl *seat) {
    if (seat && seat->touch_resource) {
        wl_touch_send_cancel(seat->touch_resource);
    }
}
