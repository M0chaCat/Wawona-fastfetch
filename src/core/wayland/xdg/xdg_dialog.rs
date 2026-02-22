//! XDG Dialog protocol implementation.
//!
//! This protocol allows clients to mark toplevels as dialog windows,
//! optionally making them modal (preventing interaction with the parent).

use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use wayland_protocols::xdg::dialog::v1::server::{
    xdg_dialog_v1::{self, XdgDialogV1},
    xdg_wm_dialog_v1::{self, XdgWmDialogV1},
};

use crate::core::state::CompositorState;

// ============================================================================
// xdg_wm_dialog_v1
// ============================================================================

impl GlobalDispatch<XdgWmDialogV1, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<XdgWmDialogV1>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound xdg_wm_dialog_v1");
    }
}

impl Dispatch<XdgWmDialogV1, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &Client,
        _resource: &XdgWmDialogV1,
        request: xdg_wm_dialog_v1::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            xdg_wm_dialog_v1::Request::GetXdgDialog { id, toplevel } => {
                let toplevel_id = toplevel.id().protocol_id();
                let _dialog: XdgDialogV1 = data_init.init(id, toplevel_id);
                tracing::debug!("Created dialog for toplevel {}", toplevel_id);
            }
            xdg_wm_dialog_v1::Request::Destroy => {
                tracing::debug!("xdg_wm_dialog_v1 destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// xdg_dialog_v1 — uses toplevel protocol_id (u32) as user data
// ============================================================================

impl Dispatch<XdgDialogV1, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &XdgDialogV1,
        request: xdg_dialog_v1::Request,
        data: &u32,
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let toplevel_id = *data;
        match request {
            xdg_dialog_v1::Request::SetModal => {
                tracing::debug!("Dialog for toplevel {} set as modal", toplevel_id);
                // Find the window and mark it as modal
                if let Some(tl_data) = state.xdg.toplevels.get(&toplevel_id) {
                    let window_id = tl_data.window_id;
                    if let Some(window) = state.get_window(window_id) {
                        if let Ok(mut w) = window.write() {
                            w.modal = true;
                        }
                    }
                }
            }
            xdg_dialog_v1::Request::UnsetModal => {
                tracing::debug!("Dialog for toplevel {} unset modal", toplevel_id);
                if let Some(tl_data) = state.xdg.toplevels.get(&toplevel_id) {
                    let window_id = tl_data.window_id;
                    if let Some(window) = state.get_window(window_id) {
                        if let Ok(mut w) = window.write() {
                            w.modal = false;
                        }
                    }
                }
            }
            xdg_dialog_v1::Request::Destroy => {
                // Clear modal state on destroy
                if let Some(tl_data) = state.xdg.toplevels.get(&toplevel_id) {
                    let window_id = tl_data.window_id;
                    if let Some(window) = state.get_window(window_id) {
                        if let Ok(mut w) = window.write() {
                            w.modal = false;
                        }
                    }
                }
                tracing::debug!("xdg_dialog_v1 destroyed for toplevel {}", toplevel_id);
            }
            _ => {}
        }
    }
}

/// Register xdg_wm_dialog_v1 global
pub fn register_xdg_dialog(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, XdgWmDialogV1, ()>(1, ())
}
