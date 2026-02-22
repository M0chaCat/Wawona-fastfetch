use wayland_server::{
    protocol::wl_pointer,
    Dispatch, Resource, DisplayHandle,
};
use crate::core::state::CompositorState;

// ============================================================================
// wl_pointer
// ============================================================================

impl Dispatch<wl_pointer::WlPointer, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &wl_pointer::WlPointer,
        request: wl_pointer::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_pointer::Request::SetCursor { serial: _, surface, hotspot_x, hotspot_y } => {
                let surface_id = surface.as_ref().map(|s| s.id().protocol_id());
                state.seat.pointer.cursor_surface = surface_id;
                state.seat.pointer.cursor_hotspot_x = hotspot_x as f64;
                state.seat.pointer.cursor_hotspot_y = hotspot_y as f64;
                
                tracing::debug!(
                    "wl_pointer.set_cursor: surface={:?}, hotspot=({}, {})",
                    surface_id, hotspot_x, hotspot_y
                );
            }
            wl_pointer::Request::Release => {
                tracing::debug!("wl_pointer released");
            }
            _ => {}
        }
    }
}
