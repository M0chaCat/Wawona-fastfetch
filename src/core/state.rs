//! Global compositor state.
//!
//! This module contains the `CompositorState` struct which holds all the
//! "business logic" state of the compositor, separate from the Wayland
//! protocol mechanics or the platform UI.
//!
//! The state is designed to be:
//! - Thread-safe (accessed via Arc<RwLock<CompositorState>>)
//! - Serializable for debugging
//! - Decoupled from Wayland protocol types where possible

use std::collections::HashMap;
use std::sync::{Arc, RwLock};
use std::time::Instant;

use wayland_server::Resource;

use wayland_server::protocol::wl_callback::WlCallback;
use wayland_server::backend::{ClientData, ClientId, DisconnectReason};



use crate::core::surface::Surface;
use crate::core::window::{Window, DecorationMode};
use crate::core::window::tree::WindowTree;
use crate::core::window::focus::FocusManager;

use crate::core::compositor::CompositorEvent;

use wayland_protocols::xdg::shell::server::{
    xdg_surface, xdg_toplevel, xdg_wm_base,
};

use crate::core::wayland::presentation_time::PresentationFeedback;

// ============================================================================
// Subsurface State
// ============================================================================

/// Subsurface tracking information
#[derive(Debug, Clone)]
pub struct SubsurfaceState {
    /// Surface ID of the subsurface
    pub surface_id: u32,
    /// Parent surface ID
    pub parent_id: u32,
    /// Position relative to parent
    pub position: (i32, i32),
    /// Pending position (before commit)
    pub pending_position: (i32, i32),
    /// Whether in synchronized mode
    pub sync: bool,
    /// Z-order relative to siblings (higher = on top)
    pub z_order: i32,
}

// ============================================================================
// SHM Pool State (for buffer pixel access)
// ============================================================================

use std::os::unix::io::{AsRawFd, OwnedFd};

/// Shared memory pool for SHM buffer pixel data
pub struct ShmPool {
    /// File descriptor for the pool (owned - keeps fd alive!)
    pub fd: OwnedFd,
    /// Size of the pool in bytes
    pub size: usize,
    /// mmap'd data pointer (None until first access)
    pub data: Option<*mut u8>,
}

impl ShmPool {
    /// Create a new SHM pool from file descriptor
    pub fn new(fd: OwnedFd, size: i32) -> Self {
        Self {
            fd,  // Store the OwnedFd directly to keep it alive
            size: size as usize,
            data: None,
        }
    }
    
    /// mmap the pool and return pointer to data
    pub fn map(&mut self) -> Option<*mut u8> {
        if self.data.is_some() {
            return self.data;
        }
        
        // SAFETY: mmap the file descriptor
        unsafe {
            let ptr = libc::mmap(
                std::ptr::null_mut(),
                self.size,
                libc::PROT_READ,
                libc::MAP_SHARED,
                self.fd.as_raw_fd(),  // Use .as_raw_fd() on the stored OwnedFd
                0,
            );
            
            if ptr == libc::MAP_FAILED {
                tracing::error!("Failed to mmap SHM pool (fd={}, size={})", self.fd.as_raw_fd(), self.size);
                return None;
            }
            
            self.data = Some(ptr as *mut u8);
            self.data
        }
    }
}

impl Drop for ShmPool {
    fn drop(&mut self) {
        if let Some(ptr) = self.data {
            unsafe {
                libc::munmap(ptr as *mut libc::c_void, self.size);
            }
        }
    }
}

// Safety: ShmPool manages an mmap region. We wrap access with RwLock in state.
unsafe impl Send for ShmPool {}
unsafe impl Sync for ShmPool {}

// ============================================================================
// Layer Shell State
// ============================================================================

/// Layer surface state (wlr-layer-shell-unstable-v1)
#[derive(Debug, Clone)]
pub struct LayerSurface {
    /// Associated surface ID
    pub surface_id: u32,
    /// Associated output ID
    pub output_id: u32,
    /// Layer (background, bottom, top, overlay)
    pub layer: u32,
    /// Namespace
    pub namespace: String,
    /// Anchor edges
    pub anchor: u32,
    /// Margin (top, right, bottom, left)
    pub margin: (i32, i32, i32, i32),
    /// Exclusive zone
    pub exclusive_zone: i32,
    /// Keyboard interactivity
    pub interactivity: u32,
    /// Desired width
    pub width: u32,
    /// Desired height
    pub height: u32,
    /// Whether initial configure was acked
    pub configured: bool,
    /// Pending configure serial
    pub pending_serial: u32,
}

impl LayerSurface {
    pub fn new(surface_id: u32, output_id: u32, layer: u32, namespace: String) -> Self {
        Self {
            surface_id,
            output_id,
            layer,
            namespace,
            anchor: 0,
            margin: (0, 0, 0, 0),
            exclusive_zone: 0,
            interactivity: 0,
            width: 0,
            height: 0,
            configured: false,
            pending_serial: 0,
        }
    }
}

// ============================================================================
// DMABUF Export State
// ============================================================================

/// State for a DMABUF export frame
#[derive(Debug, Clone)]
pub struct DmabufExportFrame {
    /// Associated output ID
    pub output_id: u32,
    /// Whether cursor should be overlaid
    pub overlay_cursor: bool,
    /// Frame metadata (width, height, etc.) - populated when frame is ready
    pub width: u32,
    pub height: u32,
    pub format: u32,
    pub num_objects: u32,
}

impl DmabufExportFrame {
    pub fn new(output_id: u32, overlay_cursor: bool) -> Self {
        Self {
            output_id,
            overlay_cursor,
            width: 0,
            height: 0,
            format: 0,
            num_objects: 0,
        }
    }
}

/// Data stored with DMA-BUF buffer params
#[derive(Debug, Clone, Default)]
pub struct DmabufBufferParamsData {
    pub width: u32,
    pub height: u32,
    pub format: u32, // DRM fourcc format
    pub flags: u32,
    pub fds: Vec<i32>,
    pub offsets: Vec<u32>,
    pub strides: Vec<u32>,
    pub modifiers: Vec<u64>,
}

impl DmabufBufferParamsData {
    pub fn new() -> Self {
        Self::default()
    }
}



/// Data stored with each relative pointer
#[derive(Debug, Clone)]
pub struct RelativePointerData {
    /// Associated wl_pointer
    pub pointer_id: u32,
}

/// Constraint lifetime
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConstraintLifetime {
    /// Constraint is persistent until explicitly destroyed
    Persistent,
    /// Constraint deactivates when pointer leaves surface
    /// Constraint deactivates when pointer leaves surface
    Oneshot,
}

// ============================================================================
// Protocol Data Types
// ============================================================================

/// Data stored with each viewport
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

/// Data stored with activation token
#[derive(Debug, Clone)]
pub struct ActivationTokenData {
    pub token: String,
    pub app_id: Option<String>,
    pub serial: Option<u32>,
    pub surface_id: Option<u32>,
}

impl Default for ActivationTokenData {
    fn default() -> Self {
        use std::time::{SystemTime, UNIX_EPOCH};
        let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap().as_nanos();
        let token = format!("wawona-{:x}", now);
        Self {
            token,
            app_id: None,
            serial: None,
            surface_id: None,
        }
    }
}

/// Data stored with exported toplevel
#[derive(Debug, Clone)]
pub struct ExportedToplevelData {
    pub toplevel_id: u32,
    pub handle: String,
}

/// Data stored with imported toplevel
#[derive(Debug, Clone)]
pub struct ImportedToplevelData {
    pub handle: String,
}

/// Data stored with each xdg_output
#[derive(Debug, Clone)]
pub struct XdgOutputData {
    pub output_id: u32,
}

impl XdgOutputData {
    pub fn new(output_id: u32) -> Self {
        Self { output_id }
    }
}

use wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::ZxdgToplevelDecorationV1;

/// Data stored with each toplevel decoration
#[derive(Debug, Clone)]
pub struct ToplevelDecorationData {
    pub window_id: u32,
    pub mode: wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode,
    pub resource: Option<ZxdgToplevelDecorationV1>,
}

impl ToplevelDecorationData {
    pub fn new(window_id: u32, resource: Option<ZxdgToplevelDecorationV1>) -> Self {
        Self {
            window_id,
            mode: wayland_protocols::xdg::decoration::zv1::server::zxdg_toplevel_decoration_v1::Mode::ClientSide,
            resource,
        }
    }
}

unsafe impl Send for ToplevelDecorationData {}
unsafe impl Sync for ToplevelDecorationData {}



// ============================================================================
// XDG Shell Data Types
// ============================================================================

/// Data stored with each xdg_surface
#[derive(Debug, Clone)]
pub struct XdgSurfaceData {
    /// The underlying wl_surface ID
    pub surface_id: u32,
    /// Associated window ID (if toplevel)
    pub window_id: Option<u32>,
    /// Serial number for configuration
    pub pending_serial: u32,
    /// Whether initial configure was acked
    pub configured: bool,
    /// The actual protocol resource
    pub resource: Option<xdg_surface::XdgSurface>,
}

impl XdgSurfaceData {
    pub fn new(surface_id: u32) -> Self {
        Self {
            surface_id,
            window_id: None,
            pending_serial: 0,
            configured: false,
            resource: None,
        }
    }
}

unsafe impl Send for XdgSurfaceData {}
unsafe impl Sync for XdgSurfaceData {}

/// Data stored with each xdg_toplevel
#[derive(Debug, Clone)]
pub struct XdgToplevelData {
    /// Associated window ID
    pub window_id: u32,
    /// Associated surface ID
    pub surface_id: u32,
    /// Title
    pub title: String,
    /// App ID
    pub app_id: String,
    /// Parent toplevel (if any)
    pub parent: Option<u32>,
    /// Current width
    pub width: u32,
    /// Current height
    pub height: u32,
    /// Pending configure serial
    pub pending_serial: u32,
    /// Activation state
    pub activated: bool,
    /// The actual protocol resource
    pub resource: Option<xdg_toplevel::XdgToplevel>,
}

impl XdgToplevelData {
    pub fn new(window_id: u32, surface_id: u32) -> Self {
        Self {
            window_id,
            surface_id,
            title: String::new(),
            app_id: String::new(),
            parent: None,
            width: 0,
            height: 0,
            pending_serial: 0,
            activated: false,
            resource: None,
        }
    }
}

unsafe impl Send for XdgToplevelData {}
unsafe impl Sync for XdgToplevelData {}

/// Data stored with each xdg_popup
#[derive(Debug, Clone)]
pub struct XdgPopupData {
    pub surface_id: u32,
    pub window_id: u32,
    pub parent_id: Option<u32>,
    pub geometry: (i32, i32, i32, i32), // x, y, width, height
    pub anchor_rect: (i32, i32, i32, i32),
    pub grabbed: bool,
    pub repositioned_token: Option<u32>,
}

unsafe impl Send for XdgPopupData {}
unsafe impl Sync for XdgPopupData {}

/// Data stored with each xdg_positioner
#[derive(Debug, Clone, Copy)]
pub struct XdgPositionerData {
    pub width: i32,
    pub height: i32,
    pub anchor_rect: (i32, i32, i32, i32),
    pub anchor: u32, // xdg_positioner::Anchor
    pub gravity: u32, // xdg_positioner::Gravity
    pub constraint_adjustment: u32, // xdg_positioner::ConstraintAdjustment
    pub offset: (i32, i32),
}

impl Default for XdgPositionerData {
    fn default() -> Self {
        Self {
            width: 0,
            height: 0,
            anchor_rect: (0, 0, 0, 0),
            anchor: 0,
            gravity: 0,
            constraint_adjustment: 0,
            offset: (0, 0),
        }
    }
}

// ============================================================================
// Subcompositor Data Types
// ============================================================================

/// Per-subsurface data
#[derive(Debug, Clone)]
pub struct SubsurfaceData {
    /// The parent surface ID this subsurface is attached to
    pub parent_id: u32,
    /// Position relative to parent (pending)
    pub pending_position: (i32, i32),
    /// Position relative to parent (committed)
    pub position: (i32, i32),
    /// Whether this subsurface is in synchronized mode
    pub sync: bool,
}

impl SubsurfaceData {
    pub fn new(parent_id: u32) -> Self {
        Self {
            parent_id,
            pending_position: (0, 0),
            position: (0, 0),
            sync: true, // Default is synchronized mode
        }
    }
}
/// Data stored with data source
#[derive(Debug, Clone)]
pub struct DataSourceData {
    pub mime_types: Vec<String>,
    pub dnd_actions: wayland_server::protocol::wl_data_device_manager::DndAction,
}

impl Default for DataSourceData {
    fn default() -> Self {
        Self {
            mime_types: Vec::new(),
            dnd_actions: wayland_server::protocol::wl_data_device_manager::DndAction::empty(),
        }
    }
}

impl DataSourceData {
    pub fn new() -> Self {
        Self::default()
    }
}

#[derive(Debug, Clone)]
pub struct DataOfferData {
    pub source_id: Option<u32>,
    pub mime_types: Vec<String>,
}

#[derive(Debug, Clone)]
pub struct DataDeviceData {
    pub seat_id: u32,
}

/// Data stored with locked pointer
#[derive(Debug, Clone)]
pub struct LockedPointerData {
    pub surface_id: u32,
    pub pointer_id: u32,
    pub lifetime: ConstraintLifetime,
    pub active: bool,
}

/// Data stored with confined pointer
#[derive(Debug, Clone)]
pub struct ConfinedPointerData {
    pub surface_id: u32,
    pub pointer_id: u32,
    pub lifetime: ConstraintLifetime,
    pub active: bool,
}

// ============================================================================
// Virtual Pointer State
// ============================================================================

/// State for a virtual pointer device
#[derive(Debug, Clone)]
pub struct VirtualPointerState {
    /// Associated seat name
    pub seat_name: Option<String>,
    /// Associated output ID (for absolute motion)
    pub output_id: Option<u32>,
}

impl VirtualPointerState {
    pub fn new(seat_name: Option<String>, output_id: Option<u32>) -> Self {
        Self { seat_name, output_id }
    }
}

// ============================================================================
// Virtual Keyboard State
// ============================================================================

/// State for a virtual keyboard device
#[derive(Debug, Clone)]
pub struct VirtualKeyboardState {
    /// Associated seat name
    pub seat_name: Option<String>,
}

impl VirtualKeyboardState {
    pub fn new(seat_name: Option<String>) -> Self {
        Self { seat_name }
    }
}

// ============================================================================
// Client State
// ============================================================================

/// Data stored with each Wayland client
#[derive(Default, Clone)]
pub struct ClientState {
    /// Client identifier
    pub id: Option<u32>,
}

impl ClientData for ClientState {
    fn initialized(&self, client_id: ClientId) {
        tracing::info!("Client initialized: {:?}", client_id);
    }
    
    fn disconnected(&self, client_id: ClientId, reason: DisconnectReason) {
        let reason_str = match reason {
            DisconnectReason::ConnectionClosed => "connection closed",
            DisconnectReason::ProtocolError(_) => "protocol error",
        };
        tracing::info!("Client disconnected: {:?} ({})", client_id, reason_str);
    }
}

// ============================================================================
// Output State
// ============================================================================

/// Output (display/monitor) state
#[derive(Debug, Clone)]
pub struct OutputMode {
    pub width: u32,
    pub height: u32,
    pub refresh: u32,
    pub preferred: bool,
}

/// Output (display/monitor) state
#[derive(Debug, Clone)]
pub struct OutputState {
    /// Output identifier
    pub id: u32,
    /// Output name
    pub name: String,
    /// Description
    pub description: String,
    /// Manufacturer
    pub make: String,
    /// Model
    pub model: String,
    /// Serial number
    pub serial_number: String,
    /// Position X
    pub x: i32,
    /// Position Y
    pub y: i32,
    /// Physical width in mm
    pub physical_width: u32,
    /// Physical height in mm
    pub physical_height: u32,
    /// Current width in pixels
    pub width: u32,
    /// Current height in pixels
    pub height: u32,
    /// Refresh rate in mHz
    pub refresh: u32,
    /// Scale factor
    pub scale: f32,
    /// List of modes
    pub modes: Vec<OutputMode>,
    /// Power mode (0 = off, 1 = on)
    pub power_mode: u32,
}

impl OutputState {
    pub fn new(id: u32, name: String, width: u32, height: u32) -> Self {
        let mode = OutputMode {
            width,
            height,
            refresh: 60000,
            preferred: true,
        };
        Self {
            id,
            name: name.clone(),
            description: format!("Virtual Display {}", name),
            make: "Wawona".to_string(),
            model: "Virtual".to_string(),
            serial_number: format!("WAW-{}", id),
            x: 0,
            y: 0,
            // Calculate physical dimensions assuming ~96 DPI for defaults
            // 96 DPI = ~3.78 pixels/mm
            physical_width: (width as f32 / 3.78) as u32,
            physical_height: (height as f32 / 3.78) as u32,
            width,
            height,
            refresh: 60000, // 60Hz
            scale: 1.0,
            modes: vec![mode],
            power_mode: 1, // Default to ON
        }
    }

    pub fn update(&mut self, width: u32, height: u32, scale: f32) {
        self.width = width;
        self.height = height;
        self.scale = scale;
        // 96 DPI = ~3.78 pixels/mm
        self.physical_width = (width as f32 / 3.78) as u32;
        self.physical_height = (height as f32 / 3.78) as u32;
        
        // Update or add mode
        if let Some(mode) = self.modes.get_mut(0) {
            mode.width = width;
            mode.height = height;
        } else {
            self.modes.push(OutputMode {
                width,
                height,
                refresh: 60000,
                preferred: true,
            });
        }
    }
}

impl Default for OutputState {
    fn default() -> Self {
        Self::new(0, "default".to_string(), 1920, 1080)
    }
}

// ============================================================================
// Seat State
// ============================================================================

// ============================================================================
// Seat Resources Tracking
// ============================================================================

use wayland_server::protocol::{wl_pointer, wl_keyboard, wl_touch};

use crate::core::wayland::wlroots::wlr_data_control_unstable_v1::{
    zwlr_data_control_source_v1,
};

/// Collection of seat resources bound by clients
#[derive(Debug, Clone, Default)]
pub struct SeatState {
    /// Seat name
    pub name: String,
    /// Pointer focus surface
    pub pointer_focus: Option<u32>,
    /// Pointer position
    pub pointer_x: f64,
    pub pointer_y: f64,
    /// Number of pointer buttons currently pressed (for implicit grab)
    pub pointer_button_count: u32,
    /// Keyboard focus surface
    pub keyboard_focus: Option<u32>,
    /// Pressed keys
    pub pressed_keys: Vec<u32>,
    /// Modifier state
    pub mods_depressed: u32,
    pub mods_latched: u32,
    pub mods_locked: u32,
    pub mods_group: u32,
    /// Cursor surface ID
    pub cursor_surface: Option<u32>,
    /// Cursor hotspot
    pub cursor_hotspot_x: f64,
    pub cursor_hotspot_y: f64,
    /// Bound resources
    pub pointers: Vec<wl_pointer::WlPointer>,
    pub keyboards: Vec<wl_keyboard::WlKeyboard>,
    pub touches: Vec<wl_touch::WlTouch>,
}

impl SeatState {
    pub fn new(name: &str) -> Self {
        Self {
            name: name.to_string(),
            ..Default::default()
        }
    }

    /// Add a pointer resource
    pub fn add_pointer(&mut self, pointer: wl_pointer::WlPointer) {
        self.pointers.push(pointer);
    }

    /// Add a keyboard resource
    pub fn add_keyboard(&mut self, keyboard: wl_keyboard::WlKeyboard) {
        self.keyboards.push(keyboard);
    }

    /// Add a touch resource
    pub fn add_touch(&mut self, touch: wl_touch::WlTouch) {
        self.touches.push(touch);
    }

    /// Clean up dead resources
    pub fn cleanup_resources(&mut self) {
        let before_pointers = self.pointers.len();
        let before_keyboards = self.keyboards.len();
        let before_touches = self.touches.len();
        
        self.pointers.retain(|p| p.is_alive());
        // FIXED: Don't aggressively clean up keyboards - they're being incorrectly marked as dead
        // Keyboards will be cleaned up when clients disconnect
        // self.keyboards.retain(|k| k.is_alive());
        self.touches.retain(|t| t.is_alive());
        
        if before_keyboards != self.keyboards.len() {
            crate::wlog!(crate::util::logging::SEAT, 
                "Cleanup removed {} dead keyboards ({} -> {})", 
                before_keyboards - self.keyboards.len(),
                before_keyboards, 
                self.keyboards.len());
        }
        if before_pointers != self.pointers.len() {
            crate::wlog!(crate::util::logging::SEAT, 
                "Cleanup removed {} dead pointers", 
                before_pointers - self.pointers.len());
        }
        if before_touches != self.touches.len() {
            crate::wlog!(crate::util::logging::SEAT, 
                "Cleanup removed {} dead touches", 
                before_touches - self.touches.len());
        }
    }

    /// Broadcast pointer motion event
    pub fn broadcast_pointer_motion(&mut self, time: u32, x: f64, y: f64, focused_client: Option<&wayland_server::Client>) {
        if let Some(focused) = focused_client {
            for ptr in &self.pointers {
                if ptr.client().as_ref() == Some(focused) {
                    ptr.motion(time, x, y);
                }
            }
        }
    }

    /// Broadcast pointer button event
    pub fn broadcast_pointer_button(&mut self, serial: u32, time: u32, button: u32, state: wl_pointer::ButtonState, focused_client: Option<&wayland_server::Client>) {
        if let Some(focused) = focused_client {
            for ptr in &self.pointers {
                if ptr.client().as_ref() == Some(focused) {
                    ptr.button(serial, time, button, state);
                }
            }
        }
    }

    /// Broadcast pointer enter event
    pub fn broadcast_pointer_enter(&mut self, serial: u32, surface: &wayland_server::protocol::wl_surface::WlSurface, x: f64, y: f64) {
        let client = surface.client();
        for ptr in &self.pointers {
            if ptr.client() == client {
                ptr.enter(serial, surface, x, y);
            }
        }
    }

    /// Broadcast pointer leave event
    pub fn broadcast_pointer_leave(&mut self, serial: u32, surface: &wayland_server::protocol::wl_surface::WlSurface) {
        let client = surface.client();
        for ptr in &self.pointers {
            if ptr.client() == client {
                ptr.leave(serial, surface);
            }
        }
    }

    /// Broadcast pointer frame event
    pub fn broadcast_pointer_frame(&mut self) {
        for ptr in &self.pointers {
            ptr.frame();
        }
    }

    /// Broadcast keyboard key event
    pub fn broadcast_key(&mut self, serial: u32, time: u32, key: u32, state: wl_keyboard::KeyState, focused_client: Option<&wayland_server::Client>) {
        for kbd in &self.keyboards {
            if focused_client.is_none() || kbd.client().as_ref() == focused_client {
                kbd.key(serial, time, key, state);
            }
        }
    }

    /// Broadcast keyboard modifiers event
    pub fn broadcast_modifiers(&mut self, serial: u32, depressed: u32, latched: u32, locked: u32, group: u32, focused_client: Option<&wayland_server::Client>) {
        for kbd in &self.keyboards {
            if focused_client.is_none() || kbd.client().as_ref() == focused_client {
                kbd.modifiers(serial, depressed, latched, locked, group);
            }
        }
    }

    /// Broadcast keyboard enter event
    // FORCE REBUILD: 2026-01-19 keyboard.modifiers() fix
    /// Broadcast keyboard enter event
    pub fn broadcast_keyboard_enter(&mut self, serial: u32, surface: &wayland_server::protocol::wl_surface::WlSurface, keys: &[u32]) {
        let client = surface.client();
        // Prepare keys array with proper endianness
        let keys_bytes = keys.iter().flat_map(|k| k.to_ne_bytes().to_vec()).collect::<Vec<u8>>();
        for kbd in &self.keyboards {
            if kbd.client() == client {
                kbd.enter(serial, surface, keys_bytes.clone());
                
                // CRITICAL: Wayland protocol requires sending modifiers after enter
                kbd.modifiers(
                    serial,
                    self.mods_depressed,
                    self.mods_latched,
                    self.mods_locked,
                    self.mods_group,
                );
                
                // Send repeat info (version 4+)
                if kbd.version() >= 4 {
                    kbd.repeat_info(33, 500); // 33 Hz, 500ms delay
                }
            }
        }
    }

    /// Broadcast keyboard leave event
    pub fn broadcast_keyboard_leave(&mut self, serial: u32, surface: &wayland_server::protocol::wl_surface::WlSurface) {
        let client = surface.client();
        for kbd in &self.keyboards {
            if kbd.client() == client {
                kbd.leave(serial, surface);
            }
        }
    }
}

// ============================================================================
// Focus State
// ============================================================================



// ============================================================================
// Frame Callback State
// ============================================================================

/// Pending frame callback
#[derive(Debug)]
pub struct PendingFrameCallback {
    /// Surface ID
    pub surface_id: u32,
    /// Wayland callback object
    pub callback: WlCallback,
    /// Queued time
    pub queued_at: Instant,
}

// ============================================================================
// Decoration State
// ============================================================================

/// Global decoration policy
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecorationPolicy {
    /// Prefer client-side decorations
    PreferClient,
    /// Prefer server-side decorations
    PreferServer,
    /// Force server-side decorations
    ForceServer,
}

impl Default for DecorationPolicy {
    fn default() -> Self {
        Self::PreferClient
    }
}

// ============================================================================
// Main Compositor State
// ============================================================================

/// Global compositor state.
///
/// This struct holds all the "business logic" state of the compositor,
/// separate from the Wayland protocol machinations or the platform UI.
pub struct CompositorState {
    // =========================================================================
    // Core State
    // =========================================================================
    
    /// Connected clients
    pub clients: HashMap<wayland_server::backend::ClientId, ClientState>,

    /// All active surfaces, keyed by their Wayland object ID.
    pub surfaces: HashMap<u32, Arc<RwLock<Surface>>>,
    
    /// All active windows (Toplevels), keyed by their ID.
    pub windows: HashMap<u32, Arc<RwLock<Window>>>,
    
    /// Surface ID to Window ID mapping
    pub surface_to_window: HashMap<u32, u32>,
    
    /// Subsurface registry, keyed by subsurface's surface ID
    pub subsurfaces: HashMap<u32, SubsurfaceState>,
    
    /// Parent to children mapping for subsurface hierarchy
    pub subsurface_children: HashMap<u32, Vec<u32>>,
    
    /// All active layer surfaces, keyed by surface ID
    pub layer_surfaces: HashMap<u32, Arc<RwLock<LayerSurface>>>,
    
    /// Surface ID to layer surface ID mapping (for buffer handling)
    pub surface_to_layer: HashMap<u32, u32>,
    
    /// Protocol surface ID to internal surface ID mapping
    /// This maps the client's protocol object ID to our internal surface ID
    pub protocol_to_internal_surface: HashMap<u32, u32>,
    
    /// All active buffers, keyed by their Wayland object ID.
    pub buffers: HashMap<u32, Arc<RwLock<crate::core::surface::Buffer>>>,

    /// Bound wl_buffer resources (for sending release events)

    
    // =========================================================================
    // Focus & Input State
    // =========================================================================
    
    /// Focus manager
    pub focus: FocusManager,
    
    /// Window tree
    pub window_tree: WindowTree,
    
    /// Primary seat state
    pub seat: SeatState,
    
    // =========================================================================
    // Output State
    // =========================================================================
    
    /// Output states
    pub outputs: Vec<OutputState>,
    
    /// Primary output index
    pub primary_output: usize,
    
    // =========================================================================
    // Frame Callbacks
    // =========================================================================
    
    /// Pending frame callbacks per surface.
    pub frame_callbacks: HashMap<u32, Vec<WlCallback>>,
    
    // =========================================================================
    // Configuration
    // =========================================================================
    
    /// Decoration policy
    pub decoration_policy: DecorationPolicy,
    
    /// Keyboard repeat rate (Hz)
    pub keyboard_repeat_rate: i32,
    
    /// Keyboard repeat delay (ms)
    pub keyboard_repeat_delay: i32,
    
    // =========================================================================
    // ID Generators
    // =========================================================================
    
    /// Next surface ID
    next_surface_id: u32,
    
    /// Next window ID
    next_window_id: u32,
    
    /// Serial counter for Wayland events
    serial: u32,
    
    /// Presentation sequence counter
    presentation_seq: u64,
    
    /// Pending presentation feedbacks
    pub presentation_feedbacks: Vec<PresentationFeedback>,
    
    /// Active idle inhibitors (inhibitor_id -> surface_id)
    pub idle_inhibitors: HashMap<u32, u32>,
    
    /// Next idle inhibitor ID
    next_inhibitor_id: u32,
    
    /// Active keyboard shortcuts inhibitors (surface_id -> seat_id)
    pub keyboard_shortcuts_inhibitors: HashMap<u32, u32>,
    
    /// Last output manager config serial
    pub last_output_manager_serial: u32,
    
    /// Active DMABUF export frames (resource_id -> frame_state)
    pub export_dmabuf_frames: HashMap<u32, DmabufExportFrame>,
    
    /// Pending DMA-BUF params (params_id -> params_data)
    pub pending_dmabuf_params: HashMap<u32, DmabufBufferParamsData>,
    
    /// Surface synchronization objects (sync_id -> surface_id)
    pub surface_sync_states: HashMap<u32, u32>,

    /// DRM Syncobj surfaces (syncobj_surface_id -> surface_id)
    pub syncobj_surfaces: HashMap<u32, u32>,
    
    /// DRM Syncobj timelines (timeline_id -> file_descriptor)
    pub syncobj_timelines: HashMap<u32, Option<i32>>,
    
    /// Active xdg_wm_base resources (for pinging)
    pub xdg_shell_resources: HashMap<u32, xdg_wm_base::XdgWmBase>,

    /// DRM Lease connectors (connector_resource_id -> connector_id)
    pub lease_connectors: HashMap<u32, u32>,
    
    /// Relative pointer data (relative_pointer_id -> pointer_id)
    pub relative_pointers: HashMap<u32, u32>,
    
    /// Locked pointer data (locked_pointer_id -> data)
    pub locked_pointers: HashMap<u32, LockedPointerData>,
    
    /// Confined pointer data (confined_pointer_id -> data)
    pub confined_pointers: HashMap<u32, ConfinedPointerData>,
    
    /// Viewports (viewport_id -> data)
    pub viewports: HashMap<u32, ViewportData>,
    
    /// Activation tokens (token_id -> data)
    pub activation_tokens: HashMap<u32, ActivationTokenData>,
    
    /// Exported toplevels (exported_id -> data)
    pub exported_toplevels: HashMap<u32, ExportedToplevelData>,
    
    /// Imported toplevels (imported_id -> data)
    pub imported_toplevels: HashMap<u32, ImportedToplevelData>,
    
    /// XDG outputs (xdg_output_id -> data)
    pub xdg_outputs: HashMap<u32, XdgOutputData>,
    
    /// Toplevel decorations (decoration_id -> data)
    pub decorations: HashMap<u32, ToplevelDecorationData>,
    
    /// Data sources (source_id -> data)
    pub data_sources: HashMap<u32, DataSourceData>,
    
    /// Data offers (offer_id -> data)
    pub data_offers: HashMap<u32, DataOfferData>,
    
    /// Data devices (device_id -> data)
    pub data_devices: HashMap<u32, DataDeviceData>,
    
    /// Active virtual pointers (resource_id -> pointer_state)
    pub virtual_pointers: HashMap<u32, VirtualPointerState>,
    
    /// Active virtual keyboards (resource_id -> keyboard_state)
    pub virtual_keyboards: HashMap<u32, VirtualKeyboardState>,
    
    /// Global selection source (data control)
    pub selection_source: Option<zwlr_data_control_source_v1::ZwlrDataControlSourceV1>,
    /// Global primary selection source (data control)
    pub primary_selection_source: Option<zwlr_data_control_source_v1::ZwlrDataControlSourceV1>,

    // =========================================================================
    // Protocol-Specific State
    // =========================================================================

    /// Mapping of xdg_surface IDs to their data
    pub xdg_surfaces: HashMap<u32, XdgSurfaceData>,
    
    /// Mapping of xdg_toplevel IDs to their data
    pub xdg_toplevels: HashMap<u32, XdgToplevelData>,
    
    /// Mapping of xdg_popup IDs to their data
    pub xdg_popups: HashMap<u32, XdgPopupData>,

    /// Mapping of xdg_positioner IDs to their data
    pub xdg_positioners: HashMap<u32, XdgPositionerData>,
    
    /// Bound wl_output resources
    pub output_resources: HashMap<wayland_server::backend::ObjectId, wayland_server::protocol::wl_output::WlOutput>,
    
    /// Bound wl_seat resources
    pub seat_resources: HashMap<u32, wayland_server::protocol::wl_seat::WlSeat>,
    
    /// Pending compositor events (pushed by protocol handlers)
    pub pending_compositor_events: Vec<CompositorEvent>,
    
    /// SHM pools for buffer pixel access (pool_id -> pool)
    pub shm_pools: HashMap<u32, ShmPool>,

    /// Regions for wl_region (region_id -> list of rects)
    pub regions: HashMap<u32, Vec<crate::core::surface::damage::DamageRegion>>,
}

impl CompositorState {
    pub fn new() -> Self {
        Self {
            clients: HashMap::new(),
            surfaces: HashMap::new(),
            windows: HashMap::new(),
            surface_to_window: HashMap::new(),
            subsurfaces: HashMap::new(),
            subsurface_children: HashMap::new(),
            focus: FocusManager::new(),
            window_tree: WindowTree::new(),
            seat: SeatState::new("seat0"),
            outputs: vec![OutputState::default()],
            primary_output: 0,
            frame_callbacks: HashMap::new(),
            decoration_policy: DecorationPolicy::default(),
            keyboard_repeat_rate: 33,
            keyboard_repeat_delay: 500,
            next_surface_id: 1,
            next_window_id: 1,
            serial: 1,
            presentation_seq: 1,
            presentation_feedbacks: Vec::new(),
            idle_inhibitors: HashMap::new(),
            next_inhibitor_id: 1,
            keyboard_shortcuts_inhibitors: HashMap::new(),
            layer_surfaces: HashMap::new(),
            surface_to_layer: HashMap::new(),
            protocol_to_internal_surface: HashMap::new(),
            last_output_manager_serial: 1,
            export_dmabuf_frames: HashMap::new(),
            pending_dmabuf_params: HashMap::new(),
            surface_sync_states: HashMap::new(),
            syncobj_surfaces: HashMap::new(),
            syncobj_timelines: HashMap::new(),
            lease_connectors: HashMap::new(),
            relative_pointers: HashMap::new(),
            locked_pointers: HashMap::new(),
            confined_pointers: HashMap::new(),
            viewports: HashMap::new(),
            activation_tokens: HashMap::new(),
            exported_toplevels: HashMap::new(),
            imported_toplevels: HashMap::new(),
            xdg_outputs: HashMap::new(),
            xdg_shell_resources: HashMap::new(),
            decorations: HashMap::new(),
            data_sources: HashMap::new(),
            data_offers: HashMap::new(),
            data_devices: HashMap::new(),
            xdg_surfaces: HashMap::new(),
            xdg_toplevels: HashMap::new(),
            xdg_popups: HashMap::new(),
            xdg_positioners: HashMap::new(),
            output_resources: HashMap::new(),
            seat_resources: HashMap::new(),
            virtual_pointers: HashMap::new(),
            virtual_keyboards: HashMap::new(),
            selection_source: None,
            primary_selection_source: None,
            buffers: HashMap::new(),
            // buffer_resources removed
            pending_compositor_events: Vec::new(),
            shm_pools: HashMap::new(),
            regions: HashMap::new(),
        }
    }
    

    
    // =========================================================================
    // Surface Management
    // =========================================================================
    
    /// Generate next surface ID
    pub fn next_surface_id(&mut self) -> u32 {
        let id = self.next_surface_id;
        self.next_surface_id += 1;
        id
    }
    
    /// Add a surface
    pub fn add_surface(&mut self, surface: Surface) -> u32 {
        let id = surface.id;
        self.surfaces.insert(id, Arc::new(RwLock::new(surface)));
        tracing::debug!("Added surface {}", id);
        id
    }
    
    /// Remove a surface
    pub fn remove_surface(&mut self, surface_id: u32) {
        self.surfaces.remove(&surface_id);
        self.frame_callbacks.remove(&surface_id);
        
        // Update focus if needed
        if self.focus.grabbed_surface == Some(surface_id) {
            self.focus.grabbed_surface = None;
        }
        
        tracing::debug!("Removed surface {}", surface_id);
    }
    
    /// Get a surface
    pub fn get_surface(&self, surface_id: u32) -> Option<Arc<RwLock<Surface>>> {
        self.surfaces.get(&surface_id).cloned()
    }
    
    // =========================================================================
    // Window Management
    // =========================================================================
    
    /// Generate next window ID
    pub fn next_window_id(&mut self) -> u32 {
        let id = self.next_window_id;
        self.next_window_id += 1;
        id
    }
    
    /// Generate next serial for Wayland events
    pub fn next_serial(&mut self) -> u32 {
        let serial = self.serial;
        self.serial = self.serial.wrapping_add(1);
        serial
    }

    // =========================================================================
    // Input Injection
    // =========================================================================

    /// Inject a key event and broadcast to all bound keyboards
    pub fn inject_key(&mut self, key: u32, key_state: wl_keyboard::KeyState, time: u32) {
        let serial = self.next_serial();
        self.seat.cleanup_resources();
        for keyboard in &self.seat.keyboards {
            keyboard.key(serial, time, key, key_state);
        }
    }

    /// Inject modifier state and broadcast to all bound keyboards
    pub fn inject_modifiers(&mut self, depressed: u32, latched: u32, locked: u32, group: u32) {
        let serial = self.next_serial();
        self.seat.cleanup_resources();
        for keyboard in &self.seat.keyboards {
            keyboard.modifiers(serial, depressed, latched, locked, group);
        }
    }

    /// Inject relative pointer motion and broadcast to all bound pointers
    pub fn inject_pointer_motion_relative(&mut self, dx: f64, dy: f64, time: u32) {
        self.seat.pointer_x += dx;
        self.seat.pointer_y += dy;
        self.seat.cleanup_resources();
        for pointer in &self.seat.pointers {
            pointer.motion(time, self.seat.pointer_x, self.seat.pointer_y);
        }
    }

    /// Inject absolute pointer motion and broadcast to all bound pointers
    pub fn inject_pointer_motion_absolute(&mut self, x: f64, y: f64, _time: u32) {
        self.seat.pointer_x = x;
        self.seat.pointer_y = y;
        self.seat.cleanup_resources();
        for pointer in &self.seat.pointers {
            pointer.motion(_time, x, y);
        }
    }

    /// Inject a pointer button event and broadcast to all bound pointers
    pub fn inject_pointer_button(&mut self, button: u32, state: wl_pointer::ButtonState, time: u32) {
        let serial = self.next_serial();
        self.seat.cleanup_resources();
        for pointer in &self.seat.pointers {
            pointer.button(serial, time, button, state);
        }
    }

    /// Flush pending pointer events (send frame event)
    pub fn flush_pointer_events(&mut self) {
        self.seat.cleanup_resources();
        for pointer in &self.seat.pointers {
            pointer.frame();
        }
    }
    
    /// Add a window
    /// Add a window (Legacy - delegating to register_window)
    pub fn add_window(&mut self, window: Window) -> u32 {
        let surface_id = window.surface_id;
        self.register_window(surface_id, window)
    }
    
    /// Remove a window (Delegating to destroy_window)
    pub fn remove_window(&mut self, window_id: u32) {
        self.destroy_window(window_id);
    }
    
    // get_window is already defined below, removing this duplicate
    
    /// Get window for surface
    pub fn get_window_for_surface(&self, surface_id: u32) -> Option<Arc<RwLock<Window>>> {
        self.get_window_by_surface(surface_id)
    }
    
    /// Get all window IDs
    pub fn window_ids(&self) -> Vec<u32> {
        self.windows.keys().copied().collect()
    }
    
    // =========================================================================
    // Focus Management
    // =========================================================================
    
    /// Set focused window
    pub fn set_focused_window(&mut self, window_id: Option<u32>) {
        self.focus.set_keyboard_focus(window_id);
        
        // Update keyboard focus to the window's surface
        if let Some(wid) = window_id {
            if let Some(window) = self.windows.get(&wid) {
                let window = window.read().unwrap();
                self.seat.keyboard_focus = Some(window.surface_id);
            }
        } else {
            self.seat.keyboard_focus = None;
        }
        
        tracing::debug!("Focus changed to window: {:?}", window_id);
    }

    /// Get the client of the currently focused keyboard surface
    pub fn focused_keyboard_client(&self) -> Option<wayland_server::Client> {
        self.seat.keyboard_focus.and_then(|sid| {
            self.surfaces.get(&sid).and_then(|surf| {
                surf.read().unwrap().resource.as_ref().and_then(|res| res.client())
            })
        })
    }

    /// Get the client of the currently focused pointer surface
    pub fn focused_pointer_client(&self) -> Option<wayland_server::Client> {
        self.seat.pointer_focus.and_then(|sid| {
            self.surfaces.get(&sid).and_then(|surf| {
                surf.read().unwrap().resource.as_ref().and_then(|res| res.client())
            })
        })
    }
    
    /// Get focused window
    pub fn focused_window(&self) -> Option<u32> {
        self.focus.keyboard_focus
    }

    // =========================================================================
    // Input Processing
    // =========================================================================

    /// Process a raw input event from the platform/FFI
    pub fn process_input_event(&mut self, event: crate::core::input::InputEvent) {
        use crate::core::input::InputEvent;
        use wayland_server::protocol::wl_pointer::ButtonState;
        use wayland_server::protocol::wl_keyboard::KeyState;

        match event {
            InputEvent::PointerMotion { x, y, time_ms } => {
                self.seat.pointer_x = x;
                self.seat.pointer_y = y;

                // Hit test
                let window_info = {
                     let under = self.window_tree.window_under(x, y, &self.windows);
                     if let Some(wid) = under {
                         if let Some(window) = self.windows.get(&wid) {
                             let w = window.read().unwrap();
                             Some((wid, w.surface_id, w.geometry()))
                         } else {
                             None
                         }
                     } else {
                         None
                     }
                };
                
                // Update focus if needed
                if let Some((_window_id, surface_id, win_geo)) = window_info {
                        // Check if focus changed
                        if self.seat.pointer_focus != Some(surface_id) {
                            // Leave old surface
                            if let Some(old_focus) = self.seat.pointer_focus {
                                let old_resource = if let Some(surf) = self.surfaces.get(&old_focus) {
                                     let surf = surf.read().unwrap();
                                     surf.resource.clone()
                                } else {
                                    None
                                };

                                if let Some(res) = old_resource {
                                    self.serial += 1;
                                    let serial = self.serial;
                                    self.seat.broadcast_pointer_leave(serial, &res);
                                }
                            }
                            
                            // Enter new surface
                            let new_resource = if let Some(surf) = self.surfaces.get(&surface_id) {
                                let surf = surf.read().unwrap();
                                surf.resource.clone()
                            } else {
                                None
                            };

                            if let Some(res) = new_resource {
                                // Calculate local coordinates
                                let lx = x - win_geo.x as f64;
                                let ly = y - win_geo.y as f64;
                                
                                self.serial += 1;
                                let serial = self.serial;
                                self.seat.broadcast_pointer_enter(serial, &res, lx, ly);
                            }
                            
                            self.seat.pointer_focus = Some(surface_id);
                        }
                        
                        // Send motion event
                         let lx = x - win_geo.x as f64;
                         let ly = y - win_geo.y as f64;
                         
                         // Get client for focused pointer (inlined, no closure)
                         let client = if let Some(sid) = self.seat.pointer_focus {
                            if let Some(surf) = self.surfaces.get(&sid) {
                                surf.read().unwrap().resource.as_ref().and_then(|res| res.client())
                            } else {
                                None
                            }
                         } else {
                             None
                         };
                         
                         self.seat.broadcast_pointer_motion(time_ms, lx, ly, client.as_ref());

                } else {
                    // Pointer moves to void
                     if let Some(old_focus) = self.seat.pointer_focus {
                        let old_resource = if let Some(surf) = self.surfaces.get(&old_focus) {
                             let surf = surf.read().unwrap();
                             surf.resource.clone()
                        } else {
                            None
                        };

                        if let Some(res) = old_resource {
                             self.serial += 1;
                             let serial = self.serial;
                             self.seat.broadcast_pointer_leave(serial, &res);
                        }
                    }
                    self.seat.pointer_focus = None;
                }
            }
            InputEvent::PointerButton { button, state, time_ms } => {
                let wl_state = if state == crate::core::input::KeyState::Pressed {
                    ButtonState::Pressed
                } else {
                    ButtonState::Released
                };
                
                // Click-to-focus logic
                if wl_state == ButtonState::Pressed {
                    let window_under = self.window_tree.window_under(self.seat.pointer_x, self.seat.pointer_y, &self.windows);
                    if let Some(window_id) = window_under {
                        self.set_focused_window(Some(window_id));
                        self.window_tree.bring_to_front(window_id);
                    }
                }

                let client = if let Some(sid) = self.seat.pointer_focus {
                    if let Some(surf) = self.surfaces.get(&sid) {
                        surf.read().unwrap().resource.as_ref().and_then(|res| res.client())
                    } else {
                        None
                    }
                } else {
                    None
                };

                self.serial += 1;
                let serial = self.serial;
                self.seat.broadcast_pointer_button(serial, time_ms, button, wl_state, client.as_ref());
            }
            InputEvent::PointerAxis { horizontal: _, vertical: _, time_ms: _ } => {
                // TODO: Axis
            }
            InputEvent::KeyboardKey { keycode, state, time_ms } => {
                 let wl_state = if state == crate::core::input::KeyState::Pressed {
                    KeyState::Pressed
                } else {
                    KeyState::Released
                };
                
                let client = if let Some(sid) = self.seat.keyboard_focus {
                    if let Some(surf) = self.surfaces.get(&sid) {
                        surf.read().unwrap().resource.as_ref().and_then(|res| res.client())
                    } else {
                        None
                    }
                } else {
                    None
                };

                self.serial += 1;
                let serial = self.serial;
                self.seat.broadcast_key(serial, time_ms, keycode, wl_state, client.as_ref());
            }
            InputEvent::KeyboardModifiers { depressed, latched, locked, group } => {
                self.seat.mods_depressed = depressed;
                self.seat.mods_latched = latched;
                self.seat.mods_locked = locked;
                self.seat.mods_group = group;
                
                let client = if let Some(sid) = self.seat.keyboard_focus {
                    if let Some(surf) = self.surfaces.get(&sid) {
                        surf.read().unwrap().resource.as_ref().and_then(|res| res.client())
                    } else {
                        None
                    }
                } else {
                    None
                };

                self.serial += 1;
                let serial = self.serial;
                self.seat.broadcast_modifiers(
                    serial, 
                    depressed, 
                    latched, 
                    locked, 
                    group, 
                    client.as_ref()
                );
            }
        }
    }
    
    // =========================================================================
    // Frame Callbacks
    // =========================================================================
    
    /// Queue a frame callback for a surface.
    pub fn queue_frame_callback(&mut self, surface_id: u32, callback: WlCallback) {
        self.frame_callbacks
            .entry(surface_id)
            .or_insert_with(Vec::new)
            .push(callback);
    }
    
    /// Flush all pending frame callbacks for a surface.
    pub fn flush_frame_callbacks(&mut self, surface_id: u32, timestamp: Option<u32>) {
        if let Some(callbacks) = self.frame_callbacks.remove(&surface_id) {
            let _count = callbacks.len();
            let timestamp = timestamp.unwrap_or_else(Self::get_timestamp_ms);
            crate::wlog!(crate::util::logging::STATE, "Flushing {} frame callbacks for surface {} (timestamp={})", 
                callbacks.len(), surface_id, timestamp);
            for callback in callbacks {
                callback.done(timestamp);
            }
        }
    }
    
    /// Flush all pending frame callbacks for all surfaces.
    pub fn flush_all_frame_callbacks(&mut self) {
        let timestamp = Self::get_timestamp_ms();
        let mut total = 0;
        
        for (_surface_id, callbacks) in self.frame_callbacks.drain() {
            total += callbacks.len();
            for callback in callbacks {
                callback.done(timestamp);
            }
        }
        
        if total > 0 {
            tracing::trace!("Flushed {} total frame callbacks", total);
        }
    }
    
    /// Check if there are pending frame callbacks
    pub fn has_pending_frame_callbacks(&self) -> bool {
        self.frame_callbacks.values().any(|v| !v.is_empty())
    }

    // =========================================================================
    // Window Management
    // =========================================================================

    /// Register a new window for a surface
    pub fn register_window(&mut self, surface_id: u32, window: Window) -> u32 {
        let window_id = window.id;
        self.windows.insert(window_id, Arc::new(RwLock::new(window)));
        self.surface_to_window.insert(surface_id, window_id);
        self.window_tree.insert(window_id);
        
        // Auto-focus new window
        self.focus.set_keyboard_focus(Some(window_id));
        self.focus.set_pointer_focus(Some(window_id));
        self.window_tree.bring_to_front(window_id);
        
        tracing::info!("Registered window {} for surface {}", window_id, surface_id);
        window_id
    }

    /// Get a window by ID
    pub fn get_window(&self, window_id: u32) -> Option<Arc<RwLock<Window>>> {
        self.windows.get(&window_id).cloned()
    }
    
    /// Get a window by Surface ID
    pub fn get_window_by_surface(&self, surface_id: u32) -> Option<Arc<RwLock<Window>>> {
        let wid = self.surface_to_window.get(&surface_id)?;
        self.get_window(*wid)
    }

    /// Destroy a window
    pub fn destroy_window(&mut self, window_id: u32) {
        if let Some(window) = self.windows.remove(&window_id) {
            let surface_id = window.read().unwrap().surface_id;
            self.surface_to_window.remove(&surface_id);
            self.window_tree.remove(window_id);
            
            // Clear focus if needed
            if self.focus.has_keyboard_focus(window_id) {
                // Restore previous focus
                let next = self.focus.focus_history.first().copied();
                self.focus.set_keyboard_focus(next);
            }
            if self.focus.pointer_focus == Some(window_id) {
                self.focus.set_pointer_focus(None);
            }
            
            tracing::info!("Destroyed window {}", window_id);
            
            // CRITICAL: Emit event for FFI layer cleanup
            self.pending_compositor_events.push(crate::core::compositor::CompositorEvent::WindowDestroyed {
                window_id,
            });
        }
    }
    
    // =========================================================================
    // Output Management
    // =========================================================================
    
    /// Get primary output
    pub fn primary_output(&self) -> &OutputState {
        &self.outputs[self.primary_output]
    }

    /// Update primary output configuration
    pub fn update_primary_output(&mut self, width: u32, height: u32, scale: f32) {
        let index = self.primary_output;
        if let Some(output) = self.outputs.get_mut(index) {
            output.update(width, height, scale);
            crate::wlog!(crate::util::logging::STATE, "Updated primary output: {}x{} @ {}x", width, height, scale);
        }
    }
    
    /// Get primary output mutably
    pub fn primary_output_mut(&mut self) -> &mut OutputState {
        &mut self.outputs[self.primary_output]
    }
    
    /// Set output size
    pub fn set_output_size(&mut self, width: u32, height: u32, scale: f32) {
        let output = self.primary_output_mut();
        
        // Clamp scale to minimum 1.0 to prevent client crashes (wl_output scale must be >= 1)
        let safe_scale = if scale < 1.0 { 1.0 } else { scale };
        // Ensure non-zero dimensions
        let safe_width = if width == 0 { 1920 } else { width };
        let safe_height = if height == 0 { 1080 } else { height };
        
        output.width = safe_width;
        output.height = safe_height;
        output.scale = safe_scale;
        
        // Update physical dimensions based on new size/scale (assuming ~96 DPI logical)
        // physical_mm = (pixels / scale / 96.0) * 25.4
        output.physical_width = ((safe_width as f32 / safe_scale) / 96.0 * 25.4) as u32;
        output.physical_height = ((safe_height as f32 / safe_scale) / 96.0 * 25.4) as u32;
        
        tracing::info!("Output size set to {}x{} @ {}x (phys: {}x{}mm)", 
            safe_width, safe_height, safe_scale, output.physical_width, output.physical_height);
    }
    
    // =========================================================================
    // Utilities
    // =========================================================================
    
    /// Get current timestamp in milliseconds.
    pub fn get_timestamp_ms() -> u32 {
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u32
    }
    
    /// Get decoration mode for new windows
    pub fn decoration_mode_for_new_window(&self) -> DecorationMode {
        match self.decoration_policy {
            DecorationPolicy::PreferClient => DecorationMode::ClientSide,
            DecorationPolicy::PreferServer => DecorationMode::ServerSide,
            DecorationPolicy::ForceServer => DecorationMode::ServerSide,
        }
    }
    
    // =========================================================================
    // Subsurface Management
    // =========================================================================
    
    pub fn add_subsurface_resource(&mut self, surface_id: u32, parent_id: u32, _subsurface: wayland_server::protocol::wl_subsurface::WlSubsurface) {
         // In a full implementation, we'd store the WlSubsurface resource
         // For now, just track the ID relationship
         self.subsurface_children.entry(parent_id).or_default().push(surface_id);
    }

    /// Add a subsurface relationship
    pub fn add_subsurface(&mut self, surface_id: u32, parent_id: u32) {
        // Get z-order based on existing children
        let z_order = self.subsurface_children
            .get(&parent_id)
            .map(|c| c.len() as i32)
            .unwrap_or(0);
        
        let state = SubsurfaceState {
            surface_id,
            parent_id,
            position: (0, 0),
            pending_position: (0, 0),
            sync: true,
            z_order,
        };
        
        self.subsurfaces.insert(surface_id, state);
        self.subsurface_children
            .entry(parent_id)
            .or_insert_with(Vec::new)
            .push(surface_id);
        
        tracing::debug!(
            "Subsurface {} added to parent {} (z-order: {})",
            surface_id, parent_id, z_order
        );
    }
    
    /// Remove a subsurface
    pub fn remove_subsurface(&mut self, surface_id: u32) {
        if let Some(state) = self.subsurfaces.remove(&surface_id) {
            // Remove from parent's children list
            if let Some(children) = self.subsurface_children.get_mut(&state.parent_id) {
                children.retain(|&id| id != surface_id);
            }
            tracing::debug!("Subsurface {} removed from parent {}", surface_id, state.parent_id);
        }
    }
    
    /// Set subsurface pending position
    pub fn set_subsurface_position(&mut self, surface_id: u32, x: i32, y: i32) {
        if let Some(state) = self.subsurfaces.get_mut(&surface_id) {
            state.pending_position = (x, y);
        }
    }
    
    /// Commit subsurface position (called on parent commit for sync mode)
    pub fn commit_subsurface_position(&mut self, surface_id: u32) {
        if let Some(state) = self.subsurfaces.get_mut(&surface_id) {
            state.position = state.pending_position;
        }
    }
    
    /// Set subsurface sync mode
    pub fn set_subsurface_sync(&mut self, surface_id: u32, sync: bool) {
        if let Some(state) = self.subsurfaces.get_mut(&surface_id) {
            state.sync = sync;
        }
    }
    
    /// Place subsurface above sibling
    pub fn place_subsurface_above(&mut self, surface_id: u32, sibling_id: u32) {
        if let Some(state) = self.subsurfaces.get(&surface_id) {
            let parent_id = state.parent_id;
            if let Some(children) = self.subsurface_children.get_mut(&parent_id) {
                // Find sibling's position and place above
                if let Some(sibling_pos) = children.iter().position(|&id| id == sibling_id) {
                    children.retain(|&id| id != surface_id);
                    let insert_pos = (sibling_pos + 1).min(children.len());
                    children.insert(insert_pos, surface_id);
                    
                    // Update z-orders
                    for (i, &id) in children.iter().enumerate() {
                        if let Some(s) = self.subsurfaces.get_mut(&id) {
                            s.z_order = i as i32;
                        }
                    }
                }
            }
        }
    }
    
    /// Place subsurface below sibling
    pub fn place_subsurface_below(&mut self, surface_id: u32, sibling_id: u32) {
        if let Some(state) = self.subsurfaces.get(&surface_id) {
            let parent_id = state.parent_id;
            if let Some(children) = self.subsurface_children.get_mut(&parent_id) {
                // Find sibling's position and place below
                if let Some(sibling_pos) = children.iter().position(|&id| id == sibling_id) {
                    children.retain(|&id| id != surface_id);
                    children.insert(sibling_pos, surface_id);
                    
                    // Update z-orders
                    for (i, &id) in children.iter().enumerate() {
                        if let Some(s) = self.subsurfaces.get_mut(&id) {
                            s.z_order = i as i32;
                        }
                    }
                }
            }
        }
    }
    
    /// Get subsurface state
    pub fn get_subsurface(&self, surface_id: u32) -> Option<&SubsurfaceState> {
        self.subsurfaces.get(&surface_id)
    }
    
    /// Get children of a surface (subsurfaces)
    pub fn get_subsurface_children(&self, parent_id: u32) -> Option<&Vec<u32>> {
        self.subsurface_children.get(&parent_id)
    }
    
    /// Check if surface is a subsurface
    pub fn is_subsurface(&self, surface_id: u32) -> bool {
        self.subsurfaces.contains_key(&surface_id)
    }
    
    // =========================================================================
    // Clipboard & Drag-and-Drop
    // =========================================================================
    
    /// Set the current clipboard source
    pub fn set_clipboard_source(&mut self, source_id: Option<u32>) {
        tracing::debug!("Clipboard source set to: {:?}", source_id);
        // In a full implementation, store the source and notify clients
    }
    
    // (start_drag removed - see implementation below)

    // =========================================================================
    // DMABUF Export Management
    // =========================================================================

    /// Add a DMABUF export frame
    pub fn add_dmabuf_export_frame(&mut self, resource_id: u32, frame: DmabufExportFrame) {
        self.export_dmabuf_frames.insert(resource_id, frame);
        tracing::debug!("Added DMABUF export frame for resource {}", resource_id);
    }

    /// Remove a DMABUF export frame
    pub fn remove_dmabuf_export_frame(&mut self, resource_id: u32) {
        self.export_dmabuf_frames.remove(&resource_id);
        tracing::debug!("Removed DMABUF export frame for resource {}", resource_id);
    }

    // =========================================================================
    // Virtual Pointer Management
    // =========================================================================

    /// Add a virtual pointer
    pub fn add_virtual_pointer(&mut self, resource_id: u32, pointer: VirtualPointerState) {
        self.virtual_pointers.insert(resource_id, pointer);
        tracing::debug!("Added virtual pointer device for resource {}", resource_id);
    }

    /// Add a buffer
    pub fn add_buffer(&mut self, buffer: crate::core::surface::Buffer) {
        let id = buffer.id;
        self.buffers.insert(id, Arc::new(RwLock::new(buffer)));
        tracing::debug!("Added buffer {}", id);
    }

    /// Get a buffer by ID
    pub fn get_buffer(&self, id: u32) -> Option<Arc<RwLock<crate::core::surface::Buffer>>> {
        self.buffers.get(&id).cloned()
    }

    /// Release a buffer (notify client we are done with it)
    pub fn release_buffer(&mut self, buffer_id: u32) {
        if let Some(buffer) = self.buffers.get(&buffer_id) {
            let mut buffer = buffer.write().unwrap();
            buffer.release();
            tracing::debug!("Released buffer {}", buffer_id);
        }
    }

    /// Remove a buffer
    pub fn remove_buffer(&mut self, id: u32) {
        self.buffers.remove(&id);
        tracing::debug!("Removed buffer {}", id);
    }

    /// Remove a virtual pointer
    pub fn remove_virtual_pointer(&mut self, resource_id: u32) {
        self.virtual_pointers.remove(&resource_id);
        tracing::debug!("Removed virtual pointer device for resource {}", resource_id);
    }

    // =========================================================================
    // Virtual Keyboard Management
    // =========================================================================

    /// Add a virtual keyboard
    pub fn add_virtual_keyboard(&mut self, resource_id: u32, keyboard: VirtualKeyboardState) {
        self.virtual_keyboards.insert(resource_id, keyboard);
        tracing::debug!("Added virtual keyboard device for resource {}", resource_id);
    }

    /// Remove a virtual keyboard
    pub fn remove_virtual_keyboard(&mut self, resource_id: u32) {
        self.virtual_keyboards.remove(&resource_id);
        tracing::debug!("Removed virtual keyboard device for resource {}", resource_id);
    }

    /// Start a drag-and-drop operation
    pub fn start_drag(
        &mut self,
        source_id: Option<u32>,
        origin_surface_id: u32,
        icon_surface_id: Option<u32>,
    ) {
        tracing::debug!(
            "Drag started: source={:?}, origin={}, icon={:?}",
            source_id, origin_surface_id, icon_surface_id
        );
        // In a full implementation:
        // 1. Store drag state
        // 2. Track icon surface
        // 3. Send enter/leave/motion events during drag
    }
    
    /// End the current drag-and-drop operation
    pub fn end_drag(&mut self, dropped: bool) {
        tracing::debug!("Drag ended: dropped={}", dropped);
        // In a full implementation:
        // 1. Send drop/cancel to target
        // 2. Clean up drag state
    }
    
    // =========================================================================
    // Presentation Time
    // =========================================================================
    
    /// Get next presentation sequence number
    pub fn next_presentation_seq(&mut self) -> u64 {
        let seq = self.presentation_seq;
        self.presentation_seq = self.presentation_seq.wrapping_add(1);
        seq
    }
    

    
    // =========================================================================
    // Idle Inhibition
    // =========================================================================
    
    /// Get next idle inhibitor ID
    pub fn next_inhibitor_id(&mut self) -> u32 {
        let id = self.next_inhibitor_id;
        self.next_inhibitor_id += 1;
        id
    }
    
    /// Add an idle inhibitor
    pub fn add_idle_inhibitor(&mut self, inhibitor_id: u32, surface_id: u32) {
        self.idle_inhibitors.insert(inhibitor_id, surface_id);
        tracing::debug!(
            "Idle inhibitor {} added (total: {})",
            inhibitor_id,
            self.idle_inhibitors.len()
        );
    }
    
    /// Remove an idle inhibitor
    pub fn remove_idle_inhibitor(&mut self, inhibitor_id: u32) {
        self.idle_inhibitors.remove(&inhibitor_id);
        tracing::debug!(
            "Idle inhibitor {} removed (remaining: {})",
            inhibitor_id,
            self.idle_inhibitors.len()
        );
    }
    
    /// Check if idle is currently inhibited
    pub fn is_idle_inhibited(&self) -> bool {
        !self.idle_inhibitors.is_empty()
    }
    
    /// Get count of active idle inhibitors
    pub fn idle_inhibitor_count(&self) -> usize {
        self.idle_inhibitors.len()
    }
    
    // =========================================================================
    // Keyboard Shortcuts Inhibition
    // =========================================================================
    
    /// Add a keyboard shortcuts inhibitor
    pub fn add_keyboard_shortcuts_inhibitor(&mut self, surface_id: u32, seat_id: u32) {
        self.keyboard_shortcuts_inhibitors.insert(surface_id, seat_id);
        tracing::debug!(
            "Keyboard shortcuts inhibitor added for surface {} on seat {}",
            surface_id, seat_id
        );
    }
    
    /// Remove a keyboard shortcuts inhibitor
    pub fn remove_keyboard_shortcuts_inhibitor(&mut self, surface_id: u32, seat_id: u32) {
        self.keyboard_shortcuts_inhibitors.remove(&surface_id);
        tracing::debug!(
            "Keyboard shortcuts inhibitor removed for surface {} on seat {}",
            surface_id, seat_id
        );
    }
    
    /// Check if keyboard shortcuts are inhibited for a surface
    pub fn is_keyboard_shortcuts_inhibited(&self, surface_id: u32) -> bool {
        self.keyboard_shortcuts_inhibitors.contains_key(&surface_id)
    }
    
    // =========================================================================
    // Layer Surface Management
    // =========================================================================
    
    /// Add a layer surface
    pub fn add_layer_surface(&mut self, surface: LayerSurface) -> u32 {
        let id = surface.surface_id;
        self.layer_surfaces.insert(id, Arc::new(RwLock::new(surface)));
        tracing::debug!("Added layer surface {}", id);
        id
    }
    
    /// Remove a layer surface
    pub fn remove_layer_surface(&mut self, surface_id: u32) {
        self.layer_surfaces.remove(&surface_id);
        tracing::debug!("Removed layer surface {}", surface_id);
    }
    
    /// Get a layer surface
    pub fn get_layer_surface(&self, surface_id: u32) -> Option<Arc<RwLock<LayerSurface>>> {
        self.layer_surfaces.get(&surface_id).cloned()
    }
    
    /// Get all layer surfaces for an output
    pub fn layer_surfaces_for_output(&self, output_id: u32) -> Vec<Arc<RwLock<LayerSurface>>> {
        self.layer_surfaces.values()
            .filter(|ls| ls.read().unwrap().output_id == output_id)
            .cloned()
            .collect()
    }
}

impl Default for CompositorState {
    fn default() -> Self {
        Self::new()
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_compositor_state_new() {
        let state = CompositorState::new();
        assert!(state.surfaces.is_empty());
        assert!(state.windows.is_empty());
        assert_eq!(state.focus.keyboard_focus, None);
    }
    
    #[test]
    fn test_surface_ids() {
        let mut state = CompositorState::new();
        assert_eq!(state.next_surface_id(), 1);
        assert_eq!(state.next_surface_id(), 2);
        assert_eq!(state.next_surface_id(), 3);
    }
    
    #[test]
    fn test_window_ids() {
        let mut state = CompositorState::new();
        assert_eq!(state.next_window_id(), 1);
        assert_eq!(state.next_window_id(), 2);
        assert_eq!(state.next_window_id(), 3);
    }
    
    #[test]
    fn test_focus_history() {
        let mut focus = crate::core::window::focus::FocusManager::new();
        
        focus.set_keyboard_focus(Some(1));
        assert_eq!(focus.keyboard_focus, Some(1));
        
        focus.set_keyboard_focus(Some(2));
        assert_eq!(focus.keyboard_focus, Some(2));
        assert_eq!(focus.focus_history, vec![1]);
        
        focus.set_keyboard_focus(Some(3));
        assert_eq!(focus.keyboard_focus, Some(3));
        assert_eq!(focus.focus_history, vec![2, 1]);
    }
}
