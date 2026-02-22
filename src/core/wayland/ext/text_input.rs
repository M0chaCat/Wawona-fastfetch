//! WP Text Input protocol implementation.
//!
//! This protocol provides text input support for IME (Input Method Editor).
//! The compositor tracks per-text-input state (surrounding text, content type,
//! cursor rectangle, enabled/disabled) and sends enter/leave events on focus change.
//! Commit strings and preedit are forwarded from the platform IME integration.

use std::collections::HashMap;
use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::wp::text_input::zv3::server::{
    zwp_text_input_manager_v3::{self, ZwpTextInputManagerV3},
    zwp_text_input_v3::{self, ZwpTextInputV3},
};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// Content type hint for the text input field
#[derive(Debug, Clone, Default)]
pub struct ContentType {
    pub hint: u32,
    pub purpose: u32,
}

/// Per-text-input state tracked by the compositor
#[derive(Debug, Clone)]
pub struct TextInputInstance {
    pub resource: ZwpTextInputV3,
    pub seat_id: u32,
    pub enabled: bool,
    pub surrounding_text: String,
    pub surrounding_cursor: i32,
    pub surrounding_anchor: i32,
    pub content_type: ContentType,
    pub cursor_rect: (i32, i32, i32, i32),
    pub serial: u32,
}

/// Compositor-wide text input state
#[derive(Debug, Default)]
pub struct TextInputState {
    /// All active text input instances, keyed by resource protocol ID
    pub instances: HashMap<u32, TextInputInstance>,
    /// Currently focused text input (receives enter/leave)
    pub focused: Option<u32>,
}

impl TextInputState {
    /// Send enter event to all text inputs associated with the focused surface
    pub fn enter(&mut self, surface: &wayland_server::protocol::wl_surface::WlSurface) {
        for (_id, instance) in &self.instances {
            if instance.resource.is_alive() {
                instance.resource.enter(surface);
            }
        }
    }

    /// Send leave event to all text inputs associated with the focused surface
    pub fn leave(&mut self, surface: &wayland_server::protocol::wl_surface::WlSurface) {
        for (_id, instance) in &self.instances {
            if instance.resource.is_alive() {
                instance.resource.leave(surface);
            }
        }
    }

    /// Forward a commit string from platform IME to the enabled text input.
    ///
    /// Per the zwp_text_input_v3 spec, the `done` serial must reflect the
    /// compositor's own event sequence.  We increment on each `done` we send
    /// so clients can detect missed events.
    pub fn commit_string(&mut self, text: &str) {
        for (_id, instance) in &mut self.instances {
            if instance.enabled && instance.resource.is_alive() {
                instance.serial = instance.serial.wrapping_add(1);
                instance.resource.commit_string(Some(text.to_string()));
                instance.resource.done(instance.serial);
            }
        }
    }

    /// Forward preedit from platform IME
    pub fn preedit_string(&mut self, text: &str, cursor_begin: i32, cursor_end: i32) {
        for (_id, instance) in &mut self.instances {
            if instance.enabled && instance.resource.is_alive() {
                instance.serial = instance.serial.wrapping_add(1);
                instance.resource.preedit_string(Some(text.to_string()), cursor_begin, cursor_end);
                instance.resource.done(instance.serial);
            }
        }
    }

    /// Forward delete_surrounding_text from platform IME
    pub fn delete_surrounding_text(&mut self, before_length: u32, after_length: u32) {
        for (_id, instance) in &mut self.instances {
            if instance.enabled && instance.resource.is_alive() {
                instance.serial = instance.serial.wrapping_add(1);
                instance.resource.delete_surrounding_text(before_length, after_length);
                instance.resource.done(instance.serial);
            }
        }
    }
}

// ============================================================================
// zwp_text_input_manager_v3
// ============================================================================

impl GlobalDispatch<ZwpTextInputManagerV3, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZwpTextInputManagerV3>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zwp_text_input_manager_v3");
    }
}

impl Dispatch<ZwpTextInputManagerV3, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZwpTextInputManagerV3,
        request: zwp_text_input_manager_v3::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zwp_text_input_manager_v3::Request::GetTextInput { id, seat } => {
                let seat_id = seat.id().protocol_id();
                let text_input = data_init.init(id, seat_id);
                let ti_id = text_input.id().protocol_id();

                state.ext.text_input.instances.insert(ti_id, TextInputInstance {
                    resource: text_input,
                    seat_id,
                    enabled: false,
                    surrounding_text: String::new(),
                    surrounding_cursor: 0,
                    surrounding_anchor: 0,
                    content_type: ContentType::default(),
                    cursor_rect: (0, 0, 0, 0),
                    serial: 0,
                });

                tracing::debug!("Created text input {} for seat {}", ti_id, seat_id);
            }
            zwp_text_input_manager_v3::Request::Destroy => {
                tracing::debug!("zwp_text_input_manager_v3 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zwp_text_input_v3 — user data is seat_id: u32
// ============================================================================

impl Dispatch<ZwpTextInputV3, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZwpTextInputV3,
        request: zwp_text_input_v3::Request,
        _seat_id: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let ti_id = resource.id().protocol_id();
        match request {
            zwp_text_input_v3::Request::Enable => {
                if let Some(instance) = state.ext.text_input.instances.get_mut(&ti_id) {
                    instance.enabled = true;
                    tracing::debug!("Text input {} enabled", ti_id);
                }
                // Notify input method engine (desktop only).
                #[cfg(feature = "desktop-protocols")]
                {
                    state.ext.input_method.activate();
                }
            }
            zwp_text_input_v3::Request::Disable => {
                if let Some(instance) = state.ext.text_input.instances.get_mut(&ti_id) {
                    instance.enabled = false;
                    instance.surrounding_text.clear();
                    tracing::debug!("Text input {} disabled", ti_id);
                }
                // Notify input method engine (desktop only).
                #[cfg(feature = "desktop-protocols")]
                {
                    state.ext.input_method.deactivate();
                }
            }
            zwp_text_input_v3::Request::SetSurroundingText { text, cursor, anchor } => {
                if let Some(instance) = state.ext.text_input.instances.get_mut(&ti_id) {
                    instance.surrounding_text = text;
                    instance.surrounding_cursor = cursor;
                    instance.surrounding_anchor = anchor;
                }
            }
            zwp_text_input_v3::Request::SetTextChangeCause { cause: _ } => {
                // Stored implicitly — the change cause applies to the next commit
            }
            zwp_text_input_v3::Request::SetContentType { hint, purpose } => {
                if let Some(instance) = state.ext.text_input.instances.get_mut(&ti_id) {
                    instance.content_type.hint = hint.into();
                    instance.content_type.purpose = purpose.into();
                }
            }
            zwp_text_input_v3::Request::SetCursorRectangle { x, y, width, height } => {
                if let Some(instance) = state.ext.text_input.instances.get_mut(&ti_id) {
                    instance.cursor_rect = (x, y, width, height);
                }
            }
            zwp_text_input_v3::Request::Commit => {
                // Extract the values we need before releasing the borrow
                // on `instances`, so we can also borrow `input_method`.
                let _im_data = state.ext.text_input.instances.get_mut(&ti_id).map(|instance| {
                    instance.serial = instance.serial.wrapping_add(1);
                    tracing::debug!("Text input {} commit (serial {})", ti_id, instance.serial);
                    (
                        instance.surrounding_text.clone(),
                        instance.surrounding_cursor as u32,
                        instance.surrounding_anchor as u32,
                        instance.content_type.hint,
                        instance.content_type.purpose,
                    )
                });

                // Forward double-buffered state to the input method engine.
                #[cfg(feature = "desktop-protocols")]
                if let Some((text, cursor, anchor, hint, purpose)) = _im_data {
                    let im = &mut state.ext.input_method;
                    if im.active {
                        im.surrounding_text(&text, cursor, anchor);
                        im.content_type(hint, purpose);
                        im.done();
                    }
                }
            }
            zwp_text_input_v3::Request::Destroy => {
                state.ext.text_input.instances.remove(&ti_id);
                tracing::debug!("Text input {} destroyed", ti_id);
            }
            _ => {}
        }
    }
}

/// Register zwp_text_input_manager_v3 global
pub fn register_text_input_manager(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZwpTextInputManagerV3, ()>(1, ())
}
