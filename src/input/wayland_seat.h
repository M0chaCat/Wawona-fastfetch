#pragma once

#include <wayland-server-core.h>
#include <wayland-server.h>
#include <xkbcommon/xkbcommon.h>

struct wl_seat_impl {
    struct wl_global *global;
    struct wl_display *display;
    
    uint32_t capabilities;
    uint32_t serial;
    
    struct wl_resource *seat_resource;
    struct wl_resource *pointer_resource;
    struct wl_resource *keyboard_resource;
    struct wl_resource *touch_resource;
    
    // Focus tracking
    void *focused_surface;
    void *pointer_focused_surface;
    
    // Button state tracking (bitmask of pressed buttons)
    // Each bit represents a button: bit 0 = button 272 (left), bit 1 = button 273 (right), etc.
    uint32_t pressed_buttons;
    
    // Modifier state tracking
    uint32_t mods_depressed;  // Currently pressed modifier keys
    uint32_t mods_latched;    // Latched modifier keys
    uint32_t mods_locked;     // Locked modifier keys (e.g., Caps Lock)
    uint32_t group;            // Keyboard group
    
    // Deferred keyboard enter event (to avoid calling variadic function from FFI callback)
    struct wl_event_source *pending_keyboard_enter_idle;
    struct wl_resource *pending_keyboard_enter_surface;
    struct wl_resource *pending_keyboard_enter_keyboard_resource;
    uint32_t pending_keyboard_enter_serial;
    struct wl_array *pending_keyboard_enter_keys; // Points to keys array (must be valid until callback runs)
    
    // Deferred modifiers event (sent after keyboard enter)
    struct wl_event_source *pending_modifiers_idle;
    bool pending_modifiers_needed;
    uint32_t pending_modifiers_serial;
    
    // Cursor surface tracking
    struct wl_resource *cursor_surface;  // Current cursor surface (if any)
    int32_t cursor_hotspot_x;
    int32_t cursor_hotspot_y;
    
    // xkbcommon for keymap handling
    struct xkb_context *xkb_context;
    struct xkb_keymap *xkb_keymap;
    struct xkb_state *xkb_state;
    int keymap_fd;
    uint32_t keymap_size;
};

struct wl_seat_impl *wl_seat_create(struct wl_display *display);
void wl_seat_destroy(struct wl_seat_impl *seat);
void wl_seat_set_capabilities(struct wl_seat_impl *seat, uint32_t capabilities);
uint32_t wl_seat_get_serial(struct wl_seat_impl *seat);
void wl_seat_set_focused_surface(struct wl_seat_impl *seat, void *surface);

// Input event handlers (to be called from NSEvent handlers)
void wl_seat_send_pointer_enter(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial, double x, double y);
void wl_seat_send_pointer_leave(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial);
void wl_seat_send_pointer_motion(struct wl_seat_impl *seat, uint32_t time, double x, double y);
void wl_seat_send_pointer_button(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, uint32_t button, uint32_t state);
void wl_seat_send_pointer_frame(struct wl_seat_impl *seat);
void wl_seat_send_keyboard_enter(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial, struct wl_array *keys);
void wl_seat_send_keyboard_leave(struct wl_seat_impl *seat, struct wl_resource *surface, uint32_t serial);
void wl_seat_send_keyboard_key(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, uint32_t key, uint32_t state);
void wl_seat_send_keyboard_modifiers(struct wl_seat_impl *seat, uint32_t serial);
void wl_seat_send_touch_down(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, struct wl_resource *surface, int32_t id, wl_fixed_t x, wl_fixed_t y);
void wl_seat_send_touch_up(struct wl_seat_impl *seat, uint32_t serial, uint32_t time, int32_t id);
void wl_seat_send_touch_motion(struct wl_seat_impl *seat, uint32_t time, int32_t id, wl_fixed_t x, wl_fixed_t y);
void wl_seat_send_touch_frame(struct wl_seat_impl *seat);
void wl_seat_send_touch_cancel(struct wl_seat_impl *seat);

