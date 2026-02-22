//! XDG Toplevel Tag protocol implementation.
//!
//! Allows tagging toplevels for identification across restarts.

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::xdg::toplevel_tag::v1::server::{
    xdg_toplevel_tag_manager_v1::{self, XdgToplevelTagManagerV1},
};

use crate::core::state::CompositorState;

impl GlobalDispatch<XdgToplevelTagManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XdgToplevelTagManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound xdg_toplevel_tag_manager_v1");
    }
}

impl Dispatch<XdgToplevelTagManagerV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XdgToplevelTagManagerV1,
        request: xdg_toplevel_tag_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xdg_toplevel_tag_manager_v1::Request::SetToplevelTag { toplevel, tag } => {
                let toplevel_id = toplevel.id().protocol_id();
                tracing::debug!("Set tag '{}' for toplevel {}", tag, toplevel_id);
            }
            xdg_toplevel_tag_manager_v1::Request::SetToplevelDescription { toplevel, description } => {
                let toplevel_id = toplevel.id().protocol_id();
                tracing::debug!("Set description '{}' for toplevel {}", description, toplevel_id);
            }
            xdg_toplevel_tag_manager_v1::Request::Destroy => {}
            _ => {}
        }
    }
}

pub fn register_xdg_toplevel_tag(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, XdgToplevelTagManagerV1, ()>(1, ())
}
