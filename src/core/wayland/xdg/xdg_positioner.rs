//! XDG Positioner protocol implementation.
//!
//! This implements the xdg_positioner protocol from the xdg-shell extension.
//! It provides positioning constraints for popup surfaces.


use wayland_server::{
    Dispatch, Resource, DisplayHandle,
};
use crate::core::wayland::protocol::server::xdg::shell::server::xdg_positioner;

use crate::core::state::{CompositorState, XdgPositionerData};

impl Dispatch<xdg_positioner::XdgPositioner, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &xdg_positioner::XdgPositioner,
        request: xdg_positioner::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let positioner_id = resource.id().protocol_id();
        
        // Ensure positioner data exists
        if !state.xdg.positioners.contains_key(&positioner_id) {
            state.xdg.positioners.insert(positioner_id, XdgPositionerData::default());
        }
        
        // Helper to update positioner data
        let update_positioner = |state: &mut CompositorState, id: u32, update_fn: Box<dyn FnOnce(&mut XdgPositionerData)>| {
            if let Some(data) = state.xdg.positioners.get_mut(&id) {
                update_fn(data);
            }
        };

        match request {
            xdg_positioner::Request::SetSize { width, height } => {
                tracing::trace!("xdg_positioner.set_size: {}x{}", width, height);
                update_positioner(state, positioner_id, Box::new(move |data| {
                    data.width = width;
                    data.height = height;
                }));
            }
            xdg_positioner::Request::SetAnchorRect { x, y, width, height } => {
                tracing::trace!("xdg_positioner.set_anchor_rect: {},{} {}x{}", x, y, width, height);
                update_positioner(state, positioner_id, Box::new(move |data| {
                    data.anchor_rect = (x, y, width, height);
                }));
            }
            xdg_positioner::Request::SetAnchor { anchor } => {
                tracing::trace!("xdg_positioner.set_anchor: {:?}", anchor);
                if let wayland_server::WEnum::Value(anchor_val) = anchor {
                    let raw_val: u32 = anchor_val.into();
                     update_positioner(state, positioner_id, Box::new(move |data| {
                        data.anchor = raw_val;
                    }));
                }
            }
            xdg_positioner::Request::SetGravity { gravity } => {
                tracing::trace!("xdg_positioner.set_gravity: {:?}", gravity);
                if let wayland_server::WEnum::Value(gravity_val) = gravity {
                    let raw_val: u32 = gravity_val.into();
                    update_positioner(state, positioner_id, Box::new(move |data| {
                        data.gravity = raw_val;
                    }));
                }
            }
            xdg_positioner::Request::SetConstraintAdjustment { constraint_adjustment } => {
                tracing::trace!("xdg_positioner.set_constraint_adjustment: {:?}", constraint_adjustment);
                let raw_val = u32::from(constraint_adjustment); 
                update_positioner(state, positioner_id, Box::new(move |data| {
                    data.constraint_adjustment = raw_val;
                }));
            }
            xdg_positioner::Request::SetOffset { x, y } => {
                tracing::trace!("xdg_positioner.set_offset: {},{}", x, y);
                update_positioner(state, positioner_id, Box::new(move |data| {
                    data.offset = (x, y);
                }));
            }
            xdg_positioner::Request::Destroy => {
                tracing::trace!("xdg_positioner destroyed");
                state.xdg.positioners.remove(&positioner_id);
            }
            _ => {}
        }
    }
}

