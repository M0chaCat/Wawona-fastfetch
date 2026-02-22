//! wl_seat protocol implementation.
//!
//! The seat is the primary abstraction for input devices. It represents
//! a collection of input devices (keyboard, pointer, touch) that are
//! logically grouped together.

use wayland_server::{
    protocol::{wl_seat, wl_pointer, wl_keyboard, wl_touch},
    Dispatch, Resource, DisplayHandle, GlobalDispatch,
};

use crate::core::state::CompositorState;

/// Seat global data
pub struct SeatGlobal {
    pub name: String,
}

impl Default for SeatGlobal {
    fn default() -> Self {
        Self {
            name: "seat0".to_string(),
        }
    }
}

// ============================================================================
// wl_seat
// ============================================================================

impl GlobalDispatch<wl_seat::WlSeat, SeatGlobal> for CompositorState {
    fn bind(
        state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<wl_seat::WlSeat>,
        global_data: &SeatGlobal,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let seat = data_init.init(resource, ());
        crate::wlog!(crate::util::logging::SEAT, "DEBUG: Seat Bind Called for client {:?}", _client.id());
        state.seat_resources.insert(seat.id().protocol_id(), seat.clone());
        
        // Send capabilities
        seat.capabilities(
            wl_seat::Capability::Pointer | 
            wl_seat::Capability::Keyboard
        );
        
        // Send name (version 2+)
        if seat.version() >= 2 {
            seat.name(global_data.name.clone());
        }
        
        tracing::debug!("Bound wl_seat with pointer+keyboard capabilities");
    }
}

impl Dispatch<wl_seat::WlSeat, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &wl_seat::WlSeat,
        request: wl_seat::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_seat::Request::GetPointer { id } => {
                let pointer = data_init.init(id, ());
                tracing::debug!("Created wl_pointer");
                
                state.seat.add_pointer(pointer);
            }
            wl_seat::Request::GetKeyboard { id } => {
                let keyboard = data_init.init(id, ());
                crate::wlog!(crate::util::logging::SEAT, "Created wl_keyboard resource");
                
                let serial = state.next_serial();
                state.seat.add_keyboard(keyboard, serial);
                crate::wlog!(crate::util::logging::SEAT, "Added keyboard to seat (total: {})", 
                    state.seat.keyboard.resources.len());
            }
            wl_seat::Request::GetTouch { id } => {
                let touch = data_init.init(id, ());
                tracing::debug!("Created wl_touch");
                state.seat.add_touch(touch);
            }
            wl_seat::Request::Release => {
                tracing::debug!("wl_seat released");
            }
            _ => {}
        }
    }
}


// ============================================================================
// Helpers
// ============================================================================


// ============================================================================
// wl_keyboard
// ============================================================================

impl Dispatch<wl_keyboard::WlKeyboard, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wl_keyboard::WlKeyboard,
        request: wl_keyboard::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_keyboard::Request::Release => {
                state.seat.remove_keyboard(resource);
            }
            _ => {}
        }
    }
}

// ============================================================================
// wl_touch
// ============================================================================

impl Dispatch<wl_touch::WlTouch, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wl_touch::WlTouch,
        request: wl_touch::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_touch::Request::Release => {
                state.seat.remove_touch(resource);
            }
            _ => {}
        }
    }
}

// ============================================================================
// wl_pointer
// ============================================================================

impl Dispatch<wl_pointer::WlPointer, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wl_pointer::WlPointer,
        request: wl_pointer::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
             wl_pointer::Request::SetCursor { serial: _, surface, hotspot_x, hotspot_y } => {
                let surface_id = surface.map(|s| s.id().protocol_id());
                state.seat.pointer.cursor_surface = surface_id;
                state.seat.pointer.cursor_hotspot_x = hotspot_x as f64;
                state.seat.pointer.cursor_hotspot_y = hotspot_y as f64;
                
                if let Some(sid) = surface_id {
                    tracing::debug!("Seat cursor set to surface {} at ({}, {})", sid, hotspot_x, hotspot_y);
                } else {
                    tracing::debug!("Seat cursor hidden");
                }
             }
             wl_pointer::Request::Release => {
                state.seat.pointer.resources.retain(|p| p.id() != resource.id());
             }
             _ => {}
        }
    }
}

