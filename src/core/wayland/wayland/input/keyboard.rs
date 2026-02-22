use wayland_server::{
    protocol::wl_keyboard,
    Dispatch, Resource, DisplayHandle,
};
use crate::core::state::CompositorState;

// ============================================================================
// wl_keyboard
// ============================================================================

impl Dispatch<wl_keyboard::WlKeyboard, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &wl_keyboard::WlKeyboard,
        request: wl_keyboard::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_keyboard::Request::Release => {
                tracing::debug!("wl_keyboard released");
            }
            _ => {}
        }
    }
}
