use std::collections::HashMap;
use wayland_server::Resource;
use wayland_server::protocol::wl_touch::WlTouch;
use wayland_server::protocol::wl_surface::WlSurface;

/// A single active touch point
#[derive(Debug, Clone)]
pub struct TouchPoint {
    /// Touch point ID
    pub id: i32,
    /// Surface that received the touch down event (internal ID)
    pub surface_id: u32,
    /// Current position in surface-local coordinates
    pub x: f64,
    pub y: f64,
}

/// Touch state for a seat, managing active touch points and resources.
#[derive(Debug, Clone, Default)]
pub struct TouchState {
    /// Active touch points, keyed by touch ID
    pub active_points: HashMap<i32, TouchPoint>,
    /// Bound touch resources from clients
    pub resources: Vec<WlTouch>,
}

impl TouchState {
    pub fn new() -> Self {
        Self::default()
    }

    /// Add a touch resource
    pub fn add_resource(&mut self, touch: WlTouch) {
        self.resources.push(touch);
    }

    /// Remove a touch resource
    pub fn remove_resource(&mut self, resource: &WlTouch) {
        self.resources.retain(|t| t.id() != resource.id());
    }

    /// Record a new touch point
    pub fn touch_down(&mut self, id: i32, surface_id: u32, x: f64, y: f64) {
        self.active_points.insert(
            id,
            TouchPoint {
                id,
                surface_id,
                x,
                y,
            },
        );
    }

    /// Update a touch point position
    pub fn touch_motion(&mut self, id: i32, x: f64, y: f64) {
        if let Some(point) = self.active_points.get_mut(&id) {
            point.x = x;
            point.y = y;
        }
    }

    /// Remove a touch point
    pub fn touch_up(&mut self, id: i32) {
        self.active_points.remove(&id);
    }

    /// Cancel all touch points
    pub fn touch_cancel(&mut self) {
        self.active_points.clear();
    }

    /// Get the surface for a touch point
    pub fn get_touch_surface(&self, id: i32) -> Option<u32> {
        self.active_points.get(&id).map(|p| p.surface_id)
    }

    /// Whether any touch points are active
    pub fn has_active_touches(&self) -> bool {
        !self.active_points.is_empty()
    }

    /// Send touch down event
    pub fn broadcast_down(
        &self,
        serial: u32,
        time: u32,
        surface: &WlSurface,
        id: i32,
        x: f64,
        y: f64,
    ) {
        let client = surface.client();
        for touch in &self.resources {
            if touch.client() == client {
                touch.down(serial, time, surface, id, x, y);
            }
        }
    }

    /// Send touch up event
    pub fn broadcast_up(
        &self,
        serial: u32,
        time: u32,
        id: i32,
        focused_client: Option<&wayland_server::Client>,
    ) {
        if let Some(focused) = focused_client {
            for touch in &self.resources {
                if touch.client().as_ref() == Some(focused) {
                    touch.up(serial, time, id);
                }
            }
        }
    }

    /// Send touch motion event
    pub fn broadcast_motion(
        &self,
        time: u32,
        id: i32,
        x: f64,
        y: f64,
        focused_client: Option<&wayland_server::Client>,
    ) {
        if let Some(focused) = focused_client {
            for touch in &self.resources {
                if touch.client().as_ref() == Some(focused) {
                    touch.motion(time, id, x, y);
                }
            }
        }
    }

    /// Send touch frame event
    pub fn broadcast_frame(&self, focused_client: Option<&wayland_server::Client>) {
        if let Some(focused) = focused_client {
            for touch in &self.resources {
                if touch.client().as_ref() == Some(focused) {
                    touch.frame();
                }
            }
        }
    }

    /// Send touch cancel event
    pub fn broadcast_cancel(&self, focused_client: Option<&wayland_server::Client>) {
        if let Some(focused) = focused_client {
            for touch in &self.resources {
                if touch.client().as_ref() == Some(focused) {
                    touch.cancel();
                }
            }
        }
    }

    /// Clean up dead touch resources
    pub fn cleanup_resources(&mut self) {
        let before = self.resources.len();
        self.resources.retain(|t| t.is_alive());
        if before != self.resources.len() {
            crate::wlog!(
                crate::util::logging::SEAT,
                "Cleaned up {} dead touches",
                before - self.resources.len()
            );
        }
    }
}
