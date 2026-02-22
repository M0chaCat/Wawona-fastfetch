use wayland_server::{
    Dispatch, DisplayHandle, GlobalDispatch, Resource,
};

use crate::core::state::CompositorState;
use crate::core::wayland::protocol::wlroots::zwp_virtual_keyboard_v1::{
    zwp_virtual_keyboard_manager_v1,
    zwp_virtual_keyboard_v1,
};

pub struct VirtualKeyboardManagerData;

/// State for a virtual keyboard device
#[derive(Debug, Clone)]
pub struct VirtualKeyboardState {
    /// Associated seat name
    pub seat_name: Option<String>,
}

impl VirtualKeyboardState {
    pub fn new(seat_name: Option<String>) -> Self {
        Self { seat_name }
    }
}


impl GlobalDispatch<zwp_virtual_keyboard_manager_v1::ZwpVirtualKeyboardManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<zwp_virtual_keyboard_manager_v1::ZwpVirtualKeyboardManagerV1>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
    }
}

impl Dispatch<zwp_virtual_keyboard_manager_v1::ZwpVirtualKeyboardManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &zwp_virtual_keyboard_manager_v1::ZwpVirtualKeyboardManagerV1,
        request: zwp_virtual_keyboard_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwp_virtual_keyboard_manager_v1::Request::CreateVirtualKeyboard { seat, id } => {
                let seat_name = seat.data::<String>().cloned().unwrap_or_default();
                let keyboard_res = data_init.init(id, ());
                let resource_id = keyboard_res.id().protocol_id();
                
                let keyboard_state = VirtualKeyboardState::new(Some(seat_name));
                state.wlr.virtual_keyboards.insert(resource_id, keyboard_state);
            }
            _ => {}
        }
    }
}

impl Dispatch<zwp_virtual_keyboard_v1::ZwpVirtualKeyboardV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &zwp_virtual_keyboard_v1::ZwpVirtualKeyboardV1,
        request: zwp_virtual_keyboard_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            zwp_virtual_keyboard_v1::Request::Keymap { format, fd: _, size } => {
                tracing::debug!("Virtual keyboard keymap: format={:?}, size={}", format, size);
                // In a full implementation, we would parse this keymap with xkbcommon
                // and use it to translate keycodes from this virtual device.
            }
            zwp_virtual_keyboard_v1::Request::Key { time, key, state: key_state } => {
                tracing::debug!("Virtual keyboard key: {} is {} at {}", key, key_state, time);
                let key_state_val = match key_state {
                    1 => wayland_server::protocol::wl_keyboard::KeyState::Pressed,
                    _ => wayland_server::protocol::wl_keyboard::KeyState::Released,
                };
                state.inject_key(key, key_state_val, time);
            }
            zwp_virtual_keyboard_v1::Request::Modifiers { mods_depressed, mods_latched, mods_locked, group } => {
                tracing::debug!(
                    "Virtual keyboard modifiers: depressed={}, latched={}, locked={}, group={}",
                    mods_depressed, mods_latched, mods_locked, group
                );
                state.inject_modifiers(mods_depressed, mods_latched, mods_locked, group);
            }
            zwp_virtual_keyboard_v1::Request::Destroy => {
                let resource_id = resource.id().protocol_id();
                state.wlr.virtual_keyboards.remove(&resource_id);
            }
            _ => {}
        }
    }
}

/// Register zwp_virtual_keyboard_manager_v1 global
pub fn register_virtual_keyboard(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, zwp_virtual_keyboard_manager_v1::ZwpVirtualKeyboardManagerV1, ()>(1, ())
}
