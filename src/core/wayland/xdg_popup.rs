//! XDG Popup protocol implementation.
//!
//! This implements the xdg_popup protocol from the xdg-shell extension.
//! It provides the interface for managing popup surfaces (menus, tooltips, etc.).


use wayland_server::{
    Dispatch, DisplayHandle, Resource,
};
use crate::core::wayland::protocol::server::xdg::shell::server::xdg_popup;

use crate::core::state::CompositorState;

impl Dispatch<xdg_popup::XdgPopup, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &xdg_popup::XdgPopup,
        request: xdg_popup::Request,
        _data: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let popup_id = resource.id().protocol_id();
        
        match request {
            xdg_popup::Request::Destroy => {
                tracing::debug!("xdg_popup destroyed: {}", popup_id);
                if let Some(data) = state.xdg_popups.remove(&popup_id) {
                    // Clean up surface_to_window mapping
                    state.surface_to_window.remove(&data.surface_id);
                    
                    // CRITICAL: Emit event for FFI layer cleanup
                    state.pending_compositor_events.push(crate::core::compositor::CompositorEvent::WindowDestroyed {
                        window_id: data.window_id,
                    });
                }
            }
            xdg_popup::Request::Grab { seat, serial } => {
                tracing::debug!("xdg_popup.grab requested for popup {}", popup_id);
                if let Some(data) = state.xdg_popups.get_mut(&popup_id) {
                    data.grabbed = true;
                    // TODO: meaningful input grabbing logic in SeatState
                    // For now we just track that this popup requested a grab
                    
                    // Verify the serial matches a valid input event
                    // This validation requires tracking serials which we loosely do
                    tracing::debug!("Popup {} grabbed seat {} with serial {}", popup_id, seat.id().protocol_id(), serial);
                }
            }
            xdg_popup::Request::Reposition { positioner, token } => {
                tracing::debug!("xdg_popup.reposition requested for popup {}", popup_id);
                
                // Get positioner data
                let positioner_data = state.xdg_positioners
                    .get(&positioner.id().protocol_id())
                    .cloned()
                    .unwrap_or_default();
                    
                let surface_id = if let Some(data) = state.xdg_popups.get_mut(&popup_id) {
                    // Update geometry
                    data.geometry = (
                        positioner_data.anchor_rect.0 + positioner_data.offset.0,
                        positioner_data.anchor_rect.1 + positioner_data.offset.1,
                        positioner_data.width,
                        positioner_data.height
                    );
                    data.anchor_rect = positioner_data.anchor_rect;
                    data.repositioned_token = Some(token);
                    
                    // CRITICAL: Emit event for FFI layer to reposition the platform window
                    state.pending_compositor_events.push(crate::core::compositor::CompositorEvent::PopupRepositioned {
                        window_id: data.window_id,
                        x: data.geometry.0,
                        y: data.geometry.1,
                        width: data.geometry.2 as u32,
                        height: data.geometry.3 as u32,
                    });

                    // Send repositioned event
                    resource.repositioned(token);
                    
                    // Send configure
                    resource.configure(
                        data.geometry.0,
                        data.geometry.1,
                        data.geometry.2,
                        data.geometry.3
                    );
                    
                    Some(data.surface_id)
                } else {
                    None
                };

                // Trigger surface configure to apply changes
                if let Some(sid) = surface_id {
                     let serial = state.next_serial();
                     if let Some(surface_data) = state.xdg_surfaces.get(&sid) {
                        if let Some(surface_resource) = &surface_data.resource {
                             surface_resource.configure(serial);
                        }
                    }
                }
            }
            _ => {}
        }
    }
}

