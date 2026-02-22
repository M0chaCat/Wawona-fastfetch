//! XDG Surface protocol implementation.
//!
//! This implements the xdg_surface protocol from the xdg-shell extension.
//! It provides the base interface for creating toplevel and popup windows.

use wayland_server::{
    Dispatch, DisplayHandle, Resource,
};
use crate::core::wayland::protocol::server::xdg::shell::server::xdg_surface;

use crate::core::state::{CompositorState, XdgToplevelData, XdgPopupData};
use crate::core::window::Window;

impl Dispatch<xdg_surface::XdgSurface, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &xdg_surface::XdgSurface,
        request: xdg_surface::Request,
        _data: &u32,
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let surface_id = resource.id().protocol_id();
        let data = state.xdg.surfaces.get(&surface_id).cloned();
        
        match request {
            xdg_surface::Request::GetToplevel { id } => {
                crate::wlog!(crate::util::logging::COMPOSITOR, "xdg_surface.get_toplevel for surface {}", surface_id);
                if let Some(data) = data {
                    // Create a new window for this toplevel
                    let window_id = state.next_window_id();
                    let window = Window::new(window_id, data.surface_id);
                    
                     // Get output dimensions for initial size
                    let (initial_width, initial_height, scale) = {
                        let output = state.primary_output();
                        (output.width, output.height, output.scale)
                    };
                    
                    // Create toplevel data (wl_surface_id, xdg_surface_id)
                    let mut toplevel_data = XdgToplevelData::new(window_id, data.surface_id, surface_id);
                    // Store the window ID (u32) as user data for the toplevel resource
                    let toplevel: wayland_protocols::xdg::shell::server::xdg_toplevel::XdgToplevel = data_init.init(id, window_id);
                    toplevel_data.resource = Some(toplevel.clone());
                    
                    state.xdg.toplevels.insert(toplevel.id().protocol_id(), toplevel_data);
                    
                    // Update surface data with window_id
                    if let Some(surface_data) = state.xdg.surfaces.get_mut(&surface_id) {
                        surface_data.window_id = Some(window_id);
                    }
                    
                    // Add window to state
                    state.add_window(window);
                    
                    // Send initial configure
                    // Use logical coordinates (physical / scale)
                    let logical_width = (initial_width as f32 / scale) as i32;
                    let logical_height = (initial_height as f32 / scale) as i32;
                    
                    // Generate configure serial
                    let serial = state.next_serial();
                    
                    // State byte array expects sequence of u32s. 
                    // State::Activated is usually the correct starting state for new windows in Wawona.
                    let mut states: Vec<u8> = vec![];
                    states.extend_from_slice(&((wayland_protocols::xdg::shell::server::xdg_toplevel::State::Activated as u32).to_ne_bytes()));
                    
                    crate::wlog!(crate::util::logging::COMPOSITOR, 
                        "Configuring xdg_toplevel: window={} surface={} size={}x{} states={:?} serial={}", 
                        window_id, data.surface_id, logical_width, logical_height, states, serial);

                    toplevel.configure(logical_width, logical_height, states);
                    resource.configure(serial);
                    
                    // Set surface role
                    if let Some(surface) = state.get_surface(data.surface_id) {
                        let mut surface = surface.write().unwrap();
                        if let Err(e) = surface.set_role(crate::core::surface::SurfaceRole::Toplevel) {
                            tracing::error!("Failed to set role for surface {}: {}", data.surface_id, e);
                        }
                    }
                    
                    tracing::info!(
                        "Created xdg_toplevel: window_id={}, surface_id={}, size={}x{}",
                        window_id, data.surface_id, initial_width, initial_height
                    );
                    

                    // CRITICAL: Push WindowCreated event for FFI layer to create platform window
                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::WindowCreated {
                            window_id,
                            surface_id: data.surface_id,
                            title: String::new(),  // Title will be set via set_title later
                            width: initial_width,
                            height: initial_height,
                            decoration_mode: state.decoration_mode_for_new_window(),
                            fullscreen_shell: false,
                        }
                    );
                }
            }
            xdg_surface::Request::GetPopup { id, parent, positioner } => {
                if let Some(data) = data {
                    let surface_id = data.surface_id;
                    // Set surface role
                    if let Some(surface) = state.get_surface(surface_id) {
                        let mut surface = surface.write().unwrap();
                        if let Err(e) = surface.set_role(crate::core::surface::SurfaceRole::Popup) {
                            tracing::error!("Failed to set role for surface {}: {}", surface_id, e);
                        }
                    }

                    // Get positioner data
                    let positioner_data = state.xdg.positioners
                        .remove(&positioner.id().protocol_id())
                        .unwrap_or_default();

                    // Get output dimensions for initial size
                    let (ox, oy, initial_width, initial_height, _scale) = {
                        let output = state.primary_output();
                        (output.x, output.y, output.width, output.height, output.scale)
                    };
                    
                    let output_rect = crate::util::geometry::Rect::new(ox, oy, initial_width, initial_height);
                    
                    // Calculate position using anchor/gravity rules
                    let (px, py) = positioner_data.calculate_position(output_rect);
                    
                    // Create popup state
                    let window_id = state.next_window_id();
                    let popup_data = XdgPopupData {
                        surface_id: data.surface_id,
                        xdg_surface_id: surface_id,
                        window_id,
                        parent_id: parent.as_ref().map(|p| p.id().protocol_id()),
                        geometry: (px, py, positioner_data.width, positioner_data.height),
                        anchor_rect: positioner_data.anchor_rect,
                        grabbed: false,
                        repositioned_token: None,
                        resource: None,
                    };
                    
                    // Initialize the popup with window_id (u32)
                    let popup: wayland_protocols::xdg::shell::server::xdg_popup::XdgPopup = data_init.init(id, window_id);
                    
                    let mut popup_data = popup_data;
                    popup_data.resource = Some(popup.clone());
                    
                    state.xdg.popups.insert(popup.id().protocol_id(), popup_data);
                    
                    // CRITICAL: Register in surface_to_window for buffer routing
                    state.surface_to_window.insert(surface_id, window_id);
                    
                    // Update surface data with window_id
                    if let Some(surface_data) = state.xdg.surfaces.get_mut(&surface_id) {
                        surface_data.window_id = Some(window_id);
                    }
                    
                    tracing::debug!("Created xdg_popup for surface {}, window_id={}", surface_id, window_id);
                    
                    // CRITICAL: Push PopupCreated event for FFI layer
                    // We need to resolve parent popup/toplevel ID to a Window ID if possible
                    // For now, pass 0 as parent if lookup fails, but we should try
                    let parent_window_id = if let Some(parent_obj) = parent.as_ref() {
                        // This logic is simplified; parent could be xdg_surface or xdg_toplevel
                        // Typically it's the xdg_surface ID. We need its window ID.
                        // Assuming parent is XdgSurface resource:
                        state.xdg.surfaces.get(&parent_obj.id().protocol_id())
                             .and_then(|d| d.window_id)
                             .unwrap_or(0)
                    } else {
                        0
                    };

                    // Send enter events for all bound outputs
                    let surface_res = if let Some(s) = state.get_surface(surface_id) {
                        s.read().unwrap().resource.clone()
                    } else {
                        None
                    };

                    if let Some(surface_res) = surface_res {
                        for output in state.output_resources.values() {
                            // Only send enter event if output belongs to the same client
                            if surface_res.client() == output.client() {
                                surface_res.enter(output);
                            }
                        }
                    }

                    state.pending_compositor_events.push(
                        crate::core::compositor::CompositorEvent::PopupCreated {
                            window_id,
                            surface_id,
                            parent_id: parent_window_id,
                            x: px,
                            y: py,
                            width: positioner_data.width.max(1) as u32,
                            height: positioner_data.height.max(1) as u32,
                        }
                    );

                    // Send initial configure
                        let next_serial = state.next_serial();
                        crate::wlog!(crate::util::logging::COMPOSITOR, "Configuring xdg_popup: window={} surface={} x={} y={} w={} h={} serial={}", 
                            window_id, surface_id, px, py, positioner_data.width, positioner_data.height, next_serial);

                        popup.configure(px, py, positioner_data.width, positioner_data.height);
                        
                        // Send surface configure
                        resource.configure(next_serial);
                        return;
                }
            }
            xdg_surface::Request::AckConfigure { serial } => {
                crate::wlog!(crate::util::logging::COMPOSITOR, "Client acked configure serial {}", serial);
                if let Some(data) = data {
                    // Mark the window as configured
                    if let Some(window_id) = data.window_id {
                        if let Some(window) = state.get_window(window_id) {
                            // Window is now ready
                            tracing::debug!("Window {} is now configured", window_id);
                            
                            // Check for toplevel state transitions
                            let mut to_finalize = None;
                            for (tl_id, tl_data) in state.xdg.toplevels.iter() {
                                if tl_data.xdg_surface_id == surface_id && tl_data.pending_serial == serial {
                                    to_finalize = Some(*tl_id);
                                    break;
                                }
                            }
                            
                            if let Some(tl_id) = to_finalize {
                                let mut window = window.write().unwrap();
                                if let Some(tl_data) = state.xdg.toplevels.get_mut(&tl_id) {
                                    tl_data.maximized = tl_data.pending_maximized;
                                    tl_data.fullscreen = tl_data.pending_fullscreen;
                                    
                                    // Mirror to window state
                                    window.maximized = tl_data.maximized;
                                    window.fullscreen = tl_data.fullscreen;
                                    
                                    tracing::info!("Finalized state for window {}: maximized={}, fullscreen={}", 
                                        window_id, tl_data.maximized, tl_data.fullscreen);
                                }
                            }
                        }
                    }
                }
            }
            xdg_surface::Request::SetWindowGeometry { x, y, width, height } => {
                tracing::debug!(
                    "xdg_surface.set_window_geometry: ({}, {}) {}x{}",
                    x, y, width, height
                );
                if let Some(surface_data) = state.xdg.surfaces.get_mut(&surface_id) {
                    surface_data.geometry = Some((x, y, width, height));
                }
            }
            xdg_surface::Request::Destroy => {
                state.xdg.surfaces.remove(&surface_id);
                tracing::debug!("xdg_surface destroyed");
            }
            _ => {}
        }
    }
}
