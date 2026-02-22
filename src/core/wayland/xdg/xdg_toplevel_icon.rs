//! XDG Toplevel Icon protocol implementation.
//!
//! Allows clients to set custom icons for their toplevels. Icons are
//! stored as buffer references with scale factors. SetIcon applies the
//! icon to the specified toplevel's window metadata.

use std::collections::HashMap;
use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::xdg::toplevel_icon::v1::server::{
    xdg_toplevel_icon_v1::{self, XdgToplevelIconV1},
    xdg_toplevel_icon_manager_v1::{self, XdgToplevelIconManagerV1},
};

use crate::core::state::CompositorState;

// ============================================================================
// Data Types
// ============================================================================

/// A single icon buffer at a specific scale
#[derive(Debug, Clone)]
pub struct IconBuffer {
    pub buffer_id: u32,
    pub scale: i32,
}

/// Per-icon data — collects buffers before being applied to a toplevel
#[derive(Debug, Clone, Default)]
pub struct IconData {
    pub buffers: Vec<IconBuffer>,
}

/// Compositor-wide toplevel icon state
#[derive(Debug, Default)]
pub struct ToplevelIconState {
    /// Pending icon objects (icon_id → buffers)
    pub pending_icons: HashMap<u32, IconData>,
    /// Applied icons per toplevel (toplevel_id → icon buffers)
    pub toplevel_icons: HashMap<u32, Vec<IconBuffer>>,
}

// ============================================================================
// xdg_toplevel_icon_manager_v1
// ============================================================================

impl GlobalDispatch<XdgToplevelIconManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XdgToplevelIconManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound xdg_toplevel_icon_manager_v1");
    }
}

impl Dispatch<XdgToplevelIconManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &XdgToplevelIconManagerV1,
        request: xdg_toplevel_icon_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xdg_toplevel_icon_manager_v1::Request::CreateIcon { id } => {
                let icon = data_init.init(id, ());
                let icon_id = icon.id().protocol_id();
                state.xdg.toplevel_icon.pending_icons.insert(icon_id, IconData::default());
                tracing::debug!("Created toplevel icon {}", icon_id);
            }
            xdg_toplevel_icon_manager_v1::Request::SetIcon { toplevel, icon } => {
                let toplevel_id = toplevel.id().protocol_id();
                if let Some(icon_res) = icon {
                    let icon_id = icon_res.id().protocol_id();
                    if let Some(icon_data) = state.xdg.toplevel_icon.pending_icons.get(&icon_id) {
                        state.xdg.toplevel_icon.toplevel_icons.insert(
                            toplevel_id,
                            icon_data.buffers.clone(),
                        );
                        tracing::debug!(
                            "Applied icon {} ({} buffers) to toplevel {}",
                            icon_id, icon_data.buffers.len(), toplevel_id
                        );
                    }
                } else {
                    // Null icon — remove the icon
                    state.xdg.toplevel_icon.toplevel_icons.remove(&toplevel_id);
                    tracing::debug!("Removed icon from toplevel {}", toplevel_id);
                }
            }
            xdg_toplevel_icon_manager_v1::Request::Destroy => {
                tracing::debug!("xdg_toplevel_icon_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// xdg_toplevel_icon_v1
// ============================================================================

impl Dispatch<XdgToplevelIconV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &XdgToplevelIconV1,
        request: xdg_toplevel_icon_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let icon_id = resource.id().protocol_id();
        match request {
            xdg_toplevel_icon_v1::Request::AddBuffer { buffer, scale } => {
                let buffer_id = buffer.id().protocol_id();
                if let Some(icon_data) = state.xdg.toplevel_icon.pending_icons.get_mut(&icon_id) {
                    icon_data.buffers.push(IconBuffer { buffer_id, scale });
                    tracing::debug!("Icon {} added buffer {} at scale {}", icon_id, buffer_id, scale);
                }
            }
            xdg_toplevel_icon_v1::Request::Destroy => {
                state.xdg.toplevel_icon.pending_icons.remove(&icon_id);
                tracing::debug!("Icon {} destroyed", icon_id);
            }
            _ => {}
        }
    }
}

/// Register xdg_toplevel_icon_manager_v1 global
pub fn register_xdg_toplevel_icon(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, XdgToplevelIconManagerV1, ()>(1, ())
}
