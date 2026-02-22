//! XDG Output protocol implementation.
//!
//! This protocol provides additional output information beyond wl_output,
//! including logical position and size (accounting for scaling and transforms).


use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::xdg::xdg_output::zv1::server::{
    zxdg_output_manager_v1::{self, ZxdgOutputManagerV1},
    zxdg_output_v1::{self, ZxdgOutputV1},
};


use crate::core::state::CompositorState;
use std::collections::HashMap;

#[derive(Debug, Clone)]
pub struct XdgOutputData {
    pub output_id: u32,
}

impl XdgOutputData {
    pub fn new(output_id: u32) -> Self {
        Self { output_id }
    }
}

/// Tracks all bound xdg_output resources for update notifications.
#[derive(Debug, Default)]
pub struct XdgOutputState {
    pub outputs: HashMap<u32, XdgOutputData>,
    /// All active xdg_output resources, keyed by xdg_output protocol ID.
    /// Used to send updates when output configuration changes.
    pub resources: HashMap<u32, ZxdgOutputV1>,
}


// ============================================================================
// zxdg_output_manager_v1
// ============================================================================

impl GlobalDispatch<ZxdgOutputManagerV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<ZxdgOutputManagerV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound zxdg_output_manager_v1");
    }
}

impl Dispatch<ZxdgOutputManagerV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &ZxdgOutputManagerV1,
        request: zxdg_output_manager_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zxdg_output_manager_v1::Request::GetXdgOutput { id, output } => {
                let output_id = output.id().protocol_id();
                let xdg_output_data = XdgOutputData::new(output_id);
                let xdg_output = data_init.init(id, ());

                let xdg_output_id = xdg_output.id().protocol_id();
                state.xdg.output.outputs.insert(xdg_output_id, xdg_output_data);
                state.xdg.output.resources.insert(xdg_output_id, xdg_output.clone());

                
                // Send output information
                let output_state = state.primary_output();
                
                // Logical position (in compositor coordinates)
                xdg_output.logical_position(output_state.x, output_state.y);
                
                // Logical size (may differ from physical due to scaling)
                let logical_width = (output_state.width as f32 / output_state.scale) as i32;
                let logical_height = (output_state.height as f32 / output_state.scale) as i32;
                xdg_output.logical_size(logical_width, logical_height);
                
                // Name and description (v2+)
                if xdg_output.version() >= 2 {
                    xdg_output.name(output_state.name.clone());
                    xdg_output.description(format!(
                        "{} ({}x{} @ {}Hz)",
                        output_state.name,
                        output_state.width,
                        output_state.height,
                        output_state.refresh / 1000
                    ));
                }
                
                // Done event (v3+)
                if xdg_output.version() >= 3 {
                    xdg_output.done();
                }
                
                tracing::debug!(
                    "Created xdg_output for output {}: logical {}x{} at ({}, {})",
                    output_id, logical_width, logical_height, output_state.x, output_state.y
                );
            }
            zxdg_output_manager_v1::Request::Destroy => {
                tracing::debug!("zxdg_output_manager_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// zxdg_output_v1
// ============================================================================

impl Dispatch<ZxdgOutputV1, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &ZxdgOutputV1,
        request: zxdg_output_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            zxdg_output_v1::Request::Destroy => {
                let id = resource.id().protocol_id();
                state.xdg.output.outputs.remove(&id);
                state.xdg.output.resources.remove(&id);
                tracing::debug!("zxdg_output_v1 destroyed");
            }

            _ => {}
        }
    }
}

/// Notify all xdg_output resources about output configuration changes.
/// Called when output geometry, mode, or scale changes.
pub fn notify_xdg_output_change(state: &CompositorState) {
    let output_state = state.primary_output();
    let logical_width = (output_state.width as f32 / output_state.scale) as i32;
    let logical_height = (output_state.height as f32 / output_state.scale) as i32;

    for (_, xdg_output) in &state.xdg.output.resources {
        if !xdg_output.is_alive() {
            continue;
        }
        xdg_output.logical_position(output_state.x, output_state.y);
        xdg_output.logical_size(logical_width, logical_height);

        if xdg_output.version() >= 3 {
            xdg_output.done();
        }
    }

    if !state.xdg.output.resources.is_empty() {
        tracing::debug!(
            "Notified {} xdg_output resources of change: logical {}x{} at ({}, {})",
            state.xdg.output.resources.len(),
            logical_width, logical_height, output_state.x, output_state.y
        );
    }
}

/// Register zxdg_output_manager_v1 global
pub fn register_xdg_output_manager(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, ZxdgOutputManagerV1, ()>(3, ())
}
