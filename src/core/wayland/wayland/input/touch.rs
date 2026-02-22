use wayland_server::{
    protocol::wl_touch,
    Dispatch, Resource, DisplayHandle,
};
use crate::core::state::CompositorState;

// ============================================================================
// wl_touch
// ============================================================================

impl Dispatch<wl_touch::WlTouch, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &wl_touch::WlTouch,
        request: wl_touch::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_touch::Request::Release => {
                tracing::debug!("wl_touch released");
            }
            _ => {}
        }
    }
}
