//! UniFFI API Implementation
//! 
//! This module provides the FFI boundary for the Wawona compositor.
//! All platform-specific code (macOS, iOS, Android) interacts with the
//! compositor through this stable API.
//!
//! Key design principles:
//! - Platform code never directly accesses Wayland types or compositor internals
//! - All state is managed by Rust core
//! - Platform receives high-level events and provides rendering/windowing services

use std::sync::{Arc, RwLock, Mutex};
use std::collections::HashMap;

use crate::ffi::types;

use crate::core::{
    Compositor, CompositorConfig, CompositorEvent,
    Runtime,
    CompositorState,
};

use wayland_server::Resource;

// Re-export types for convenience
pub use crate::ffi::types::*;
pub use crate::ffi::errors::*;

// ============================================================================
// Main Compositor Object
// ============================================================================

/// Main compositor object exposed via FFI
/// 
/// This is the primary interface between platform code and the Rust compositor core.
/// Platform code creates an instance, starts the compositor, and processes events.
/// 
/// # Thread Safety
/// All methods are thread-safe and can be called from any thread.
#[derive(uniffi::Object)]
pub struct WawonaCore {
    /// Core compositor (manages Wayland display and clients)
    compositor: Mutex<Option<Compositor>>,
    
    /// Runtime (event loop and frame timing)
    runtime: Mutex<Runtime>,
    
    /// Compositor state (surfaces, windows, etc.)
    state: Arc<RwLock<CompositorState>>,
    
    /// Output configuration (cached for FFI access)
    output_size: RwLock<(u32, u32, f32)>,
    
    /// Force server-side decorations
    force_ssd: RwLock<bool>,
    
    /// FFI window info cache
    ffi_windows: RwLock<HashMap<u64, WindowInfo>>,
    
    /// FFI surface state cache
    ffi_surfaces: RwLock<HashMap<u32, SurfaceState>>,
    
    /// FFI client info cache
    ffi_clients: RwLock<HashMap<u32, ClientInfo>>,
    
    /// Texture cache (buffer_id -> texture_handle)
    textures: RwLock<HashMap<u64, TextureHandle>>,
    
    /// Keyboard configuration (rate Hz, delay ms)
    keyboard_config: RwLock<(i32, i32)>,
    
    /// Pending window events queue (for FFI polling)
    pending_window_events: RwLock<Vec<WindowEvent>>,
    
    /// Pending client events queue (for FFI polling)
    pending_client_events: RwLock<Vec<ClientEvent>>,
    
    /// Pending buffers to upload (platform pulls these)
    pending_buffers: RwLock<HashMap<types::WindowId, types::WindowBuffer>>,
    
    /// Pending redraw requests
    pending_redraws: RwLock<Vec<WindowId>>,
}

#[uniffi::export]
impl WawonaCore {
    // =========================================================================
    // Lifecycle
    // =========================================================================
    
    /// Create a new compositor instance
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        crate::wlog!(crate::util::logging::FFI, "Creating Wawona compositor (FFI)");
        
        Arc::new(Self {
            compositor: Mutex::new(None),
            runtime: Mutex::new(Runtime::new()),
            state: Arc::new(RwLock::new(CompositorState::new())),
            output_size: RwLock::new((1920, 1080, 1.0)),
            force_ssd: RwLock::new(false),
            ffi_windows: RwLock::new(HashMap::new()),
            ffi_surfaces: RwLock::new(HashMap::new()),
            ffi_clients: RwLock::new(HashMap::new()),
            textures: RwLock::new(HashMap::new()),
            keyboard_config: RwLock::new((33, 500)),
            pending_window_events: RwLock::new(Vec::new()),
            pending_client_events: RwLock::new(Vec::new()),
            pending_buffers: RwLock::new(HashMap::new()),
            pending_redraws: RwLock::new(Vec::new()),
        })
    }
    
    /// Start the compositor
    /// 
    /// # Arguments
    /// * `socket_name` - Optional Wayland socket name (defaults to "wayland-0")
    pub fn start(&self, socket_name: Option<String>) -> Result<()> {
        let mut compositor_guard = self.compositor.lock().unwrap();
        
        if compositor_guard.is_some() {
            return Err(CompositorError::AlreadyStarted);
        }
        
        let socket = socket_name.unwrap_or_else(|| "wayland-0".to_string());
        crate::wlog!(crate::util::logging::FFI, "Starting compositor on socket: {}", socket);
        
        // Create compositor configuration
        let (width, height, scale) = *self.output_size.read().unwrap();
        let (repeat_rate, repeat_delay) = *self.keyboard_config.read().unwrap();
        
        let config = CompositorConfig {
            socket_name: socket.clone(),
            force_ssd: *self.force_ssd.read().unwrap(),
            output_width: width,
            output_height: height,
            output_scale: scale,
            keyboard_repeat_rate: repeat_rate,
            keyboard_repeat_delay: repeat_delay,
        };
        
        // Create and start the compositor
        let mut compositor = Compositor::new(config.clone())
            .map_err(|e| CompositorError::initialization_failed(e.to_string()))?;
        
        // Synchronize output configuration into state
        let mut state = self.state.write().unwrap();
        state.update_primary_output(width, height, scale);
        
        // Synchronize Force SSD policy
        state.decoration_policy = if config.force_ssd {
            crate::core::state::DecorationPolicy::ForceServer
        } else {
            crate::core::state::DecorationPolicy::PreferClient
        };
        drop(state);
        
        compositor.start()
            .map_err(|e| CompositorError::initialization_failed(e.to_string()))?;
        
        *compositor_guard = Some(compositor);
        
        crate::wlog!(crate::util::logging::FFI, "Compositor started successfully");
        Ok(())
    }
    
    /// Set whether server-side decorations (SSD) should be forced
    pub fn set_force_ssd(&self, enabled: bool) {
        let mut state = self.state.write().unwrap();
        
        crate::wlog!(crate::util::logging::FFI, "FFI: set_force_ssd({})", enabled);
        
        // 1. Update policy
        state.decoration_policy = if enabled {
            crate::core::state::DecorationPolicy::ForceServer
        } else {
            crate::core::state::DecorationPolicy::PreferClient
        };
        
        // 2. Update cached state
        *self.force_ssd.write().unwrap() = enabled;
        
        // 3. Notify existing decorations if protocol is active
        use wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode;
        
        let target_mode = if enabled {
            Mode::ServerSide
        } else {
            Mode::ClientSide
        };
        
        // Collect existing decorations to trigger updates
        let mut decorations_to_configure = Vec::new();
        for decoration in state.decorations.values() {
            if let Some(res) = &decoration.resource {
                decorations_to_configure.push((res.clone(), decoration.window_id));
            }
        }
        
        crate::wlog!(crate::util::logging::FFI, "Updating {} active decorations to {:?}", decorations_to_configure.len(), target_mode);
        
        for (res, window_id) in decorations_to_configure {
            // Send the decoration mode configure
            res.configure(target_mode);
            
            // Update window decoration mode state
            if let Some(window) = state.get_window(window_id) {
                let mut window = window.write().unwrap();
                window.decoration_mode = if enabled {
                    crate::core::window::DecorationMode::ServerSide
                } else {
                    crate::core::window::DecorationMode::ClientSide
                };
            }
            
            // CRITICAL: Trigger a full configure sequence (toplevel + surface)
            // for the mode to take effect and for the client to resize!
            
            let mut surface_res = None;
            let mut toplevel_res = None;
            let mut internal_surface_id = 0;
            
            // Find toplevel and surface resources for this window
            for tl in state.xdg_toplevels.values() {
                if tl.window_id == window_id {
                    internal_surface_id = tl.surface_id;
                    toplevel_res = tl.resource.clone();
                    break;
                }
            }
            
            if internal_surface_id != 0 {
                if let Some(surf) = state.xdg_surfaces.get(&internal_surface_id) {
                    surface_res = surf.resource.clone();
                }
            }
            
            if let Some(tl) = toplevel_res {
                // Send current size or 0,0 to request re-layout
                // In Wawona, 0,0 usually tells client to decide
                tl.configure(0, 0, vec![]);
                
                if let Some(surf) = surface_res {
                    let serial = state.next_serial();
                    surf.configure(serial);
                    crate::wlog!(crate::util::logging::FFI, "Sent configure serial {} to window {} for SSD change", serial, window_id);
                }
            }
        }
    }
    
    /// Stop the compositor
    pub fn stop(&self) -> Result<()> {
        let mut compositor_guard = self.compositor.lock().unwrap();
        
        let compositor = compositor_guard.as_mut()
            .ok_or(CompositorError::NotStarted)?;
        
        compositor.stop()
            .map_err(|e| CompositorError::platform_error(e.to_string()))?;
        
        *compositor_guard = None;
        
        // Clear caches
        self.ffi_windows.write().unwrap().clear();
        self.ffi_surfaces.write().unwrap().clear();
        self.ffi_clients.write().unwrap().clear();
        self.textures.write().unwrap().clear();
        self.pending_window_events.write().unwrap().clear();
        self.pending_client_events.write().unwrap().clear();
        self.pending_buffers.write().unwrap().clear();
        self.pending_redraws.write().unwrap().clear();
        
        crate::wlog!(crate::util::logging::FFI, "Compositor stopped");
        Ok(())
    }
    
    /// Check if compositor is running
    pub fn is_running(&self) -> bool {
        self.compositor.lock().unwrap()
            .as_ref()
            .map(|c| c.is_running())
            .unwrap_or(false)
    }
    
    /// Get the Wayland socket path
    pub fn get_socket_path(&self) -> String {
        self.compositor.lock().unwrap()
            .as_ref()
            .map(|c| c.socket_path().to_string())
            .unwrap_or_default()
    }
    
    /// Get the Wayland socket name
    pub fn get_socket_name(&self) -> String {
        self.compositor.lock().unwrap()
            .as_ref()
            .map(|c| c.socket_name().to_string())
            .unwrap_or_default()
    }
    
    // =========================================================================
    // Socket Management
    // =========================================================================
    
    /// Add an additional Unix domain socket for connections
    pub fn add_unix_socket(&self, path: String) -> Result<()> {
        let mut compositor_guard = self.compositor.lock().unwrap();
        
        let compositor = compositor_guard.as_mut()
            .ok_or(CompositorError::NotStarted)?;
        
        compositor.add_unix_socket(&path)
            .map_err(|e| CompositorError::socket_error(e.to_string()))?;
        
        crate::wlog!(crate::util::logging::FFI, "Added Unix socket: {}", path);
        Ok(())
    }
    
    /// Add a vsock listener on the specified port
    pub fn add_vsock_listener(&self, port: u32) -> Result<()> {
        let mut compositor_guard = self.compositor.lock().unwrap();
        
        let compositor = compositor_guard.as_mut()
            .ok_or(CompositorError::NotStarted)?;
        
        compositor.add_vsock_listener(port)
            .map_err(|e| CompositorError::socket_error(e.to_string()))?;
        
        crate::wlog!(crate::util::logging::FFI, "Added vsock listener on port: {}", port);
        Ok(())
    }
    
    /// Remove a socket by its path or identifier
    pub fn remove_socket(&self, identifier: String) -> Result<()> {
        let mut compositor_guard = self.compositor.lock().unwrap();
        
        let compositor = compositor_guard.as_mut()
            .ok_or(CompositorError::NotStarted)?;
        
        compositor.remove_socket(&identifier)
            .map_err(|e| CompositorError::socket_error(e.to_string()))?;
        
        crate::wlog!(crate::util::logging::FFI, "Removed socket: {}", identifier);
        Ok(())
    }
    
    pub fn get_socket_paths(&self) -> Vec<String> {
        self.compositor.lock().unwrap()
            .as_ref()
            .map(|c| c.get_socket_paths())
            .unwrap_or_default()
    }
    

    
    // =========================================================================
    // Input Injection
    // =========================================================================

    /// Inject an input event into the compositor
    pub fn inject_input_event(&self, event: InputEvent) {
        let core_event = match event {
            InputEvent::PointerMotion { x, y, time_ms } => {
                crate::core::input::InputEvent::PointerMotion { x, y, time_ms }
            }
            InputEvent::PointerButton { button, state, time_ms } => {
                let core_state = match state {
                    ButtonState::Pressed => crate::core::input::KeyState::Pressed,
                    ButtonState::Released => crate::core::input::KeyState::Released,
                };
                crate::core::input::InputEvent::PointerButton { button, state: core_state, time_ms }
            }
            InputEvent::PointerAxis { horizontal, vertical, time_ms } => {
                crate::core::input::InputEvent::PointerAxis { horizontal, vertical, time_ms }
            }
            InputEvent::KeyboardKey { keycode, state, time_ms } => {
                let core_state = match state {
                    KeyState::Pressed => crate::core::input::KeyState::Pressed,
                    KeyState::Released => crate::core::input::KeyState::Released,
                };
                crate::core::input::InputEvent::KeyboardKey { keycode, state: core_state, time_ms }
            }
            InputEvent::KeyboardModifiers { depressed, latched, locked, group } => {
                crate::core::input::InputEvent::KeyboardModifiers { depressed, latched, locked, group }
            }
        };

        let mut state = self.state.write().unwrap();
        state.process_input_event(core_event);
    }
    
    // =========================================================================
    // Event Processing
    // =========================================================================
    
    /// Process pending Wayland events
    /// Returns true if events were processed
    pub fn process_events(&self) -> bool {
        let mut compositor_guard = self.compositor.lock().unwrap();
        let compositor = match compositor_guard.as_mut() {
            Some(c) => c,
            None => return false,
        };
        
        let mut runtime = self.runtime.lock().unwrap();
        
        // Collect events while holding the lock
        let events = {
            let mut state = self.state.write().unwrap();
            
            // Process events
            match runtime.poll(compositor, &mut state) {
                Ok(events) => events,
                Err(e) => {
                    crate::wlog!(crate::util::logging::FFI, "Event processing error: {}", e);
                    return false;
                }
            }
        }; // state lock released here
        
        // Drop the other locks too before handling events
        drop(runtime);
        drop(compositor_guard);
        
        // Handle events without holding any locks
        for event in events {
            self.handle_compositor_event(event);
        }
        true
    }
    
    /// Dispatch pending events with timeout (milliseconds)
    /// Returns true if events were processed
    pub fn dispatch_events(&self, timeout_ms: u32) -> bool {
        let mut compositor_guard = self.compositor.lock().unwrap();
        let compositor = match compositor_guard.as_mut() {
            Some(c) => c,
            None => return false,
        };
        
        let mut runtime = self.runtime.lock().unwrap();
        let timeout = std::time::Duration::from_millis(timeout_ms as u64);
        
        // Collect events while holding the lock
        let events = {
            let mut state = self.state.write().unwrap();
            
            match runtime.dispatch(compositor, &mut state, timeout) {
                Ok(events) => events,
                Err(e) => {
                    crate::wlog!(crate::util::logging::FFI, "Event dispatch error: {}", e);
                    return false;
                }
            }
        }; // state lock released here
        
        // Drop other locks before handling events
        drop(runtime);
        drop(compositor_guard);
        
        // Handle events without holding any locks
        for event in events {
            self.handle_compositor_event(event);
        }
        true
    }
    
    /// Flush client event queues
    pub fn flush_clients(&self) {
        if let Some(compositor) = self.compositor.lock().unwrap().as_mut() {
            let _ = compositor.flush();
        }
    }
}

// Internal methods (not exported via UniFFI)
impl WawonaCore {
    /// Get next serial number (for input event correlation)
    fn next_serial(&self) -> u32 {
        if let Some(compositor) = self.compositor.lock().unwrap().as_mut() {
            compositor.next_serial()
        } else {
            0
        }
    }
    
    /// Handle a compositor event (convert to FFI event)
    fn handle_compositor_event(&self, event: CompositorEvent) {
        match event {
            CompositorEvent::ClientConnected { client_id, pid } => {
                let client_info = ClientInfo {
                    id: ClientId { id: client_id },
                    pid: pid.unwrap_or(0),
                    name: None,
                    surface_count: 0,
                    window_count: 0,
                };
                self.ffi_clients.write().unwrap().insert(client_id, client_info);
                self.pending_client_events.write().unwrap().push(
                    ClientEvent::Connected { 
                        client_id: ClientId { id: client_id }, 
                        pid: pid.unwrap_or(0) 
                    }
                );
            }
            CompositorEvent::ClientDisconnected { client_id } => {
                self.ffi_clients.write().unwrap().remove(&client_id);
                self.pending_client_events.write().unwrap().push(
                    ClientEvent::Disconnected { 
                        client_id: ClientId { id: client_id } 
                    }
                );
            }
            CompositorEvent::WindowCreated { window_id, surface_id, title, width, height } => {
                let window_info = WindowInfo {
                    id: WindowId { id: window_id as u64 },
                    surface_id: SurfaceId { id: surface_id },
                    title: title.clone(),
                    app_id: String::new(),
                    width,
                    height,
                    decoration_mode: DecorationMode::ClientSide,
                    state: crate::ffi::types::WindowState::Normal,
                    activated: false,
                    resizing: false,
                };
                self.ffi_windows.write().unwrap().insert(window_id as u64, window_info.clone());
                
                let config = WindowConfig {
                    title,
                    app_id: String::new(),
                    width,
                    height,
                    min_width: None,
                    min_height: None,
                    max_width: None,
                    max_height: None,
                    decoration_mode: DecorationMode::ClientSide,
                    state: crate::ffi::types::WindowState::Normal,
                    parent: None,
                };
                self.pending_window_events.write().unwrap().push(
                    WindowEvent::Created { 
                        window_id: WindowId { id: window_id as u64 }, 
                        config 
                    }
                );

            }
            CompositorEvent::PopupCreated { window_id, surface_id: _, parent_id, x, y, width, height } => {
                let _config = WindowConfig {
                    title: String::new(),
                    app_id: String::new(),
                    width,
                    height,
                    min_width: None,
                    min_height: None,
                    max_width: None,
                    max_height: None,
                    decoration_mode: DecorationMode::ClientSide,
                    state: crate::ffi::types::WindowState::Normal,
                    parent: if parent_id > 0 { Some(WindowId::new(parent_id as u64)) } else { None },
                };
                
                self.pending_window_events.write().unwrap().push(
                    WindowEvent::PopupCreated { 
                        window_id: WindowId { id: window_id as u64 }, 
                        parent_id: WindowId { id: parent_id as u64 },
                        x, y,
                        width,
                        height
                    }
                );
            }
            CompositorEvent::PopupRepositioned { window_id, x, y, width, height } => {
                self.pending_window_events.write().unwrap().push(
                    WindowEvent::PopupRepositioned { 
                        window_id: WindowId { id: window_id as u64 }, 
                        x, y,
                        width,
                        height
                    }
                );
            }
            CompositorEvent::WindowDestroyed { window_id } => {
                self.ffi_windows.write().unwrap().remove(&(window_id as u64));
                self.pending_window_events.write().unwrap().push(
                    WindowEvent::Destroyed { 
                        window_id: WindowId { id: window_id as u64 } 
                    }
                );
            }
            CompositorEvent::WindowTitleChanged { window_id, title } => {
                if let Some(info) = self.ffi_windows.write().unwrap().get_mut(&(window_id as u64)) {
                    info.title = title.clone();
                }
                self.pending_window_events.write().unwrap().push(
                    WindowEvent::TitleChanged { 
                        window_id: WindowId { id: window_id as u64 }, 
                        title 
                    }
                );
            }
            CompositorEvent::WindowSizeChanged { window_id, width, height } => {
                if let Some(info) = self.ffi_windows.write().unwrap().get_mut(&(window_id as u64)) {
                    info.width = width;
                    info.height = height;
                }
                self.pending_window_events.write().unwrap().push(
                    WindowEvent::SizeChanged { 
                        window_id: WindowId { id: window_id as u64 }, 
                        width, 
                        height 
                    }
                );
            }
            CompositorEvent::WindowActivationRequested { window_id } => {
                self.pending_window_events.write().unwrap().push(
                    WindowEvent::Activated { 
                        window_id: WindowId { id: window_id as u64 } 
                    }
                );
            }
            CompositorEvent::WindowCloseRequested { window_id } => {
                self.pending_window_events.write().unwrap().push(
                    WindowEvent::CloseRequested { 
                        window_id: WindowId { id: window_id as u64 } 
                    }
                );
            }
            CompositorEvent::RedrawNeeded { window_id } => {
                self.pending_redraws.write().unwrap().push(
                    WindowId { id: window_id as u64 }
                );
            }
            CompositorEvent::SurfaceCommitted { surface_id, buffer_id } => {
                // Track commits per surface
                thread_local! {
                    static SURFACE_COMMITS: std::cell::RefCell<std::collections::HashMap<u32, u32>> = Default::default();
                }
                let commit_count = SURFACE_COMMITS.with(|commits| {
                    let mut map = commits.borrow_mut();
                    let count = map.entry(surface_id).or_insert(0);
                    *count += 1;
                    *count
                });
                
                crate::wlog!(crate::util::logging::FFI, "SurfaceCommitted surface={}, buffer_id={:?} (commit #{})", 
                    surface_id, buffer_id, commit_count);
                
                let buffer_id = if let Some(bid) = buffer_id {
                    bid as u32
                } else {
                    crate::wlog!(crate::util::logging::FFI, "FFI: SurfaceCommitted with no buffer_id");
                    return; // Exit this event handler early
                };
                let mut state = self.state.write().unwrap();
                
                // Try to get the buffer data - clone Arc first to avoid borrowing state
                let buffer = state.buffers.get(&buffer_id).cloned();
                crate::wlog!(crate::util::logging::FFI, "Buffer {} found: {}", 
                    buffer_id, buffer.is_some());
                
                // Check opaque region
                let is_opaque = if let Some(surface) = state.surfaces.get(&surface_id) {
                    let surface = surface.read().unwrap();
                    surface.current.opaque_region.as_ref().map(|r| !r.is_empty()).unwrap_or(false)
                } else {
                    false
                };

                
                let buffer_data = if let Some(buffer) = buffer {
                    let buffer = buffer.read().unwrap();
                    match &buffer.buffer_type {
                        crate::core::surface::BufferType::Shm(shm) => {
                            crate::wlog!(crate::util::logging::FFI, "SHM buffer {}x{}, pool={}, offset={}, fmt={}", 
                                shm.width, shm.height, shm.pool_id, shm.offset, shm.format);
                            // Find and map the pool
                            if let Some(pool) = state.shm_pools.get_mut(&shm.pool_id) {
                                if let Some(ptr) = pool.map() {
                                    let offset = shm.offset as usize;
                                    let size = (shm.height * shm.stride) as usize;
                                    
                                    // Safety: ptr is valid mmap'd memory from pool.fd of length pool.size
                                    // We need to ensure we don't read out of bounds
                                    if offset + size <= pool.size {
                                        let src_slice = unsafe {
                                            std::slice::from_raw_parts(ptr.add(offset), size)
                                        };
                                        

                                        
                                        // Handle formats
                                        // 0 = ARGB8888, 1 = XRGB8888
                                        let (format, needs_alpha_fix) = match shm.format {
                                            0 => (types::BufferFormat::Argb8888, is_opaque), // Force alpha if marked opaque!
                                            1 => (types::BufferFormat::Xrgb8888, true),      // Always force alpha for XRGB
                                            _ => (types::BufferFormat::Argb8888, is_opaque),
                                        };
                                        
                                        let mut pixels = src_slice.to_vec();
                                        


                                        // Fix alpha channel for XRGB8888 or Opaque ARGB (force 0xFF)
                                        if needs_alpha_fix {
                                            for chunk in pixels.chunks_exact_mut(4) {
                                                chunk[3] = 0xFF; // Force Alpha to opaque
                                            }
                                        }

                                        Some(types::BufferData::Shm {
                                            pixels,
                                            width: shm.width as u32,
                                            height: shm.height as u32,
                                            format, 
                                            stride: shm.stride as u32,
                                        })
                                    } else {
                                        crate::wlog!(crate::util::logging::FFI, "Buffer out of bounds: offset={} size={} pool_size={}", offset, size, pool.size);
                                        None
                                    }
                                } else {
                                    crate::wlog!(crate::util::logging::FFI, "Failed to map SHM pool {}", shm.pool_id);
                                    None
                                }
                            } else {
                                crate::wlog!(crate::util::logging::FFI, "SHM pool {} not found", shm.pool_id);
                                None
                            }
                        },
                        crate::core::surface::BufferType::Native(native) => {
                            crate::wlog!(crate::util::logging::FFI, "FFI: IOSurface buffer id={} {}x{}", 
                                native.id, native.width, native.height);
                            
                            Some(types::BufferData::Iosurface {
                                id: native.id as u32,
                                width: native.width as u32,
                                height: native.height as u32,
                                format: native.format,
                            })
                        },
                        _ => {
                            crate::wlog!(crate::util::logging::FFI, "FFI: Non-SHM buffer type, skipping");
                            None
                        }
                    }
                } else {
                    crate::wlog!(crate::util::logging::FFI, "FFI: Buffer {} not found in state.buffers", buffer_id);
                    None
                };
                
                if let Some(data) = buffer_data {
                    let mut target_window_id = state.surface_to_window.get(&surface_id).copied();
                    
                    // If no direct window mapping, check if it's a subsurface
                    if target_window_id.is_none() {
                        if let Some(subsurface) = state.get_subsurface(surface_id) {
                            let mut parent_id = subsurface.parent_id;
                            let mut path = format!("{}->{}", surface_id, parent_id);
                            
                            for _ in 0..10 { // Max depth
                                if let Some(wid) = state.surface_to_window.get(&parent_id) {
                                    crate::wlog!(crate::util::logging::FFI, "Resolved subsurface path: {} -> Window {}", path, wid);
                                    target_window_id = Some(*wid);
                                    break;
                                }
                                if let Some(parent_sub) = state.get_subsurface(parent_id) {
                                    parent_id = parent_sub.parent_id;
                                    path.push_str(&format!("->{}", parent_id));
                                } else {
                                    crate::wlog!(crate::util::logging::FFI, "Subsurface path dead end: {} (parent {} has no window)", path, parent_id);
                                    break;
                                }
                            }
                        }
                    }

                    // Notify redraw if associated with a window
                    if let Some(window_id) = target_window_id {
                        let win_id = types::WindowId { id: window_id as u64 };
                        crate::wlog!(crate::util::logging::FFI, "FFI: Queuing buffer for window {}", win_id.id);
                        
                        let mut pending = self.pending_buffers.write().unwrap();
                        let new_buffer = types::WindowBuffer {
                            window_id: win_id,
                            surface_id: types::SurfaceId { id: surface_id },
                            buffer: types::Buffer {
                                id: types::BufferId { id: buffer_id as u64 },
                                data
                            }
                        };
                        
                        if let Some(old_buffer) = pending.insert(win_id, new_buffer) {
                            // Only release if it's actually a DIFFERENT buffer
                            // This prevents premature release if the same buffer is committed multiple times
                            // before the UI thread has displayed it.
                            if old_buffer.buffer.id.id != buffer_id as u64 {
                                crate::wlog!(crate::util::logging::FFI, "Released superseded buffer {} for window {}", 
                                    old_buffer.buffer.id.id, win_id.id);
                                state.release_buffer(old_buffer.buffer.id.id as u32);
                            } else {
                                crate::wlog!(crate::util::logging::FFI, "Keeping reused buffer {} for window {}", 
                                    buffer_id, win_id.id);
                            }
                        }
                        
                        self.pending_redraws.write().unwrap().push(win_id);
                    } else {
                        crate::wlog!(crate::util::logging::FFI, "FFI: No window for surface {} in SurfaceCommitted", surface_id);
                    }
                }
                
                // Flush frame callbacks
                state.flush_frame_callbacks(surface_id, Some(crate::core::state::CompositorState::get_timestamp_ms()));
                crate::wlog!(crate::util::logging::FFI, "Flushed frame callbacks for surface {}", surface_id);
            }
            CompositorEvent::LayerSurfaceCommitted { surface_id, buffer_id } => {
                // Layer surface commit - TODO: Implement full layer surface rendering
                // For now, just flush frame callbacks so the client can continue rendering
                crate::wlog!(crate::util::logging::FFI, "LayerSurfaceCommitted surface={}, buffer_id={:?}", 
                    surface_id, buffer_id);
                
                let mut state = self.state.write().unwrap();
                
                // Release buffer immediately for now since we don't render layer surfaces yet
                // This prevents buffer exhaustion for wlroots clients
                if let Some(bid) = buffer_id {
                    state.release_buffer(bid as u32);
                }
                
                state.flush_frame_callbacks(surface_id, Some(crate::core::state::CompositorState::get_timestamp_ms()));
            }
        }
    }
}

#[uniffi::export]
impl WawonaCore {
    // =========================================================================
    // Platform Event Polling
    // =========================================================================
    
    /// Get pending window events (platform polls for these)
    pub fn poll_window_events(&self) -> Vec<WindowEvent> {
        std::mem::take(&mut *self.pending_window_events.write().unwrap())
    }
    
    /// Get pending client events (platform polls for these)
    pub fn poll_client_events(&self) -> Vec<ClientEvent> {
        std::mem::take(&mut *self.pending_client_events.write().unwrap())
    }
    
    /// Pop a single pending window event
    pub fn pop_window_event(&self) -> Option<WindowEvent> {
        let mut events = self.pending_window_events.write().unwrap();
        if events.is_empty() {
            None
        } else {
            Some(events.remove(0))
        }
    }
    
    /// Pop a single pending buffer (platform pulls these one by one)
    pub fn pop_pending_buffer(&self) -> Option<types::WindowBuffer> {
        let mut pending = self.pending_buffers.write().unwrap();
        let key = *pending.keys().next()?;
        pending.remove(&key)
    }

    /// Notify that a frame has been presented
    pub fn notify_frame_presented(&self, surface_id: SurfaceId, buffer_id: Option<BufferId>, timestamp: u32) {
        let mut state = self.state.write().unwrap();
        
        // Flush frame callbacks for this surface
        state.flush_frame_callbacks(surface_id.id, Some(timestamp));
        crate::wlog!(crate::util::logging::FFI, "Flushed frame callbacks for surface {}", 
            surface_id.id);
            
        // Release buffer if provided
        // Release buffer if provided
        if let Some(buf_id) = buffer_id {
            let buffer_id_u32 = buf_id.id as u32;
            state.release_buffer(buffer_id_u32);
            crate::wlog!(crate::util::logging::FFI, "Released buffer {}", buffer_id_u32);
        }
    }
    
    /// Get windows that need redraw
    pub fn poll_redraw_requests(&self) -> Vec<WindowId> {
        std::mem::take(&mut *self.pending_redraws.write().unwrap())
    }
    
    /// Notify that a buffer has been uploaded, providing the texture handle
    pub fn notify_buffer_uploaded(&self, buffer_id: BufferId, texture: TextureHandle) {
        self.textures.write().unwrap().insert(buffer_id.id, texture);
    }
    
    /// Notify that a texture has been released
    pub fn notify_texture_released(&self, texture: TextureHandle) {
        self.textures.write().unwrap().retain(|_, t| t.handle != texture.handle);
    }
    
    // =========================================================================
    // Window Management
    // =========================================================================

    /// Resize a window
    pub fn resize_window(&self, window_id: WindowId, width: u32, height: u32) {
        if !self.is_running() {
            return;
        }

        let mut state = self.state.write().unwrap();
        let wid = window_id.id as u32;

        // Update core window state
        if let Some(window) = state.get_window(wid) {
             let mut window = window.write().unwrap();
             window.width = width as i32;
             window.height = height as i32;
        }

        // Find associated surface
        let surface_id = state.surface_to_window.iter()
            .find(|(_, &w)| w == wid)
            .map(|(&s, _)| s);

        if let Some(sid) = surface_id {
             // Find toplevel data
             let toplevel_id = state.xdg_toplevels.iter()
                 .find(|(_, data)| data.surface_id == sid)
                 .map(|(&id, _)| id);
            
             if let Some(tid) = toplevel_id {
                 let scale = state.primary_output().scale;
                 if let Some(toplevel_data) = state.xdg_toplevels.get_mut(&tid) {
                     // Dedup: if size hasn't changed, don't spam configure
                     if toplevel_data.width == width && toplevel_data.height == height {
                         return;
                     }

                     toplevel_data.width = width;
                     toplevel_data.height = height;
                     
                     if let Some(resource) = &toplevel_data.resource {
                         // Send toplevel configure
                         let mut states: Vec<u8> = vec![]; 
                         
                         // Preserve activated state!
                         if toplevel_data.activated {
                             states.extend_from_slice(&((wayland_protocols::xdg::shell::server::xdg_toplevel::State::Activated as u32).to_ne_bytes()));
                         }
                         // TODO: handle maximized/fullscreen states

                         let logical_width = (width as f32 / scale) as i32;
                         let logical_height = (height as f32 / scale) as i32;
                         resource.configure(logical_width, logical_height, states);

                         // We must also send surface configure to commit the state
                         // Note: xdg_surfaces is keyed by xdg_surface's protocol_id, not wl_surface internal ID
                         // So we need to find the xdg_surface by its surface_id field
                         let xdg_surface_key = state.xdg_surfaces.iter()
                             .find(|(_, data)| data.surface_id == sid)
                             .map(|(&key, _)| key);
                         
                         if let Some(xdg_key) = xdg_surface_key {
                             if let Some(surface_data) = state.xdg_surfaces.get_mut(&xdg_key) {
                                 if let Some(surface_resource) = &surface_data.resource {
                                      // Need serial from compositor
                                      if let Some(compositor) = self.compositor.lock().unwrap().as_mut() {
                                          let serial = compositor.next_serial();
                                          surface_data.pending_serial = serial;
                                          surface_resource.configure(serial);
                                          // Use debug log instead of FFI log to reduce spam
                                          tracing::debug!("Sent configure to window {}: {}x{} serial={}", wid, width, height, serial);
                                      }
                                 }
                             }
                         }
                      }
                 }
             }
        }
    }

    /// Set window activation state
    pub fn set_window_activated(&self, window_id: WindowId, active: bool) {
        if !self.is_running() {
            return;
        }

        crate::wlog!(crate::util::logging::FFI, "Set window activation: window={} active={}", window_id.id, active);

        let mut state = self.state.write().unwrap();
        let wid = window_id.id as u32;

        // Update core window state
        if let Some(window) = state.get_window(wid) {
             let mut window = window.write().unwrap();
             window.activated = active;
        }

        // Find associated surface
        let surface_id = state.surface_to_window.iter()
            .find(|(_, &w)| w == wid)
            .map(|(&s, _)| s);

        if let Some(sid) = surface_id {
             // Find toplevel data
             let toplevel_id = state.xdg_toplevels.iter()
                 .find(|(_, data)| data.surface_id == sid)
                 .map(|(&id, _)| id);
            
             if let Some(tid) = toplevel_id {
                 let scale = state.primary_output().scale;
                 if let Some(toplevel_data) = state.xdg_toplevels.get_mut(&tid) {
                     toplevel_data.activated = active;
                     
                     if let Some(resource) = &toplevel_data.resource {
                         // Send toplevel configure with updated states
                         let mut states: Vec<u8> = vec![];
                         
                         // Add activated state if active
                         if active {
                             states.extend_from_slice(&((wayland_protocols::xdg::shell::server::xdg_toplevel::State::Activated as u32).to_ne_bytes()));
                         }
                         
                         // Add other states (maximized, fullscreen, resizing)
                         // TODO: Retrieve these from window state
                         if toplevel_data.width > 0 && toplevel_data.height > 0 {
                            let logical_width = (toplevel_data.width as f32 / scale) as i32;
                            let logical_height = (toplevel_data.height as f32 / scale) as i32;
                            resource.configure(logical_width, logical_height, states);
                         } else {
                            resource.configure(0, 0, states);
                         }

                         // We must also send surface configure to commit the state
                         if let Some(surface_data) = state.xdg_surfaces.get_mut(&sid) {
                             if let Some(surface_resource) = &surface_data.resource {
                                  // Need serial from compositor
                                  if let Some(compositor) = self.compositor.lock().unwrap().as_mut() {
                                      let serial = compositor.next_serial();
                                      surface_data.pending_serial = serial;
                                      surface_resource.configure(serial);
                                      crate::wlog!(crate::util::logging::FFI, "Sent configure (activation={}) to window {}", active, wid);
                                  }
                             }
                         }
                     }
                 }
             }
        }
    }

    // =========================================================================
    // Input Injection
    // =========================================================================
    
    /// Inject pointer motion event
    pub fn inject_pointer_motion(
        &self,
        _window_id: WindowId,
        x: f64,
        y: f64,
        timestamp_ms: u32,
    ) {
        if !self.is_running() {
            return;
        }
        
        let mut state = self.state.write().unwrap();
        // Ensure dead resources are cleaned up
        state.seat.cleanup_resources();
        
        // Update seat state
        state.seat.pointer_x = x;
        state.seat.pointer_y = y;
        state.seat.cursor_hotspot_x = x;
        state.seat.cursor_hotspot_y = y;
        
        let focused_client = state.focused_pointer_client();
        // Broadcast motion + frame event (required for clients to process atomically)
        state.seat.broadcast_pointer_motion(timestamp_ms, x, y, focused_client.as_ref());
        state.seat.broadcast_pointer_frame();
    }
    
    /// Inject pointer button event
    pub fn inject_pointer_button(
        &self,
        _window_id: WindowId,
        button: PointerButton,
        state: ButtonState,
        timestamp_ms: u32,
    ) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let wl_state = match state {
            ButtonState::Released => wayland_server::protocol::wl_pointer::ButtonState::Released,
            ButtonState::Pressed => wayland_server::protocol::wl_pointer::ButtonState::Pressed,
        };
        
        let button_code = match button {
            PointerButton::Left => 0x110,   // BTN_LEFT
            PointerButton::Right => 0x111,  // BTN_RIGHT
            PointerButton::Middle => 0x112, // BTN_MIDDLE
            PointerButton::Back => 0x116,   // BTN_BACK
            PointerButton::Forward => 0x115, // BTN_FORWARD
            PointerButton::Other(b) => b,
        };

        let mut state = self.state.write().unwrap();
        state.seat.cleanup_resources();
        
        // Update button count for implicit grab tracking
        match wl_state {
            wayland_server::protocol::wl_pointer::ButtonState::Pressed => {
                state.seat.pointer_button_count += 1;
            },
            wayland_server::protocol::wl_pointer::ButtonState::Released => {
                state.seat.pointer_button_count = state.seat.pointer_button_count.saturating_sub(1);
            },
            _ => {}
        }
        
        let focused_client = state.focused_pointer_client();
        // Broadcast button + frame event
        state.seat.broadcast_pointer_button(serial, timestamp_ms, button_code, wl_state, focused_client.as_ref());
        state.seat.broadcast_pointer_frame();
    }
    
    /// Inject pointer axis (scroll) event
    pub fn inject_pointer_axis(
        &self,
        _window_id: WindowId,
        _axis: PointerAxis,
        _value: f64,
        _discrete: i32,
        _source: AxisSource,
        _timestamp_ms: u32,
    ) {
        if !self.is_running() {
            return;
        }
        // TODO: Send wl_pointer::axis - skipping for now as SeatState helper not yet added for axis
    }
    
    /// Inject pointer frame event
    pub fn inject_pointer_frame(&self, _window_id: WindowId) {
        if !self.is_running() {
            return;
        }
        self.state.write().unwrap().seat.broadcast_pointer_frame();
    }
    
    /// Inject pointer enter event
    pub fn inject_pointer_enter(
        &self,
        window_id: WindowId,
        x: f64,
        y: f64,
        _timestamp_ms: u32,
    ) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let mut state = self.state.write().unwrap();
        
        // Find surface for window
        let surface_id = state.surface_to_window.iter()
            .find(|(_, &wid)| wid as u64 == window_id.id)
            .map(|(sid, _)| *sid);
            
        if let Some(sid) = surface_id {
            // Respect implicit grab: if buttons are pressed, don't change focus or send enter to others
            if state.seat.pointer_button_count > 0 {
                // If we are already focused on this surface, we might want to update position?
                // But generally `motion` handles that.
                // If we are focused on another surface (grab owner), we must NOT send enter here.
                return;
            }

            // Update pointer focus
            state.seat.pointer_focus = Some(sid);

            // Clone Arc to avoid borrowing state while mutating seat
            if let Some(surface) = state.surfaces.get(&sid).cloned() {
                 let surface = surface.read().unwrap();
                 if let Some(res) = &surface.resource {
                     // TODO: This uses the first resource bound to the surface, which is usually correct
                     // A more robust apporach would be needed for multi-resource surfaces
                     state.seat.broadcast_pointer_enter(serial, res, x, y);
                 }
            }
        }
    }
    
    /// Inject pointer leave event
    pub fn inject_pointer_leave(&self, window_id: WindowId, _timestamp_ms: u32) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let mut state = self.state.write().unwrap();
        
        let surface_id = state.surface_to_window.iter()
            .find(|(_, &wid)| wid as u64 == window_id.id)
            .map(|(sid, _)| *sid);
            
        if let Some(sid) = surface_id {
            // Respect implicit grab: if buttons are pressed, don't leave surface (it keeps focus)
            if state.seat.pointer_button_count > 0 {
                return;
            }

            // Clear pointer focus
            state.seat.pointer_focus = None;

            if let Some(surface) = state.surfaces.get(&sid).cloned() {
                 let surface = surface.read().unwrap();
                 if let Some(res) = &surface.resource {
                     state.seat.broadcast_pointer_leave(serial, res);
                 }
            }
        }
    }

    // ... (key injection methods also need similar fix) ...


    
    /// Inject keyboard key event
    pub fn inject_key(&self, keycode: u32, state: KeyState, timestamp_ms: u32) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let wl_state = match state {
            KeyState::Released => wayland_server::protocol::wl_keyboard::KeyState::Released,
            KeyState::Pressed => wayland_server::protocol::wl_keyboard::KeyState::Pressed,
        };
        
        let mut state = self.state.write().unwrap();
        state.seat.cleanup_resources();
        
        let focused_client = state.focused_keyboard_client();
        state.seat.broadcast_key(serial, timestamp_ms, keycode, wl_state, focused_client.as_ref());
    }
    
    /// Inject keyboard modifiers
    pub fn inject_modifiers(&self, modifiers: KeyboardModifiers) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let mut state = self.state.write().unwrap();
        state.seat.cleanup_resources();
        
        state.seat.mods_depressed = modifiers.mods_depressed;
        state.seat.mods_latched = modifiers.mods_latched;
        state.seat.mods_locked = modifiers.mods_locked;
        state.seat.mods_group = modifiers.group;
        
        let focused_client = state.focused_keyboard_client();
        state.seat.broadcast_modifiers(serial, modifiers.mods_depressed, modifiers.mods_latched, modifiers.mods_locked, modifiers.group, focused_client.as_ref());
    }
    
    /// Inject keyboard enter event
    pub fn inject_keyboard_enter(&self, window_id: WindowId, pressed_keys: Vec<u32>) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let mut state = self.state.write().unwrap();
        
        let surface_id = state.surface_to_window.iter()
            .find(|(_, &wid)| wid as u64 == window_id.id)
            .map(|(sid, _)| *sid);
            
        if let Some(sid) = surface_id {
            crate::wlog!(crate::util::logging::FFI, "Keyboard enter: window={}, surface={}", 
                window_id.id, sid);
            
            // DIAGNOSTIC: Log keyboard state
            crate::wlog!(crate::util::logging::FFI, "Keyboards available: {}", 
                state.seat.keyboards.len());
            for (idx, kbd) in state.seat.keyboards.iter().enumerate() {
                crate::wlog!(crate::util::logging::FFI, "  Keyboard {}: alive={}, version={}", 
                    idx, kbd.is_alive(), kbd.version());
            }
            
            if let Some(surface) = state.surfaces.get(&sid).cloned() {
                 let surface = surface.read().unwrap();
                 if let Some(res) = &surface.resource {
                     crate::wlog!(crate::util::logging::FFI, "Broadcasting keyboard enter to surface {} ({} keyboards bound)", 
                         sid, state.seat.keyboards.len());
                     state.seat.keyboard_focus = Some(sid);
                     state.seat.broadcast_keyboard_enter(serial, res, &pressed_keys);
                 } else {
                 crate::wlog!(crate::util::logging::FFI, "WARNING: Surface {} has no resource for keyboard enter", 
                     sid);
                 }
            } else {
                crate::wlog!(crate::util::logging::FFI, "WARNING: Surface {} not found for keyboard enter", 
                    sid);
            }
        } else {
            crate::wlog!(crate::util::logging::FFI, "WARNING: No surface found for window {} keyboard enter", 
                window_id.id);
        }
    }
    
    /// Inject keyboard leave event
    pub fn inject_keyboard_leave(&self, window_id: WindowId) {
        if !self.is_running() {
            return;
        }
        
        let serial = self.next_serial();
        let mut state = self.state.write().unwrap();
        
        let surface_id = state.surface_to_window.iter()
            .find(|(_, &wid)| wid as u64 == window_id.id)
            .map(|(sid, _)| *sid);
            
        if let Some(sid) = surface_id {
            if let Some(surface) = state.surfaces.get(&sid).cloned() {
                 let surface = surface.read().unwrap();
                 if let Some(res) = &surface.resource {
                     state.seat.broadcast_keyboard_leave(serial, res);
                 }
            }
        }
    }
    
    /// Inject touch down event
    pub fn inject_touch_down(
        &self,
        window_id: WindowId,
        touch_id: i32,
        x: f64,
        y: f64,
        _timestamp_ms: u32,
    ) -> Result<()> {
        if !self.is_running() {
            return Err(CompositorError::NotStarted);
        }
        
        let _serial = self.next_serial();
        crate::wlog!(crate::util::logging::INPUT, "Touch down: window={}, id={}, x={:.2}, y={:.2}", 
            window_id.id, touch_id, x, y);
        // TODO: Send wl_touch::down
        Ok(())
    }
    
    /// Inject touch up event
    pub fn inject_touch_up(&self, _touch_id: i32, _timestamp_ms: u32) -> Result<()> {
        if !self.is_running() {
            return Err(CompositorError::NotStarted);
        }
        
        let _serial = self.next_serial();
        // TODO: Send wl_touch::up
        Ok(())
    }
    
    /// Inject touch motion event
    pub fn inject_touch_motion(
        &self,
        _touch_id: i32,
        _x: f64,
        _y: f64,
        _timestamp_ms: u32,
    ) -> Result<()> {
        if !self.is_running() {
            return Err(CompositorError::NotStarted);
        }
        // TODO: Send wl_touch::motion
        Ok(())
    }
    
    /// Inject touch frame event
    pub fn inject_touch_frame(&self) {
        if !self.is_running() {
            return;
        }
        // TODO: Send wl_touch::frame
    }
    
    /// Inject touch cancel event
    pub fn inject_touch_cancel(&self) {
        if !self.is_running() {
            return;
        }
        // TODO: Send wl_touch::cancel
    }
    
    /// Inject gesture event
    pub fn inject_gesture(&self, gesture: GestureEvent) {
        if !self.is_running() {
            return;
        }
        
        crate::wlog!(crate::util::logging::INPUT, "Gesture: {:?} {:?} fingers={}", 
            gesture.gesture_type, gesture.state, gesture.finger_count);
        // TODO: Send pointer_gestures protocol events
    }
    
    // =========================================================================
    // Rendering
    // =========================================================================
    
    /// Get the current render scene
    pub fn get_render_scene(&self) -> RenderScene {
        if !self.is_running() {
            return RenderScene::empty();
        }
        
        let (width, height, scale) = *self.output_size.read().unwrap();
        
        // TODO: Build scene from compositor state
        let mut scene = RenderScene::new(width, height, scale);
        scene.needs_redraw = true;
        scene
    }
    
    /// Get render scene for a specific window
    pub fn get_window_render_scene(&self, window_id: WindowId) -> RenderScene {
        if !self.is_running() {
            return RenderScene::empty();
        }
        
        let windows = self.ffi_windows.read().unwrap();
        if let Some(info) = windows.get(&window_id.id) {
            let mut scene = RenderScene::new(info.width, info.height, 1.0);
            scene.needs_redraw = true;
            scene
        } else {
            RenderScene::empty()
        }
    }
    
    /// Notify compositor that frame rendering is complete
    pub fn notify_frame_complete(&self) {
        if !self.is_running() {
            return;
        }
        
        // Mark frame complete in runtime
        self.runtime.lock().unwrap().end_frame();
        
        // Flush frame callbacks
        self.state.write().unwrap().flush_all_frame_callbacks();
    }
    
    /// Notify frame complete for specific window
    pub fn notify_window_frame_complete(&self, window_id: WindowId) {
        if !self.is_running() {
            return;
        }
        
        crate::wlog!(crate::util::logging::FFI, "Window frame complete: window={}", window_id.id);
        
        // Find surfaces for this window and flush their callbacks
        let surface_id = {
            let state = self.state.read().unwrap();
            state.surface_to_window.iter()
                .find(|(_, &wid)| wid as u64 == window_id.id)
                .map(|(sid, _)| *sid)
        };
        
        if let Some(surface_id) = surface_id {
            self.state.write().unwrap().flush_frame_callbacks(surface_id, None);
        }
    }
    
    /// Flush frame callbacks immediately
    pub fn flush_frame_callbacks(&self) {
        if !self.is_running() {
            return;
        }
        self.state.write().unwrap().flush_all_frame_callbacks();
    }
    
    // =========================================================================
    // Configuration
    // =========================================================================
    
    /// Set output size and scale
    pub fn set_output_size(&self, width: u32, height: u32, scale: f32) {
        // FORCING SCALE TO 1.0 to fix Weston coordinate mismatch
        let forced_scale = 1.0;
        crate::wlog!(crate::util::logging::FFI, "Output size: {}x{} @ {}x (forced from {}x)", width, height, forced_scale, scale);
        *self.output_size.write().unwrap() = (width, height, forced_scale);
        
        // Update state
        {
            let mut state = self.state.write().unwrap();
            state.set_output_size(width, height, forced_scale);
            
            // Ensure physical dimensions are updated (assuming ~108 DPI / 4.25 pixels per mm for modern virtual displays)
            if let Some(output) = state.outputs.get_mut(0) {
                output.physical_width = (width as f32 / 4.25) as u32;
                output.physical_height = (height as f32 / 4.25) as u32;
            }
        }
        
        // TODO: Send ml_output::mode to clients
    }
    
    /// Configure output
    pub fn configure_output(&self, output: OutputInfo) {
        crate::wlog!(crate::util::logging::FFI, "Configure output: {}", output.name);
        // TODO: Register output with Wayland display
    }
    
    
    /// Set keyboard repeat rate
    pub fn set_keyboard_repeat(&self, rate: i32, delay: i32) {
        crate::wlog!(crate::util::logging::FFI, "Keyboard repeat: rate={} Hz, delay={} ms", rate, delay);
        *self.keyboard_config.write().unwrap() = (rate, delay);
        
        // Update state
        {
            let mut state = self.state.write().unwrap();
            state.keyboard_repeat_rate = rate;
            state.keyboard_repeat_delay = delay;
        }
        // TODO: Send wl_keyboard::repeat_info
    }
    
    // =========================================================================
    // Window Management
    // =========================================================================
    
    /// Get list of window IDs
    pub fn get_windows(&self) -> Vec<WindowId> {
        self.ffi_windows
            .read()
            .unwrap()
            .keys()
            .map(|id| WindowId::new(*id))
            .collect()
    }
    
    /// Get window info
    pub fn get_window_info(&self, window_id: WindowId) -> Option<WindowInfo> {
        self.ffi_windows.read().unwrap().get(&window_id.id).cloned()
    }
    
    /// Set window focus
    pub fn focus_window(&self, window_id: WindowId) {
        if !self.is_running() {
            return;
        }
        
        crate::wlog!(crate::util::logging::FFI, "Focus window: {}", window_id.id);
        
        // Update state
        self.state.write().unwrap().set_focused_window(Some(window_id.id as u32));
        
        // Update FFI window info
        {
            let mut windows = self.ffi_windows.write().unwrap();
            // Deactivate all windows first
            for (_, info) in windows.iter_mut() {
                info.activated = false;
            }
            // Activate the focused window
            if let Some(info) = windows.get_mut(&window_id.id) {
                info.activated = true;
            }
        }
        
        self.pending_window_events.write().unwrap().push(
            WindowEvent::Activated { window_id }
        );
    }
    
    /// Unfocus all windows
    pub fn unfocus_all(&self) {
        if !self.is_running() {
            return;
        }
        
        crate::wlog!(crate::util::logging::FFI, "Unfocus all windows");
        
        // Update state
        self.state.write().unwrap().set_focused_window(None);
        
        // Deactivate all windows
        let mut windows = self.ffi_windows.write().unwrap();
        for (id, info) in windows.iter_mut() {
            if info.activated {
                info.activated = false;
                self.pending_window_events.write().unwrap().push(
                    WindowEvent::Deactivated { window_id: WindowId::new(*id) }
                );
            }
        }
    }
    
    /// Request window close
    pub fn request_window_close(&self, window_id: WindowId) {
        if !self.is_running() {
            return;
        }
        crate::wlog!(crate::util::logging::FFI, "Request window close: {}", window_id.id);
        // TODO: Send xdg_toplevel::close
    }
    
    /// Start interactive move
    pub fn start_window_move(&self, window_id: WindowId, serial: u32) {
        if !self.is_running() {
            return;
        }
        crate::wlog!(crate::util::logging::FFI, "Start window move: window={}, serial={}", window_id.id, serial);
        
        self.pending_window_events.write().unwrap().push(
            WindowEvent::MoveRequested { window_id, serial }
        );
    }
    
    /// Start interactive resize
    pub fn start_window_resize(&self, window_id: WindowId, serial: u32, edge: ResizeEdge) {
        if !self.is_running() {
            return;
        }
        crate::wlog!(crate::util::logging::FFI, "Start window resize: window={}, serial={}, edge={:?}", 
            window_id.id, serial, edge);
        
        self.pending_window_events.write().unwrap().push(
            WindowEvent::ResizeRequested { window_id, serial, edge }
        );
    }
    
    // =========================================================================
    // Client Management
    // =========================================================================
    
    /// Get connected client count
    pub fn get_client_count(&self) -> u32 {
        self.compositor.lock().unwrap()
            .as_ref()
            .map(|c| c.client_count() as u32)
            .unwrap_or(0)
    }
    
    /// Get list of connected clients
    pub fn get_clients(&self) -> Vec<ClientInfo> {
        self.ffi_clients.read().unwrap().values().cloned().collect()
    }
    
    /// Disconnect a client
    pub fn disconnect_client(&self, client_id: ClientId) {
        if !self.is_running() {
            return;
        }
        crate::wlog!(crate::util::logging::FFI, "Disconnect client: {}", client_id.id);
        // TODO: Disconnect client from Wayland display
        
        self.ffi_clients.write().unwrap().remove(&client_id.id);
        self.pending_client_events.write().unwrap().push(
            ClientEvent::Disconnected { client_id }
        );
    }
    
    // =========================================================================
    // Surface Management
    // =========================================================================
    
    /// Get surface state
    pub fn get_surface_state(&self, surface_id: SurfaceId) -> Option<SurfaceState> {
        self.ffi_surfaces.read().unwrap().get(&surface_id.id).cloned()
    }
    
    // =========================================================================
    // Debug/IPC
    // =========================================================================
    
    /// Execute debug command
    pub fn execute_debug_command(&self, command: DebugCommand) -> String {
        match command {
            DebugCommand::DumpState => {
                let (width, height, scale) = *self.output_size.read().unwrap();
                let state = self.state.read().unwrap();
                format!(
                    "Compositor State:\n\
                     Running: {}\n\
                     Socket: {}\n\
                     Output: {}x{} @ {}x\n\
                     Windows: {}\n\
                     Surfaces: {}\n\
                     Clients: {}\n\
                     Focused: {:?}",
                    self.is_running(),
                    self.get_socket_name(),
                    width, height, scale,
                    state.windows.len(),
                    state.surfaces.len(),
                    self.get_client_count(),
                    state.focus.keyboard_focus
                )
            }
            DebugCommand::DumpSurfaces => {
                let state = self.state.read().unwrap();
                let mut output = format!("Surfaces ({}):\n", state.surfaces.len());
                for (id, surface) in state.surfaces.iter() {
                    let s = surface.read().unwrap();
                    output.push_str(&format!(
                        "  Surface {}: size={}x{}\n",
                        id, s.current.width, s.current.height
                    ));
                }
                output
            }
            DebugCommand::DumpWindows => {
                let state = self.state.read().unwrap();
                let mut output = format!("Windows ({}):\n", state.windows.len());
                for (id, window) in state.windows.iter() {
                    let w = window.read().unwrap();
                    output.push_str(&format!(
                        "  Window {}: title=\"{}\", size={}x{}\n",
                        id, w.title, w.width, w.height
                    ));
                }
                output
            }
            DebugCommand::DumpClients => {
                let clients = self.ffi_clients.read().unwrap();
                let mut output = format!("Clients ({}):\n", clients.len());
                for (id, info) in clients.iter() {
                    output.push_str(&format!(
                        "  Client {}: pid={}, surfaces={}, windows={}\n",
                        id, info.pid, info.surface_count, info.window_count
                    ));
                }
                output
            }
            DebugCommand::SetLogLevel { level } => {
                crate::wlog!(crate::util::logging::MAIN, "Set log level: {}", level);
                format!("Log level set to: {}", level)
            }
            DebugCommand::ForceRedraw => {
                let windows = self.ffi_windows.read().unwrap();
                let window_ids: Vec<WindowId> = windows.keys().map(|id| WindowId::new(*id)).collect();
                let count = window_ids.len();
                self.pending_redraws.write().unwrap().extend(window_ids);
                self.runtime.lock().unwrap().request_redraw();
                format!("Forced redraw for {} windows", count)
            }
        }
    }
    
    /// Get compositor statistics
    pub fn get_stats(&self) -> String {
        let (width, height, scale) = *self.output_size.read().unwrap();
        let (rate, delay) = *self.keyboard_config.read().unwrap();
        let fps = self.runtime.lock().unwrap().fps();
        
        format!(
            "Wawona Compositor Statistics\n\
             ============================\n\
             Version: {}\n\
             Running: {}\n\
             Socket: {}\n\
             FPS: {:.1}\n\
             \n\
             Output:\n\
               Size: {}x{}\n\
               Scale: {}\n\
             \n\
             Input:\n\
               Keyboard repeat: {} Hz, {} ms delay\n\
             \n\
             Objects:\n\
               Windows: {}\n\
               Surfaces: {}\n\
               Clients: {}\n\
               Textures: {}",
            version(),
            self.is_running(),
            self.get_socket_name(),
            fps,
            width, height,
            scale,
            rate, delay,
            self.ffi_windows.read().unwrap().len(),
            self.ffi_surfaces.read().unwrap().len(),
            self.get_client_count(),
            self.textures.read().unwrap().len(),
        )
    }
}

// ============================================================================
// Free Functions
// ============================================================================

/// Get library version
#[uniffi::export]
pub fn version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// Get build information
#[uniffi::export]
pub fn build_info() -> String {
    format!(
        "Wawona Compositor v{}\n\
         Built with Rust {}\n\
         Target: {}",
        env!("CARGO_PKG_VERSION"),
        "1.75+",
        std::env::consts::ARCH,
    )
}

// Note: UniFFI scaffolding is generated in lib.rs
