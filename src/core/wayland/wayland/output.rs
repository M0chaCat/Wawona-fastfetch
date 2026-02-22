//! wl_output protocol implementation.
//!
//! Outputs represent physical displays connected to the system.
//! Clients use this to understand display geometry, mode, scale, etc.

use wayland_server::{
    protocol::wl_output::{self, WlOutput, Subpixel, Transform},
    Dispatch, DisplayHandle, GlobalDispatch, Resource,
};

use crate::core::state::{CompositorState, OutputState};

/// Output global data - references an output by ID
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OutputGlobal {
    pub output_id: u32,
}

impl OutputGlobal {
    pub fn new(output_id: u32) -> Self {
        Self { output_id }
    }
}

// ============================================================================
// wl_output GlobalDispatch
// ============================================================================

impl GlobalDispatch<WlOutput, OutputGlobal> for CompositorState {
    fn bind(
        state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<WlOutput>,
        global_data: &OutputGlobal,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let output = data_init.init(resource, ());
        let object_id = output.id();
        let client = output.client();
        let client_id = client.as_ref().map(|c| c.id());
        
        state.output_resources.insert(object_id.clone(), output.clone());
        state.output_id_by_resource.insert(object_id, global_data.output_id);
        crate::wlog!(crate::util::logging::COMPOSITOR, "Bound wl_output version {} for client {:?}", output.version(), client_id);

        // Find the output state using the global data ID
        if let Some(output_state) = state.outputs.iter().find(|o| o.id == global_data.output_id) {
            send_output_info(&output, output_state);
        } else {
            // Fallback to primary output or logging error
            crate::wlog!(crate::util::logging::COMPOSITOR, "ERROR: OutputGlobal ID {} not found in state!", global_data.output_id);
            if let Some(primary) = state.outputs.first() {
                send_output_info(&output, primary);
            }
        }
    }
}

impl Dispatch<WlOutput, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &WlOutput,
        request: wl_output::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_output::Request::Release => {
                state.output_resources.remove(&resource.id());
                state.output_id_by_resource.remove(&resource.id());
                crate::wlog!(crate::util::logging::COMPOSITOR, "wl_output released for client {:?}", resource.client().map(|c| c.id()));
            }
            _ => {}
        }
    }
}

// ============================================================================
// Helpers
// ============================================================================

/// Send all output information to a newly bound output resource.
fn send_output_info(output: &WlOutput, state: &OutputState) {
    crate::wlog!(crate::util::logging::COMPOSITOR, "Sending wl_output.geometry: {}x{} @ ({},{})", state.physical_width, state.physical_height, state.x, state.y);
    // Send geometry
    output.geometry(
        state.x,
        state.y,
        state.physical_width as i32,
        state.physical_height as i32,
        Subpixel::Unknown,
        state.name.clone(),
        state.name.clone(), // model
        Transform::Normal,
    );
    
    crate::wlog!(crate::util::logging::COMPOSITOR, "Sending wl_output.mode: {}x{} (Current | Preferred)", state.width, state.height);
    // Send modes separately for maximum compatibility
    output.mode(
        wl_output::Mode::Preferred,
        state.width as i32,
        state.height as i32,
        state.refresh as i32,
    );
    output.mode(
        wl_output::Mode::Current,
        state.width as i32,
        state.height as i32,
        state.refresh as i32,
    );
    
    // Send scale (version 2+)
    if output.version() >= 2 {
        output.scale(state.scale as i32);
    }
    
    // Send name (version 4+)
    if output.version() >= 4 {
        output.name(state.name.clone());
        output.description(format!("{} ({}x{})", state.name, state.width, state.height));
    }
    
    // Send done event to signal end of initial configuration
    if output.version() >= 2 {
        output.done();
    }
    
    crate::wlog!(crate::util::logging::COMPOSITOR,
        "Sent output info: {} {}x{} ({}x{}mm) @ {}mHz, scale {}, version {}",
        state.name, state.width, state.height, state.physical_width, state.physical_height, state.refresh, state.scale, output.version()
    );
}

/// Notify all bound output resources of a configuration change.
///
/// Call this when output configuration changes (resolution, scale, position, etc.)
/// to send updated geometry, mode, scale, and done events to all clients.
pub fn notify_output_change(state: &CompositorState, output_id: u32) {
    let output_state = match state.outputs.iter().find(|o| o.id == output_id) {
        Some(o) => o,
        None => {
            tracing::warn!("notify_output_change: output {} not found", output_id);
            return;
        }
    };

    let mut notified = 0;
    for (_obj_id, output_res) in &state.output_resources {
        if !output_res.is_alive() {
            continue;
        }
        send_output_info(output_res, output_state);
        notified += 1;
    }

    tracing::debug!(
        "Notified {} bound wl_output resources of output {} change ({}x{})",
        notified, output_id, output_state.width, output_state.height
    );

    // Also notify xdg_output resources
    crate::core::wayland::xdg::xdg_output::notify_xdg_output_change(state);
}
