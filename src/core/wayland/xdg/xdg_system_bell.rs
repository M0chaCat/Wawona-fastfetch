//! XDG System Bell protocol implementation.
//!
//! Allows clients to request system bell/notification sounds.

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::xdg::system_bell::v1::server::{
    xdg_system_bell_v1::{self, XdgSystemBellV1},
};

use crate::core::state::CompositorState;

impl GlobalDispatch<XdgSystemBellV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XdgSystemBellV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound xdg_system_bell_v1");
    }
}

impl Dispatch<XdgSystemBellV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &XdgSystemBellV1,
        request: xdg_system_bell_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xdg_system_bell_v1::Request::Ring { surface } => {
                let surface_id = surface.as_ref().map(|s| s.id().protocol_id());
                tracing::debug!("System bell requested (surface={:?})", surface_id);
                state.pending_compositor_events.push(
                    crate::core::compositor::CompositorEvent::SystemBell {
                        surface_id: surface_id.unwrap_or(0),
                    }
                );
            }
            xdg_system_bell_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

pub fn register_xdg_system_bell(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, XdgSystemBellV1, ()>(1, ())
}
