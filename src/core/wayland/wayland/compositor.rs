
use wayland_server::{
    protocol::{wl_compositor, wl_surface, wl_region},
    Dispatch, Resource, DisplayHandle, GlobalDispatch, WEnum,
};

use crate::core::state::CompositorState;
use crate::core::surface::Surface;

pub struct CompositorGlobal;

impl GlobalDispatch<wl_compositor::WlCompositor, ()> for CompositorState {
    #[allow(unreachable_code)]
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<wl_compositor::WlCompositor>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        data_init.init(resource, ());
        crate::wlog!(crate::util::logging::COMPOSITOR, "DEBUG: Compositor Bind Called");
    }
}

impl Dispatch<wl_compositor::WlCompositor, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &wl_compositor::WlCompositor,
        request: wl_compositor::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_compositor::Request::CreateSurface { id: new_id } => {
                // Generate a globally unique surface ID (not dependent on client's protocol IDs)
                let internal_id = state.next_surface_id();
                let surface: wl_surface::WlSurface = data_init.init(new_id, internal_id);
                let protocol_id = surface.id().protocol_id();
                
                // Map protocol ID to internal ID for cross-reference (used by layer_shell, etc.)
                state.protocol_to_internal_surface.insert(protocol_id, internal_id);
                
                state.add_surface(Surface::new(internal_id, Some(surface.clone())));
            }
            wl_compositor::Request::CreateRegion { id } => {
                let region: wl_region::WlRegion = data_init.init(id, ());
                let region_id = region.id().protocol_id();
                state.regions.insert(region_id, Vec::new());
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_surface::WlSurface, u32> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wl_surface::WlSurface,
        request: wl_surface::Request,
        data: &u32,
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wl_surface::Request::Commit => {
                let id = *data;
                state.handle_surface_commit(id);
            }
            wl_surface::Request::Attach { buffer, x, y } => {
                let id = *data;
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    if let Some(buffer_res) = buffer {
                        let buffer_id = buffer_res.id().protocol_id();
                        if let Some(b) = state.get_buffer(buffer_id) {
                            let mut b = b.write().unwrap();
                            // Reset released flag - client is reusing this buffer
                            b.released = false;
                            
                            let client_id = resource.client();
                            let client_outputs: Vec<_> = state.output_resources.values()
                                .filter(|o| o.client() == client_id)
                                .cloned()
                                .collect();
                                
                            if client_outputs.is_empty() {
                                let all_outputs: Vec<_> = state.output_resources.values()
                                    .map(|o| format!("{:?} (client={:?})", o.id(), o.client().as_ref().map(|c| c.id())))
                                    .collect();
                                crate::wlog!(crate::util::logging::COMPOSITOR, 
                                    "WARNING: No outputs bound for client {:?}. All bound outputs: {:?}", 
                                    client_id.as_ref().map(|c| c.id()), all_outputs);
                            } else {
                                let count = client_outputs.len();
                                for output in client_outputs {
                                    resource.enter(&output);
                                }
                                crate::wtrace!(crate::util::logging::COMPOSITOR, "Sent wl_surface.enter for surface {} to {} bound outputs for client {:?}", id, count, client_id.as_ref().map(|c| c.id()));
                            }

                            surface.pending.buffer = b.buffer_type.clone();
                            surface.pending.buffer_id = Some(buffer_id);
                            tracing::debug!("Surface {} attached buffer {} at ({}, {})", id, buffer_id, x, y);
                        } else {
                            // If buffer not found (e.g. from another protocol), use a generic placeholder
                            surface.pending.buffer = crate::core::surface::BufferType::None;
                            surface.pending.buffer_id = Some(buffer_id); // Still track the ID
                        }
                    } else {

                        surface.pending.buffer = crate::core::surface::BufferType::None;
                        surface.pending.buffer_id = None;
                        tracing::debug!("Surface {} detached buffer", id);
                    }
                }
            }
            wl_surface::Request::Damage { x, y, width, height } => {
                let id = *data;
                crate::wtrace!(crate::util::logging::COMPOSITOR, "Surface {} damage (local): x={}, y={}, width={}, height={}", id, x, y, width, height);
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    surface.pending.damage.push(crate::core::surface::damage::DamageRegion {
                        x, y, width, height
                    });
                }
            }
            wl_surface::Request::DamageBuffer { x, y, width, height } => {
                let id = *data;
                crate::wtrace!(crate::util::logging::COMPOSITOR, "Surface {} damage (buffer): x={}, y={}, width={}, height={}", id, x, y, width, height);
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    surface.pending.damage.push(crate::core::surface::damage::DamageRegion {
                        x, y, width, height
                    });
                }
            }
            wl_surface::Request::Frame { callback } => {
                let surface_id = *data;
                let cb: wayland_server::protocol::wl_callback::WlCallback = data_init.init(callback, ());
                
                // Queue the callback to be sent after the next frame is rendered
                state.queue_frame_callback(surface_id, cb);
                tracing::debug!("wl_surface.frame: queued callback for surface {}", surface_id);
            }
            wl_surface::Request::SetInputRegion { region } => {
                let id = *data;
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    if let Some(region_res) = region {
                        let region_id = region_res.id().protocol_id();
                        if let Some(rects) = state.regions.get(&region_id) {
                            surface.pending.input_region = Some(rects.clone());
                        }
                    } else {
                        surface.pending.input_region = None; // Infinite
                    }
                }
            }
            wl_surface::Request::SetOpaqueRegion { region } => {
                let id = *data;
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    if let Some(region_res) = region {
                        let region_id = region_res.id().protocol_id();
                        if let Some(rects) = state.regions.get(&region_id) {
                            surface.pending.opaque_region = Some(rects.clone());
                        }
                    } else {
                        surface.pending.opaque_region = None; // Empty (transparent)
                    }
                }
            }
            wl_surface::Request::SetBufferTransform { transform } => {
                let id = *data;
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    match transform {
                        wayland_server::WEnum::Value(t) => surface.pending.transform = t,
                        _ => {}
                    }
                }
            }
            wl_surface::Request::SetBufferScale { scale } => {
                let id = *data;
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    surface.pending.scale = scale;
                }
            }
            wl_surface::Request::Offset { x, y } => {
                let id = *data;
                if let Some(surface) = state.get_surface(id) {
                    let mut surface = surface.write().unwrap();
                    surface.pending.offset = (x, y);
                }
            }
            _ => {}
        }
    }
}

impl Dispatch<wl_region::WlRegion, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wl_region::WlRegion,
        request: wl_region::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let id = resource.id().protocol_id();
        match request {
            wl_region::Request::Add { x, y, width, height } => {
                if let Some(region) = state.regions.get_mut(&id) {
                    region.push(crate::core::surface::damage::DamageRegion::new(x, y, width, height));
                }
            }
            wl_region::Request::Subtract { x: sx, y: sy, width: sw, height: sh } => {
                if let Some(region) = state.regions.get_mut(&id) {
                    // Subtract rect (sx,sy,sw,sh) from each existing rect in the region.
                    // Each rect that intersects the subtract area is split into up to 4 pieces.
                    let sub = crate::core::surface::damage::DamageRegion::new(sx, sy, sw, sh);
                    let mut new_rects = Vec::new();
                    for rect in region.drain(..) {
                        // Compute intersection
                        let ix1 = rect.x.max(sub.x);
                        let iy1 = rect.y.max(sub.y);
                        let ix2 = (rect.x + rect.width).min(sub.x + sub.width);
                        let iy2 = (rect.y + rect.height).min(sub.y + sub.height);
                        if ix1 >= ix2 || iy1 >= iy2 {
                            // No intersection — keep the rect unchanged
                            new_rects.push(rect);
                            continue;
                        }
                        let rx2 = rect.x + rect.width;
                        let ry2 = rect.y + rect.height;
                        // Top strip
                        if rect.y < iy1 {
                            new_rects.push(crate::core::surface::damage::DamageRegion::new(
                                rect.x, rect.y, rect.width, iy1 - rect.y,
                            ));
                        }
                        // Bottom strip
                        if ry2 > iy2 {
                            new_rects.push(crate::core::surface::damage::DamageRegion::new(
                                rect.x, iy2, rect.width, ry2 - iy2,
                            ));
                        }
                        // Left strip (between top and bottom)
                        if rect.x < ix1 {
                            new_rects.push(crate::core::surface::damage::DamageRegion::new(
                                rect.x, iy1, ix1 - rect.x, iy2 - iy1,
                            ));
                        }
                        // Right strip (between top and bottom)
                        if rx2 > ix2 {
                            new_rects.push(crate::core::surface::damage::DamageRegion::new(
                                ix2, iy1, rx2 - ix2, iy2 - iy1,
                            ));
                        }
                    }
                    *region = new_rects;
                }
            }
            wl_region::Request::Destroy => {
                state.regions.remove(&id);
            }
            _ => {}
        }
    }
}

// wl_shm implementation for shared memory buffers
impl GlobalDispatch<wayland_server::protocol::wl_shm::WlShm, ()> for CompositorState {
    fn bind(
        _state: &mut Self,
        _handle: &DisplayHandle,
        _client: &wayland_server::Client,
        resource: wayland_server::New<wayland_server::protocol::wl_shm::WlShm>,
        _global_data: &(),
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        let shm = data_init.init(resource, ());
        // Advertise supported formats
        shm.format(wayland_server::protocol::wl_shm::Format::Argb8888);
        shm.format(wayland_server::protocol::wl_shm::Format::Xrgb8888);
    }
}

impl Dispatch<wayland_server::protocol::wl_shm::WlShm, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &wayland_server::protocol::wl_shm::WlShm,
        request: wayland_server::protocol::wl_shm::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wayland_server::protocol::wl_shm::Request::CreatePool { id, fd, size } => {
                let pool = data_init.init(id, ());
                let pool_id = pool.id().protocol_id();
                
                // Store the pool for later mmap access to pixel data
                state.shm_pools.insert(pool_id, crate::core::state::ShmPool::new(fd, size));
                tracing::debug!("wl_shm.create_pool: id={}, size={}", pool_id, size);
            }
            _ => {}
        }
    }
}

impl Dispatch<wayland_server::protocol::wl_shm_pool::WlShmPool, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wayland_server::protocol::wl_shm_pool::WlShmPool,
        request: wayland_server::protocol::wl_shm_pool::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wayland_server::protocol::wl_shm_pool::Request::CreateBuffer { 
                id, offset, width, height, stride, format 
            } => {
                let buffer_res = data_init.init(id, ());
                let buffer_id = buffer_res.id().protocol_id();
                
                // Track SHM buffer metadata
                let shm_data = crate::core::surface::ShmBufferData {
                    width,
                    height,
                    stride,
                    format: match format {
                        WEnum::Value(f) => f as u32,
                        WEnum::Unknown(f) => f,
                    },
                    offset,
                    pool_id: resource.id().protocol_id(),
                };
                
                state.add_buffer(crate::core::surface::Buffer::new(
                    buffer_id,
                    crate::core::surface::BufferType::Shm(shm_data),
                    Some(buffer_res.clone())
                ));
                
                // Store buffer resource for release events
                tracing::debug!("wl_shm_pool.create_buffer: {}x{} (id={})", width, height, buffer_id);
            }
            wayland_server::protocol::wl_shm_pool::Request::Resize { size } => {
                let pool_id = resource.id().protocol_id();
                if let Some(pool) = state.shm_pools.get_mut(&pool_id) {
                    pool.resize(size);
                }
            }
            _ => {}
        }
    }
}

impl Dispatch<wayland_server::protocol::wl_buffer::WlBuffer, ()> for CompositorState {
    fn request(
        state: &mut Self,
        _client: &wayland_server::Client,
        resource: &wayland_server::protocol::wl_buffer::WlBuffer,
        request: wayland_server::protocol::wl_buffer::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        match request {
            wayland_server::protocol::wl_buffer::Request::Destroy => {
                let id = resource.id().protocol_id();
                state.remove_buffer(id);
                tracing::debug!("wl_buffer.destroy: removed buffer {}", id);
            }
            _ => {}
        }
    }
}

impl Dispatch<wayland_server::protocol::wl_callback::WlCallback, ()> for CompositorState {
    fn request(
        _state: &mut Self,
        _client: &wayland_server::Client,
        _resource: &wayland_server::protocol::wl_callback::WlCallback,
        _request: wayland_server::protocol::wl_callback::Request,
        _data: &(),
        _dhandle: &DisplayHandle,
        _data_init: &mut wayland_server::DataInit<'_, Self>,
    ) {
        // Callbacks don't have requests, they're one-shot events
    }
}
