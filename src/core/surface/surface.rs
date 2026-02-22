
use super::buffer::BufferType;
use super::role::SurfaceRole;
use super::damage::DamageRegion;

/// Represents the state of a surface at a point in time.
/// Used for double-buffering (pending vs current).
#[derive(Debug, Clone)]
pub struct SurfaceState {
    pub buffer: BufferType,
    pub buffer_id: Option<u32>,
    pub width: i32,
    pub height: i32,
    pub offset: (i32, i32),
    pub damage: Vec<DamageRegion>,
    pub input_region: Option<Vec<crate::core::surface::damage::DamageRegion>>, // Using DamageRegion as Rect equivalent for now
    pub opaque_region: Option<Vec<crate::core::surface::damage::DamageRegion>>,
    pub opaque: bool,
    pub scale: i32,
    pub transform: wayland_server::protocol::wl_output::Transform, // Using the protocol enum directly
}

/// Represents a Wayland Surface.
pub struct Surface {
    pub id: u32,
    pub role: SurfaceRole,
    
    /// The Wayland resource handle
    pub resource: Option<wayland_server::protocol::wl_surface::WlSurface>,
    
    /// The state currently visible to the compositor
    pub current: SurfaceState,
    /// The state being built by client requests, to be applied on commit
    pub pending: SurfaceState,
    /// The state committed but waiting for parent commit (for synchronized subsurfaces)
    pub cached: Option<SurfaceState>,
}

impl Surface {
    pub fn new(id: u32, resource: Option<wayland_server::protocol::wl_surface::WlSurface>) -> Self {
        Self {
            id,
            role: SurfaceRole::None,
            resource,
            current: SurfaceState::default(),
            pending: SurfaceState::default(),
            cached: None,
        }
    }

    /// Set the surface role. Returns error if role is already set to something else.
    pub fn set_role(&mut self, role: SurfaceRole) -> std::result::Result<(), String> {
        if self.role != SurfaceRole::None && self.role != role {
            return Err(format!(
                "Surface {} has role {:?}, cannot change to {:?}",
                self.id, self.role, role
            ));
        }
        self.role = role;
        Ok(())
    }

    /// Commit the pending state to current
    /// Returns the ID of the buffer to release, if any.
    pub fn commit(&mut self) -> Option<u32> {
        let release_id = super::commit::apply_commit(&mut self.pending, &mut self.current);
        
        tracing::debug!(
            "Surface {} committed: {}x{}, buffer={:?}",
            self.id, self.current.width, self.current.height, self.current.buffer
        );
        
        release_id
    }

    /// Commit the pending state to cached (for synchronized subsurfaces)
    /// Returns the ID of the buffer that was replaced in cached, if any.
    pub fn commit_sync(&mut self) -> Option<u32> {
        // If there was already a cached state, we might need to release its buffer
        let old_buffer_id = self.cached.as_ref().and_then(|s| s.buffer_id);
        
        // Move pending to cached
        let new_cached = self.pending.clone();
        // Reset pending damage for next commit
        self.pending.damage.clear();
        
        self.cached = Some(new_cached);
        
        tracing::debug!(
            "Surface {} committed to cached (sync mode)",
            self.id
        );
        
        old_buffer_id
    }

    /// Apply the cached state to current
    /// Returns the ID of the buffer to release, if any.
    pub fn apply_cached(&mut self) -> Option<u32> {
        if let Some(mut cached_state) = self.cached.take() {
            let release_id = super::commit::apply_commit(&mut cached_state, &mut self.current);
            
            tracing::debug!(
                "Surface {} applied cached state: {}x{}, buffer={:?}",
                self.id, self.current.width, self.current.height, self.current.buffer
            );
            
            release_id
        } else {
            None
        }
    }
}

impl Default for SurfaceState {
    fn default() -> Self {
        Self {
            buffer: BufferType::default(),
            buffer_id: None,
            width: 0,
            height: 0,
            offset: (0, 0),
            damage: Vec::new(),
            input_region: None, // None means infinite (accept all input)
            opaque_region: None, // None means empty (fully transparent)
            opaque: false, // Legacy field, might be redundant with opaque_region but kept for now
            scale: 1,
            transform: wayland_server::protocol::wl_output::Transform::Normal,
        }
    }
}
