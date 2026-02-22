//! WP Viewporter protocol implementation.
//!
//! This protocol allows clients to crop and scale their surface content,
//! useful for video playback, image viewers, and resolution-independent UIs.


use wayland_server::{
    Client, DataInit, Dispatch, DisplayHandle, GlobalDispatch, New, Resource,
};
use crate::core::wayland::protocol::server::wp::viewporter::server::{
    wp_viewporter::{self, WpViewporter},
    wp_viewport::{self, WpViewport},
};


use crate::core::state::CompositorState;
use std::collections::HashMap;

// ============================================================================
// Data Types
// ============================================================================

#[derive(Debug, Clone)]
pub struct ViewportData {
    pub surface_id: u32,
    pub source: Option<ViewportSource>,
    pub destination: Option<(i32, i32)>,
}

#[derive(Debug, Clone, Copy)]
pub struct ViewportSource {
    pub x: f64, 
    pub y: f64, 
    pub width: f64, 
    pub height: f64
}

impl ViewportData {
    pub fn new(surface_id: u32) -> Self {
        Self { surface_id, source: None, destination: None }
    }
}

/// State for viewporter protocol
#[derive(Debug, Default)]
pub struct ViewporterState {
    pub viewports: HashMap<u32, ViewportData>,
}


// ============================================================================
// wp_viewporter
// ============================================================================

impl GlobalDispatch<WpViewporter, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &Client,
        resource: New<WpViewporter>,
        _global_data: &(),
        data_init: &mut DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        tracing::debug!("Bound wp_viewporter");
    }
}

impl Dispatch<WpViewporter, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        _resource: &WpViewporter,
        request: wp_viewporter::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut DataInit<'_, Self>,
    ) {
        match request {
            wp_viewporter::Request::GetViewport { id, surface } => {
                let surface_id = surface.id().protocol_id();
                
                let viewport_data = ViewportData::new(surface_id);
                let viewport: wp_viewport::WpViewport = data_init.init(id, ());
                state.ext.viewporter.viewports.insert(viewport.id().protocol_id(), viewport_data);

                
                tracing::debug!("Created viewport for surface {}", surface_id);
            }
            wp_viewporter::Request::Destroy => {
                tracing::debug!("wp_viewporter destroyed");
            }
            _ => {}
        }
    }
}

// ============================================================================
// wp_viewport
// ============================================================================

impl Dispatch<WpViewport, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &Client,
        resource: &WpViewport,
        request: wp_viewport::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut DataInit<'_, Self>,
    ) {
        let viewport_id = resource.id().protocol_id();
        
        match request {
            wp_viewport::Request::SetSource { x, y, width, height } => {
                if let Some(data) = state.ext.viewporter.viewports.get_mut(&viewport_id) {

                    // -1 means unset
                    if x == -1.0 && y == -1.0 && width == -1.0 && height == -1.0 {
                        data.source = None;
                        tracing::debug!("Viewport source unset for surface {}", data.surface_id);
                    } else {
                        // Validate source rectangle
                        if width <= 0.0 || height <= 0.0 {
                            resource.post_error(
                                wp_viewport::Error::BadSize,
                                "Source width and height must be positive",
                            );
                            return;
                        }
                        
                        data.source = Some(ViewportSource { x, y, width, height });
                        tracing::debug!(
                            "Viewport source set for surface {}: ({}, {}) {}x{}",
                            data.surface_id, x, y, width, height
                        );
                    }
                }
            }
            wp_viewport::Request::SetDestination { width, height } => {
                if let Some(data) = state.ext.viewporter.viewports.get_mut(&viewport_id) {

                    // -1 means unset
                    if width == -1 && height == -1 {
                        data.destination = None;
                        tracing::debug!("Viewport destination unset for surface {}", data.surface_id);
                    } else {
                        // Validate destination size
                        if width <= 0 || height <= 0 {
                            resource.post_error(
                                wp_viewport::Error::BadSize,
                                "Destination width and height must be positive",
                            );
                            return;
                        }
                        
                        data.destination = Some((width, height));
                        tracing::debug!(
                            "Viewport destination set for surface {}: {}x{}",
                            data.surface_id, width, height
                        );
                    }
                }
            }
            wp_viewport::Request::Destroy => {
                if let Some(data) = state.ext.viewporter.viewports.remove(&viewport_id) {
                    tracing::debug!("Viewport destroyed for surface {}", data.surface_id);

                }
            }
            _ => {}
        }
    }
}

/// Register wp_viewporter global
pub fn register_viewporter(display: &DisplayHandle) -> wayland_server::backend::GlobalId {
    display.create_global::<CompositorState, WpViewporter, ()>(1, ())
}
