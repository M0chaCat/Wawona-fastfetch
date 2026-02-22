use crate::core::surface::surface::SurfaceState;
use crate::core::surface::damage::DamageRegion;

/// Validates and clamps region rectangles to surface bounds.
/// Returns None for regions that pass validation, or clamps out-of-bounds ones.
fn validate_regions(regions: &Option<Vec<DamageRegion>>, width: i32, height: i32) -> Option<Vec<DamageRegion>> {
    regions.as_ref().map(|rects| {
        rects.iter()
            .filter_map(|r| {
                if r.width <= 0 || r.height <= 0 {
                    tracing::warn!("Dropping invalid region: {}x{} at ({},{})", r.width, r.height, r.x, r.y);
                    return None;
                }
                if width > 0 && height > 0 {
                    let clamped = r.clamp(width, height);
                    if clamped.width > 0 && clamped.height > 0 {
                        Some(clamped)
                    } else {
                        None
                    }
                } else {
                    Some(*r)
                }
            })
            .collect()
    })
}

/// Performs the atomic update of a surface state.
/// Returns the ID of the buffer that was replaced and should be released, if any.
pub fn apply_commit(pending: &mut SurfaceState, current: &mut SurfaceState) -> Option<u32> {
    // Check if buffer is changing
    let old_buffer = if pending.buffer_id != current.buffer_id {
        current.buffer_id
    } else {
        None
    };

    // 1. Update buffer if pending
    current.buffer = pending.buffer.clone();
    current.buffer_id = pending.buffer_id;
    
    // 2. Update dimensions based on buffer size, scale and transform
    if let Some((buffer_width, buffer_height)) = current.buffer.dimensions() {
        let scale = pending.scale.max(1);
        
        // Handle transforms that swap width/height
        let swapped = match pending.transform {
            wayland_server::protocol::wl_output::Transform::_90 |
            wayland_server::protocol::wl_output::Transform::_270 |
            wayland_server::protocol::wl_output::Transform::Flipped90 |
            wayland_server::protocol::wl_output::Transform::Flipped270 => true,
            _ => false,
        };
        
        if swapped {
            current.width = buffer_height / scale;
            current.height = buffer_width / scale;
        } else {
            current.width = buffer_width / scale;
            current.height = buffer_height / scale;
        }
    } else {
        current.width = 0;
        current.height = 0;
    }
    
    // 3. Accumulate damage (clamp to surface bounds)
    for region in pending.damage.drain(..) {
        if current.width > 0 && current.height > 0 {
            let clamped = region.clamp(current.width, current.height);
            if clamped.is_valid() {
                current.damage.push(clamped);
            }
        } else {
            if region.is_valid() {
                current.damage.push(region);
            }
        }
    }
    
    // 4. Update other attributes
    current.opaque = pending.opaque;
    current.scale = pending.scale;
    current.transform = pending.transform;
    current.offset = pending.offset;

    // 5. Validate and clamp input/opaque regions to surface bounds
    current.input_region = validate_regions(&pending.input_region, current.width, current.height);
    current.opaque_region = validate_regions(&pending.opaque_region, current.width, current.height);
    
    old_buffer
}
