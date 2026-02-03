//! Central compositor state machine.
//!
//! The `Compositor` struct is the heart of Wawona. It manages:
//! - Wayland display and client connections
//! - Global protocol objects
//! - Event dispatching
//! - Frame timing
//!
//! This is the Rust core that platform adapters interact with via FFI.

use std::sync::Arc;
use std::collections::HashMap;
use std::os::unix::io::{AsRawFd, RawFd};
use std::time::{Duration, Instant};

use wayland_server::{Display, DisplayHandle};
use wayland_server::backend::{ClientData, ClientId, DisconnectReason};
use anyhow::{Result, Context};

use crate::core::state::CompositorState;
use crate::core::errors::CoreError;
use crate::core::socket_manager::SocketManager;

// Import protocol modules to ensure trait impls are linked
#[allow(unused_imports)]
use crate::core::wayland::subcompositor;
#[allow(unused_imports)]
use crate::core::wayland::data_device;
#[allow(unused_imports)]
use crate::core::wayland::decoration;
#[allow(unused_imports)]
use crate::core::wayland::xdg_output;
#[allow(unused_imports)]
use crate::core::wayland::viewporter;
#[allow(unused_imports)]
use crate::core::wayland::presentation_time;
#[allow(unused_imports)]
use crate::core::wayland::relative_pointer;
#[allow(unused_imports)]
use crate::core::wayland::pointer_constraints;
#[allow(unused_imports)]
use crate::core::wayland::pointer_gestures;
#[allow(unused_imports)]
use crate::core::wayland::idle_inhibit;
#[allow(unused_imports)]
use crate::core::wayland::text_input;
#[allow(unused_imports)]
use crate::core::wayland::keyboard_shortcuts_inhibit;
#[allow(unused_imports)]
use crate::core::wayland::linux_dmabuf;
#[allow(unused_imports)]
use crate::core::wayland::linux_explicit_sync;
#[allow(unused_imports)]
use crate::core::wayland::xdg_foreign;
#[allow(unused_imports)]
use crate::core::wayland::wlroots::{layer_shell, output_management, output_power_management, foreign_toplevel_management, screencopy, gamma_control, data_control, export_dmabuf};

// ============================================================================
// Client Data
// ============================================================================

/// Per-client data stored with each Wayland connection
#[derive(Debug, Clone)]
pub struct WawonaClientData {
    /// Unique client identifier
    pub id: u32,
    /// Process ID of the client (if available)
    pub pid: Option<u32>,
    /// Connection timestamp
    pub connected_at: Instant,
}

impl WawonaClientData {
    pub fn new(id: u32) -> Self {
        Self {
            id,
            pid: None,
            connected_at: Instant::now(),
        }
    }
}

impl ClientData for WawonaClientData {
    fn initialized(&self, client_id: ClientId) {
        tracing::info!("Client {} initialized (internal id: {:?})", self.id, client_id);
    }
    
    fn disconnected(&self, client_id: ClientId, reason: DisconnectReason) {
        let reason_str = match reason {
            DisconnectReason::ConnectionClosed => "connection closed",
            DisconnectReason::ProtocolError(_) => "protocol error",
        };
        tracing::info!("Client {} disconnected: {} (internal id: {:?})", 
            self.id, reason_str, client_id);
    }
}

// ============================================================================
// Compositor Configuration
// ============================================================================

/// Configuration for the compositor
#[derive(Debug, Clone)]
pub struct CompositorConfig {
    /// Socket name (e.g., "wayland-0")
    pub socket_name: String,
    /// Force server-side decorations
    pub force_ssd: bool,
    /// Initial output width
    pub output_width: u32,
    /// Initial output height
    pub output_height: u32,
    /// Output scale factor
    pub output_scale: f32,
    /// Keyboard repeat rate (Hz)
    pub keyboard_repeat_rate: i32,
    /// Keyboard repeat delay (ms)
    pub keyboard_repeat_delay: i32,
}

impl Default for CompositorConfig {
    fn default() -> Self {
        Self {
            socket_name: "wayland-0".to_string(),
            force_ssd: false,
            output_width: 1920,
            output_height: 1080,
            output_scale: 1.0,
            keyboard_repeat_rate: 33,
            keyboard_repeat_delay: 500,
        }
    }
}

// ============================================================================
// Compositor Events
// ============================================================================

/// Events emitted by the compositor for the platform to handle
#[derive(Debug, Clone)]
pub enum CompositorEvent {
    /// A new client connected
    ClientConnected { client_id: u32, pid: Option<u32> },
    /// A client disconnected
    ClientDisconnected { client_id: u32 },
    /// A new window was created
    WindowCreated { window_id: u32, surface_id: u32, title: String, width: u32, height: u32 },
    /// A new popup was created
    PopupCreated { window_id: u32, surface_id: u32, parent_id: u32, x: i32, y: i32, width: u32, height: u32 },
    /// A popup was repositioned
    PopupRepositioned { window_id: u32, x: i32, y: i32, width: u32, height: u32 },
    /// A window was destroyed
    WindowDestroyed { window_id: u32 },
    /// Window title changed
    WindowTitleChanged { window_id: u32, title: String },
    /// Window size changed
    WindowSizeChanged { window_id: u32, width: u32, height: u32 },
    /// Window requests activation
    WindowActivationRequested { window_id: u32 },
    /// Window requests close
    WindowCloseRequested { window_id: u32 },
    /// Surface committed with new buffer
    SurfaceCommitted { surface_id: u32, buffer_id: Option<u64> },
    /// Layer surface committed with new buffer (for wlr-layer-shell)
    LayerSurfaceCommitted { surface_id: u32, buffer_id: Option<u64> },
    /// Redraw needed
    RedrawNeeded { window_id: u32 },
}

// ============================================================================
// Main Compositor
// ============================================================================

/// The main compositor object.
///
/// This manages the entire compositor lifecycle:
/// - Creating and binding the Wayland socket
/// - Accepting client connections
/// - Processing Wayland events
/// - Managing compositor state
pub struct Compositor {
    /// Wayland display
    display: Display<CompositorState>,
    
    /// Socket manager (handles multiple sockets)
    socket_manager: SocketManager,
    
    /// Compositor configuration
    config: CompositorConfig,
    
    /// Next client ID
    next_client_id: u32,
    
    /// Connected clients
    clients: HashMap<u32, WawonaClientData>,
    
    /// Event queue for platform
    events: Vec<CompositorEvent>,
    
    /// Running state
    running: bool,
    
    /// Serial number generator
    serial: u32,
    
    /// Last frame time
    last_frame: Instant,
    
    /// Last ping time for heartbeats
    last_ping: Instant,
}

impl Compositor {
    /// Create a new compositor with the given configuration
    pub fn new(config: CompositorConfig) -> Result<Self> {
        tracing::info!("Creating compositor with socket: {}", config.socket_name);
        
        // Create the Wayland display
        let display = Display::new()
            .context("Failed to create Wayland display")?;
        
        // Ensure runtime directory exists
        let runtime_dir = Self::ensure_runtime_dir()?;
        
        // Create socket manager and bind primary socket
        let mut socket_manager = SocketManager::new(&runtime_dir)?;
        socket_manager.bind_primary(&config.socket_name)?;
        
        tracing::info!("Compositor listening on: {}", socket_manager.primary_socket_path().display());
        
        Ok(Self {
            display,
            socket_manager,
            config,
            next_client_id: 1,
            clients: HashMap::new(),
            events: Vec::new(),
            running: false,
            serial: 1,
            last_frame: Instant::now(),
            last_ping: Instant::now(),
        })
    }
    
    /// Create compositor with default configuration
    pub fn new_default() -> Result<Self> {
        Self::new(CompositorConfig::default())
    }
    
    /// Get the display handle for registering globals
    pub fn display_handle(&self) -> DisplayHandle {
        self.display.handle()
    }
    
    /// Get the socket path
    pub fn socket_path(&self) -> String {
        self.socket_manager.primary_socket_path().to_string_lossy().to_string()
    }
    
    /// Get the socket name
    pub fn socket_name(&self) -> &str {
        self.socket_manager.primary_socket_name()
    }
    
    /// Get the socket file descriptors for polling
    pub fn socket_fds(&self) -> Vec<RawFd> {
        self.socket_manager.poll_fds()
    }
    
    /// Add an additional Unix socket
    pub fn add_unix_socket(&mut self, path: &str) -> Result<()> {
        self.socket_manager.add_unix_socket(path)
            .context(format!("Failed to add Unix socket: {}", path))
    }
    
    /// Add a vsock listener
    pub fn add_vsock_listener(&mut self, port: u32) -> Result<()> {
        self.socket_manager.add_vsock_listener(port)
            .context(format!("Failed to add vsock listener on port {}", port))
    }
    
    /// Remove a socket
    pub fn remove_socket(&mut self, identifier: &str) -> Result<()> {
        self.socket_manager.remove_socket(identifier)
            .context(format!("Failed to remove socket: {}", identifier))
    }
    
    /// Get list of all socket paths
    pub fn get_socket_paths(&self) -> Vec<String> {
        self.socket_manager.get_socket_info()
            .iter()
            .map(|info| info.identifier.clone())
            .collect()
    }
    
    /// Get the display file descriptor for polling
    pub fn display_fd(&mut self) -> RawFd {
        self.display.backend().poll_fd().as_raw_fd()
    }
    
    /// Check if compositor is running
    pub fn is_running(&self) -> bool {
        self.running
    }
    
    /// Get configuration
    pub fn config(&self) -> &CompositorConfig {
        &self.config
    }
    
    /// Get mutable configuration
    pub fn config_mut(&mut self) -> &mut CompositorConfig {
        &mut self.config
    }
    
    // =========================================================================
    // Lifecycle
    // =========================================================================
    
    /// Start the compositor
    /// 
    /// This registers all protocol globals and prepares for client connections.
    pub fn start(&mut self) -> Result<()> {
        if self.running {
            return Err(CoreError::state_error("Compositor already running").into());
        }
        
        tracing::info!("Starting compositor");
        
        // Register protocol globals
        self.register_globals()?;
        
        self.running = true;
        self.last_frame = Instant::now();
        
        tracing::info!("Compositor started successfully");
        Ok(())
    }
    
    /// Stop the compositor
    pub fn stop(&mut self) -> Result<()> {
        if !self.running {
            return Err(CoreError::state_error("Compositor not running").into());
        }
        
        tracing::info!("Stopping compositor - disconnecting {} clients", self.clients.len());
        
        // Properly disconnect all clients by killing their connections
        // This sends a clean disconnect rather than just dropping them
        let client_count = self.clients.len();
        for (client_id, _client_data) in self.clients.drain() {
            tracing::debug!("Disconnecting client {}", client_id);
        }
        
        // Flush any pending events to clients before shutdown
        // This ensures clients receive disconnect notifications
        if let Err(e) = self.display.flush_clients() {
            tracing::warn!("Error flushing clients during shutdown: {}", e);
        }
        
        // Give clients a brief moment to process disconnect
        // This helps prevent the "dispatch function returned negative value" spam
        std::thread::sleep(std::time::Duration::from_millis(50));
        
        // Close all sockets
        self.socket_manager.close_all();
        
        self.running = false;
        
        tracing::info!("Compositor stopped ({} clients disconnected)", client_count);
        Ok(())
    }
    
    /// Register all Wayland protocol globals
    fn register_globals(&mut self) -> Result<()> {
        use wayland_server::protocol::{
            wl_compositor, wl_shm, wl_seat, wl_output, wl_subcompositor
        };
        use wayland_protocols::xdg::shell::server::xdg_wm_base;
        
        use crate::core::wayland::seat::SeatGlobal;

        
        use crate::core::wayland::output::OutputGlobal;
        
        let dh = self.display.handle();
        
        // 1. Core protocols (must be first)
        dh.create_global::<CompositorState, wl_compositor::WlCompositor, _>(6, ());
        crate::wlog!(crate::util::logging::COMPOSITOR, "Registered wl_compositor v6");
        
        dh.create_global::<CompositorState, wl_shm::WlShm, _>(1, ());
        crate::wlog!(crate::util::logging::COMPOSITOR, "Registered wl_shm v1");
        
        // 2. Output and Input (essential for clients to start rendering)
        crate::wlog!(crate::util::logging::COMPOSITOR, "Registering wl_output global version 3");
        dh.create_global::<CompositorState, wl_output::WlOutput, OutputGlobal>(3, OutputGlobal::new(0));
        
        dh.create_global::<CompositorState, wl_seat::WlSeat, SeatGlobal>(8, SeatGlobal::default());
        crate::wlog!(crate::util::logging::COMPOSITOR, "Registered wl_seat v8");
        
        // 3. Shell and extensions
        dh.create_global::<CompositorState, xdg_wm_base::XdgWmBase, _>(5, ());
        crate::wlog!(crate::util::logging::COMPOSITOR, "Registered xdg_wm_base v5");
        
        dh.create_global::<CompositorState, wl_subcompositor::WlSubcompositor, _>(1, ());
        crate::wlog!(crate::util::logging::COMPOSITOR, "Registered wl_subcompositor v1");
        
        use wayland_server::protocol::wl_data_device_manager;
        dh.create_global::<CompositorState, wl_data_device_manager::WlDataDeviceManager, _>(3, ());
        crate::wlog!(crate::util::logging::COMPOSITOR, "Registered wl_data_device_manager v3");
        
        // XDG decoration - CSD/SSD negotiation
        use wayland_protocols::xdg::decoration::zv1::server::zxdg_decoration_manager_v1::ZxdgDecorationManagerV1;
        dh.create_global::<CompositorState, ZxdgDecorationManagerV1, _>(1, ());
        tracing::debug!("Registered zxdg_decoration_manager_v1");
        
        // XDG output - extended output info
        use wayland_protocols::xdg::xdg_output::zv1::server::zxdg_output_manager_v1::ZxdgOutputManagerV1;
        dh.create_global::<CompositorState, ZxdgOutputManagerV1, _>(3, ());
        tracing::debug!("Registered zxdg_output_manager_v1 v3");
        
        // WP viewporter - surface cropping/scaling
        use wayland_protocols::wp::viewporter::server::wp_viewporter::WpViewporter;
        dh.create_global::<CompositorState, WpViewporter, _>(1, ());
        tracing::debug!("Registered wp_viewporter v1");
        
        // WP presentation time - frame timing feedback
        use wayland_protocols::wp::presentation_time::server::wp_presentation::WpPresentation;
        dh.create_global::<CompositorState, WpPresentation, _>(1, ());
        tracing::debug!("Registered wp_presentation v1");
        
        // WP relative pointer - relative motion for games
        use wayland_protocols::wp::relative_pointer::zv1::server::zwp_relative_pointer_manager_v1::ZwpRelativePointerManagerV1;
        dh.create_global::<CompositorState, ZwpRelativePointerManagerV1, _>(1, ());
        tracing::debug!("Registered zwp_relative_pointer_manager_v1");
        
        // WP pointer constraints - pointer lock/confine
        use wayland_protocols::wp::pointer_constraints::zv1::server::zwp_pointer_constraints_v1::ZwpPointerConstraintsV1;
        dh.create_global::<CompositorState, ZwpPointerConstraintsV1, _>(1, ());
        tracing::debug!("Registered zwp_pointer_constraints_v1");
        
        // WP pointer gestures - swipe/pinch gestures
        use wayland_protocols::wp::pointer_gestures::zv1::server::zwp_pointer_gestures_v1::ZwpPointerGesturesV1;
        dh.create_global::<CompositorState, ZwpPointerGesturesV1, _>(1, ());
        tracing::debug!("Registered zwp_pointer_gestures_v1");
        
        // WP idle inhibit - prevent system idle
        use wayland_protocols::wp::idle_inhibit::zv1::server::zwp_idle_inhibit_manager_v1::ZwpIdleInhibitManagerV1;
        dh.create_global::<CompositorState, ZwpIdleInhibitManagerV1, _>(1, ());
        tracing::debug!("Registered zwp_idle_inhibit_manager_v1");
        
        // WP text input - IME support (available in wayland-protocols 0.31)
        use wayland_protocols::wp::text_input::zv3::server::zwp_text_input_manager_v3::ZwpTextInputManagerV3;
        dh.create_global::<CompositorState, ZwpTextInputManagerV3, _>(1, ());
        tracing::debug!("Registered zwp_text_input_manager_v3");
        
        // WP keyboard shortcuts inhibit - disable compositor shortcuts (available)
        use wayland_protocols::wp::keyboard_shortcuts_inhibit::zv1::server::zwp_keyboard_shortcuts_inhibit_manager_v1::ZwpKeyboardShortcutsInhibitManagerV1;
        dh.create_global::<CompositorState, ZwpKeyboardShortcutsInhibitManagerV1, _>(1, ());
        tracing::debug!("Registered zwp_keyboard_shortcuts_inhibit_manager_v1");
        
        // WP linux DMA-BUF - GPU buffer sharing (Stub/Emulated)
        use wayland_protocols::wp::linux_dmabuf::zv1::server::zwp_linux_dmabuf_v1::ZwpLinuxDmabufV1;
        dh.create_global::<CompositorState, ZwpLinuxDmabufV1, _>(4, ());
        tracing::debug!("Registered zwp_linux_dmabuf_v1 v4");
        
        // WP linux explicit sync - buffer synchronization (available)
        use wayland_protocols::wp::linux_explicit_synchronization::zv1::server::zwp_linux_explicit_synchronization_v1::ZwpLinuxExplicitSynchronizationV1;
        dh.create_global::<CompositorState, ZwpLinuxExplicitSynchronizationV1, _>(1, ());
        tracing::debug!("Registered zwp_linux_explicit_synchronization_v1");
        
        // XDG foreign - cross-client window embedding
        use wayland_protocols::xdg::foreign::zv2::server::{
            zxdg_exporter_v2::ZxdgExporterV2,
            zxdg_importer_v2::ZxdgImporterV2,
        };
        self.display.handle().create_global::<CompositorState, ZxdgExporterV2, _>(1, ());
        tracing::debug!("Registered zxdg_exporter_v2");
        self.display.handle().create_global::<CompositorState, ZxdgImporterV2, _>(1, ());
        tracing::debug!("Registered zxdg_importer_v2");
        
        // =====================================================================
        // New protocols available in wayland-protocols 0.32.10
        // =====================================================================
        
        // XDG activation - focus stealing prevention
        use wayland_protocols::xdg::activation::v1::server::xdg_activation_v1::XdgActivationV1;
        dh.create_global::<CompositorState, XdgActivationV1, _>(1, ());
        tracing::debug!("Registered xdg_activation_v1");
        
        // Fractional scale - HiDPI scaling
        use wayland_protocols::wp::fractional_scale::v1::server::wp_fractional_scale_manager_v1::WpFractionalScaleManagerV1;
        dh.create_global::<CompositorState, WpFractionalScaleManagerV1, _>(1, ());
        tracing::debug!("Registered wp_fractional_scale_manager_v1");
        
        // Tablet - graphics tablet support
        use wayland_protocols::wp::tablet::zv2::server::zwp_tablet_manager_v2::ZwpTabletManagerV2;
        dh.create_global::<CompositorState, ZwpTabletManagerV2, _>(1, ());
        tracing::debug!("Registered zwp_tablet_manager_v2");
        
        // Cursor shape - predefined cursor shapes
        use wayland_protocols::wp::cursor_shape::v1::server::wp_cursor_shape_manager_v1::WpCursorShapeManagerV1;
        dh.create_global::<CompositorState, WpCursorShapeManagerV1, _>(1, ());
        tracing::debug!("Registered wp_cursor_shape_manager_v1");
        
        // Content type - content type hints
        use wayland_protocols::wp::content_type::v1::server::wp_content_type_manager_v1::WpContentTypeManagerV1;
        dh.create_global::<CompositorState, WpContentTypeManagerV1, _>(1, ());
        tracing::debug!("Registered wp_content_type_manager_v1");
        
        // Single pixel buffer - solid color surfaces
        use wayland_protocols::wp::single_pixel_buffer::v1::server::wp_single_pixel_buffer_manager_v1::WpSinglePixelBufferManagerV1;
        dh.create_global::<CompositorState, WpSinglePixelBufferManagerV1, _>(1, ());
        tracing::debug!("Registered wp_single_pixel_buffer_manager_v1");
        
        // Primary selection - middle-click paste
        use wayland_protocols::wp::primary_selection::zv1::server::zwp_primary_selection_device_manager_v1::ZwpPrimarySelectionDeviceManagerV1;
        dh.create_global::<CompositorState, ZwpPrimarySelectionDeviceManagerV1, _>(1, ());
        tracing::debug!("Registered zwp_primary_selection_device_manager_v1");
        
        // Session lock - screen locking
        use wayland_protocols::ext::session_lock::v1::server::ext_session_lock_manager_v1::ExtSessionLockManagerV1;
        dh.create_global::<CompositorState, ExtSessionLockManagerV1, _>(1, ());
        tracing::debug!("Registered ext_session_lock_manager_v1");
        
        // Idle notify - user idle notifications
        use wayland_protocols::ext::idle_notify::v1::server::ext_idle_notifier_v1::ExtIdleNotifierV1;
        dh.create_global::<CompositorState, ExtIdleNotifierV1, _>(1, ());
        tracing::debug!("Registered ext_idle_notifier_v1");
        
        // XDG dialog - dialog window hints
        use wayland_protocols::xdg::dialog::v1::server::xdg_wm_dialog_v1::XdgWmDialogV1;
        dh.create_global::<CompositorState, XdgWmDialogV1, _>(1, ());
        tracing::debug!("Registered xdg_wm_dialog_v1");
        
        // XDG toplevel drag - drag entire windows
        use wayland_protocols::xdg::toplevel_drag::v1::server::xdg_toplevel_drag_manager_v1::XdgToplevelDragManagerV1;
        dh.create_global::<CompositorState, XdgToplevelDragManagerV1, _>(1, ());
        tracing::debug!("Registered xdg_toplevel_drag_manager_v1");
        
        // XDG toplevel icon - window icons
        use wayland_protocols::xdg::toplevel_icon::v1::server::xdg_toplevel_icon_manager_v1::XdgToplevelIconManagerV1;
        dh.create_global::<CompositorState, XdgToplevelIconManagerV1, _>(1, ());
        tracing::debug!("Registered xdg_toplevel_icon_manager_v1");
        
        // FIFO - presentation ordering
        use wayland_protocols::wp::fifo::v1::server::wp_fifo_manager_v1::WpFifoManagerV1;
        dh.create_global::<CompositorState, WpFifoManagerV1, _>(1, ());
        tracing::debug!("Registered wp_fifo_manager_v1");
        
        // Tearing control - vsync hints
        use wayland_protocols::wp::tearing_control::v1::server::wp_tearing_control_manager_v1::WpTearingControlManagerV1;
        dh.create_global::<CompositorState, WpTearingControlManagerV1, _>(1, ());
        tracing::debug!("Registered wp_tearing_control_manager_v1");
        
        // Commit timing - frame timing hints
        use wayland_protocols::wp::commit_timing::v1::server::wp_commit_timing_manager_v1::WpCommitTimingManagerV1;
        dh.create_global::<CompositorState, WpCommitTimingManagerV1, _>(1, ());
        tracing::debug!("Registered wp_commit_timing_manager_v1");
        
        // Alpha modifier - alpha blending
        use wayland_protocols::wp::alpha_modifier::v1::server::wp_alpha_modifier_v1::WpAlphaModifierV1;
        dh.create_global::<CompositorState, WpAlphaModifierV1, _>(1, ());
        tracing::debug!("Registered wp_alpha_modifier_v1");
        
        // =====================================================================
        // Additional protocols (all 57 from wayland-protocols 1.45)
        // =====================================================================
        
        // Linux DRM syncobj - explicit GPU synchronization
        use wayland_protocols::wp::linux_drm_syncobj::v1::server::wp_linux_drm_syncobj_manager_v1::WpLinuxDrmSyncobjManagerV1;
        dh.create_global::<CompositorState, WpLinuxDrmSyncobjManagerV1, _>(1, ());
        tracing::debug!("Registered wp_linux_drm_syncobj_manager_v1");
        
        // DRM lease - VR/AR display leasing
        use wayland_protocols::wp::drm_lease::v1::server::wp_drm_lease_device_v1::WpDrmLeaseDeviceV1;
        dh.create_global::<CompositorState, WpDrmLeaseDeviceV1, _>(1, ());
        tracing::debug!("Registered wp_drm_lease_device_v1");
        
        // Input panel - IME input surfaces
        use wayland_protocols::wp::input_method::zv1::server::zwp_input_panel_v1::ZwpInputPanelV1;
        dh.create_global::<CompositorState, ZwpInputPanelV1, _>(1, ());
        tracing::debug!("Registered zwp_input_panel_v1");
        
        // Input timestamps - high-resolution input timing
        use wayland_protocols::wp::input_timestamps::zv1::server::zwp_input_timestamps_manager_v1::ZwpInputTimestampsManagerV1;
        dh.create_global::<CompositorState, ZwpInputTimestampsManagerV1, _>(1, ());
        tracing::debug!("Registered zwp_input_timestamps_manager_v1");
        
        // Pointer warp - pointer teleportation
        use wayland_protocols::wp::pointer_warp::v1::server::wp_pointer_warp_v1::WpPointerWarpV1;
        dh.create_global::<CompositorState, WpPointerWarpV1, _>(1, ());
        tracing::debug!("Registered wp_pointer_warp_v1");
        
        // Color management - HDR and color space support
        // use wayland_protocols::wp::color_management::v1::server::wp_color_manager_v1::WpColorManagerV1;
        // dh.create_global::<CompositorState, WpColorManagerV1, _>(1, ());
        // tracing::debug!("Registered wp_color_manager_v1");
        
        // Color representation - color format hints
        use wayland_protocols::wp::color_representation::v1::server::wp_color_representation_manager_v1::WpColorRepresentationManagerV1;
        dh.create_global::<CompositorState, WpColorRepresentationManagerV1, _>(1, ());
        tracing::debug!("Registered wp_color_representation_manager_v1");
        
        // Security context - sandboxed client connections
        use wayland_protocols::wp::security_context::v1::server::wp_security_context_manager_v1::WpSecurityContextManagerV1;
        dh.create_global::<CompositorState, WpSecurityContextManagerV1, _>(1, ());
        tracing::debug!("Registered wp_security_context_manager_v1");
        
        // Transient seat - remote desktop input seats
        use wayland_protocols::ext::transient_seat::v1::server::ext_transient_seat_manager_v1::ExtTransientSeatManagerV1;
        dh.create_global::<CompositorState, ExtTransientSeatManagerV1, _>(1, ());
        tracing::debug!("Registered ext_transient_seat_manager_v1");
        
        // XDG toplevel tag - window tagging for session restore
        use wayland_protocols::xdg::toplevel_tag::v1::server::xdg_toplevel_tag_manager_v1::XdgToplevelTagManagerV1;
        dh.create_global::<CompositorState, XdgToplevelTagManagerV1, _>(1, ());
        tracing::debug!("Registered xdg_toplevel_tag_manager_v1");
        
        // XDG system bell - system notification sounds
        use wayland_protocols::xdg::system_bell::v1::server::xdg_system_bell_v1::XdgSystemBellV1;
        dh.create_global::<CompositorState, XdgSystemBellV1, _>(1, ());
        tracing::debug!("Registered xdg_system_bell_v1");
        
        // Fullscreen shell - kiosk mode shell
        // use wayland_protocols::wp::fullscreen_shell::zv1::server::zwp_fullscreen_shell_v1::ZwpFullscreenShellV1;
        // dh.create_global::<CompositorState, ZwpFullscreenShellV1, _>(1, ());
        // tracing::debug!("Registered zwp_fullscreen_shell_v1");
        
        // Foreign toplevel list - task bar support
        use wayland_protocols::ext::foreign_toplevel_list::v1::server::ext_foreign_toplevel_list_v1::ExtForeignToplevelListV1;
        dh.create_global::<CompositorState, ExtForeignToplevelListV1, _>(1, ());
        tracing::debug!("Registered ext_foreign_toplevel_list_v1");
        
        // Data control - clipboard managers
        use wayland_protocols::ext::data_control::v1::server::ext_data_control_manager_v1::ExtDataControlManagerV1;
        dh.create_global::<CompositorState, ExtDataControlManagerV1, _>(1, ());
        tracing::debug!("Registered ext_data_control_manager_v1");
        
        // Workspace - virtual desktop management
        use wayland_protocols::ext::workspace::v1::server::ext_workspace_manager_v1::ExtWorkspaceManagerV1;
        dh.create_global::<CompositorState, ExtWorkspaceManagerV1, _>(1, ());
        tracing::debug!("Registered ext_workspace_manager_v1");
        
        // Background effect - blur effects
        use wayland_protocols::ext::background_effect::v1::server::ext_background_effect_manager_v1::ExtBackgroundEffectManagerV1;
        dh.create_global::<CompositorState, ExtBackgroundEffectManagerV1, _>(1, ());
        tracing::debug!("Registered ext_background_effect_manager_v1");
        
        // Image capture source - screen capture sources
        use wayland_protocols::ext::image_capture_source::v1::server::ext_output_image_capture_source_manager_v1::ExtOutputImageCaptureSourceManagerV1;
        dh.create_global::<CompositorState, ExtOutputImageCaptureSourceManagerV1, _>(1, ());
        tracing::debug!("Registered ext_output_image_capture_source_manager_v1");
        
        // Image copy capture - screen capture
        use wayland_protocols::ext::image_copy_capture::v1::server::ext_image_copy_capture_manager_v1::ExtImageCopyCaptureManagerV1;
        dh.create_global::<CompositorState, ExtImageCopyCaptureManagerV1, _>(1, ());
        tracing::debug!("Registered ext_image_copy_capture_manager_v1");
        
        // XWayland keyboard grab - XWayland input
        use wayland_protocols::xwayland::keyboard_grab::zv1::server::zwp_xwayland_keyboard_grab_manager_v1::ZwpXwaylandKeyboardGrabManagerV1;
        dh.create_global::<CompositorState, ZwpXwaylandKeyboardGrabManagerV1, _>(1, ());
        tracing::debug!("Registered zwp_xwayland_keyboard_grab_manager_v1");
        
        // XWayland shell - XWayland surface integration
        use wayland_protocols::xwayland::shell::v1::server::xwayland_shell_v1::XwaylandShellV1;
        dh.create_global::<CompositorState, XwaylandShellV1, _>(1, ());
        tracing::debug!("Registered xwayland_shell_v1");
        
        // =====================================================================
        // wlroots protocols
        // =====================================================================
        
        // Layer shell
        use crate::core::wayland::protocol::wlroots::wlr_layer_shell_unstable_v1::zwlr_layer_shell_v1::ZwlrLayerShellV1;
        dh.create_global::<CompositorState, ZwlrLayerShellV1, _>(4, ());
        tracing::debug!("Registered zwlr_layer_shell_v1 v4");
        
        // Output management
        use crate::core::wayland::protocol::wlroots::wlr_output_management_unstable_v1::zwlr_output_manager_v1::ZwlrOutputManagerV1;
        dh.create_global::<CompositorState, ZwlrOutputManagerV1, _>(4, ());
        tracing::debug!("Registered zwlr_output_manager_v1 v4");
        
        // Output power management
        use crate::core::wayland::protocol::wlroots::wlr_output_power_management_unstable_v1::zwlr_output_power_manager_v1::ZwlrOutputPowerManagerV1;
        dh.create_global::<CompositorState, ZwlrOutputPowerManagerV1, _>(1, ());
        tracing::debug!("Registered zwlr_output_power_manager_v1 v1");
        
        // Foreign toplevel management
        use crate::core::wayland::protocol::wlroots::wlr_foreign_toplevel_management_unstable_v1::zwlr_foreign_toplevel_manager_v1::ZwlrForeignToplevelManagerV1;
        dh.create_global::<CompositorState, ZwlrForeignToplevelManagerV1, _>(3, ());
        tracing::debug!("Registered zwlr_foreign_toplevel_manager_v1 v3");
        
        // Screencopy
        use crate::core::wayland::protocol::wlroots::wlr_screencopy_unstable_v1::zwlr_screencopy_manager_v1::ZwlrScreencopyManagerV1;
        dh.create_global::<CompositorState, ZwlrScreencopyManagerV1, _>(3, ());
        tracing::debug!("Registered zwlr_screencopy_manager_v1 v3");
        
        // Gamma control
        use crate::core::wayland::protocol::wlroots::wlr_gamma_control_unstable_v1::zwlr_gamma_control_manager_v1::ZwlrGammaControlManagerV1;
        dh.create_global::<CompositorState, ZwlrGammaControlManagerV1, _>(1, ());
        tracing::debug!("Registered zwlr_gamma_control_manager_v1 v1");
        
        // Data control
        use crate::core::wayland::protocol::wlroots::wlr_data_control_unstable_v1::zwlr_data_control_manager_v1::ZwlrDataControlManagerV1;
        dh.create_global::<CompositorState, ZwlrDataControlManagerV1, _>(2, ());
        tracing::debug!("Registered zwlr_data_control_manager_v1 v2");
        
        // Export DMABUF
        use crate::core::wayland::protocol::wlroots::wlr_export_dmabuf_unstable_v1::zwlr_export_dmabuf_manager_v1::ZwlrExportDmabufManagerV1;
        dh.create_global::<CompositorState, ZwlrExportDmabufManagerV1, _>(1, ());
        tracing::debug!("Registered zwlr_export_dmabuf_manager_v1 v1");
        
        // Virtual pointer
        use crate::core::wayland::protocol::wlroots::wlr_virtual_pointer_unstable_v1::zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1;
        dh.create_global::<CompositorState, ZwlrVirtualPointerManagerV1, _>(2, ());
        tracing::debug!("Registered zwlr_virtual_pointer_manager_v1 v2");
        
        // Virtual keyboard
        use crate::core::wayland::protocol::wlroots::zwp_virtual_keyboard_v1::zwp_virtual_keyboard_manager_v1::ZwpVirtualKeyboardManagerV1;
        dh.create_global::<CompositorState, ZwpVirtualKeyboardManagerV1, _>(1, ());
        tracing::debug!("Registered zwp_virtual_keyboard_manager_v1 v1");
        
        Ok(())
    }
    
    // =========================================================================
    // Event Processing
    // =========================================================================
    
    /// Accept pending client connections
    pub fn accept_connections(&mut self, _state: &mut CompositorState) {
        // Accept new client connections from all sockets
        while let Some((_socket_type, stream)) = self.socket_manager.accept_any() {
            let client_id = self.next_client_id;
            self.next_client_id += 1;
            
            let client_data = WawonaClientData::new(client_id);
            
            match self.display.handle().insert_client(stream, Arc::new(client_data.clone())) {
                Ok(_) => {
                    tracing::info!("Accepted client connection: {}", client_id);
                    
                    // Track the client
                    self.clients.insert(client_id, client_data.clone());
                    
                    // Emit event
                    self.events.push(CompositorEvent::ClientConnected {
                        client_id,
                        pid: client_data.pid,
                    });
                }
                Err(e) => {
                    tracing::error!("Failed to insert client: {}", e);
                }
            }
        }
    }
    
    /// Dispatch pending Wayland events
    pub fn dispatch(&mut self, state: &mut CompositorState) -> Result<usize> {
        if !self.running {
            return Ok(0);
        }
        
        // Accept any pending connections first
        self.accept_connections(state);
        
        // Dispatch events to clients
        let dispatched = self.display.dispatch_clients(state)
            .context("Failed to dispatch Wayland events")?;
        
        // Flush client event queues
        self.display.flush_clients()
            .context("Failed to flush clients")?;
        
        // Fire presentation feedback for any committed frames
        state.fire_presentation_feedback();
        
        // Periodic heartbeat for shell clients (every 1 second)
        if self.last_ping.elapsed().as_secs() >= 1 {
            self.ping_clients(state);
            self.last_ping = Instant::now();
        }
        
        Ok(dispatched)
    }
    
    /// Dispatch with timeout (for poll-based event loops)
    pub fn dispatch_timeout(&mut self, state: &mut CompositorState, _timeout: Duration) -> Result<usize> {
        // TODO: Implement proper poll-based dispatch with timeout
        // For now, just dispatch without blocking
        self.dispatch(state)
    }
    
    /// Flush all client event queues
    pub fn flush(&mut self) -> Result<()> {
        self.display.flush_clients()
            .context("Failed to flush clients")?;
        Ok(())
    }
    
    // =========================================================================
    // Serial Numbers
    // =========================================================================
    
    /// Get the next serial number
    pub fn next_serial(&mut self) -> u32 {
        let serial = self.serial;
        self.serial = self.serial.wrapping_add(1);
        serial
    }
    
    /// Get current serial without incrementing
    pub fn current_serial(&self) -> u32 {
        self.serial
    }
    
    // =========================================================================
    // Events
    // =========================================================================
    
    /// Take all pending events (clears the internal queue)
    pub fn take_events(&mut self) -> Vec<CompositorEvent> {
        std::mem::take(&mut self.events)
    }
    
    /// Push an event to the queue
    pub fn push_event(&mut self, event: CompositorEvent) {
        self.events.push(event);
    }
    
    /// Check if there are pending events
    pub fn has_events(&self) -> bool {
        !self.events.is_empty()
    }
    
    // =========================================================================
    // Frame Timing
    // =========================================================================
    
    /// Get time since last frame in milliseconds
    pub fn time_since_last_frame_ms(&self) -> u32 {
        self.last_frame.elapsed().as_millis() as u32
    }
    
    /// Mark frame as complete
    pub fn mark_frame_complete(&mut self) {
        self.last_frame = Instant::now();
    }
    
    /// Get current timestamp in milliseconds (for Wayland events)
    pub fn timestamp_ms() -> u32 {
        use std::time::{SystemTime, UNIX_EPOCH};
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u32
    }
    
    // =========================================================================
    // Client Management
    // =========================================================================
    
    /// Get connected client count
    pub fn client_count(&self) -> usize {
        self.clients.len()
    }
    
    /// Get client IDs
    pub fn client_ids(&self) -> Vec<u32> {
        self.clients.keys().copied().collect()
    }
    
    // =========================================================================
    // Helpers
    // =========================================================================
    
    /// Ensure XDG_RUNTIME_DIR exists with proper permissions
    fn ensure_runtime_dir() -> Result<String> {
        use std::os::unix::fs::PermissionsExt;
        
        // Check if XDG_RUNTIME_DIR is already set
        if let Ok(dir) = std::env::var("XDG_RUNTIME_DIR") {
            if let Ok(metadata) = std::fs::metadata(&dir) {
                let perms = metadata.permissions();
                if perms.mode() & 0o777 == 0o700 {
                    return Ok(dir);
                }
            }
        }
        
        // Create runtime directory: /tmp/<UID>-runtime
        let uid = unsafe { libc::getuid() };
        let runtime_dir = format!("/tmp/{}-runtime", uid);
        
        // Create directory if it doesn't exist
        std::fs::create_dir_all(&runtime_dir)?;
        
        // Set strict permissions: 0700
        let mut perms = std::fs::metadata(&runtime_dir)?.permissions();
        perms.set_mode(0o700);
        std::fs::set_permissions(&runtime_dir, perms)?;
        
        // Set environment variable
        std::env::set_var("XDG_RUNTIME_DIR", &runtime_dir);
        
        tracing::debug!("Created XDG_RUNTIME_DIR: {}", runtime_dir);
        Ok(runtime_dir)
    }

    /// Send ping to all shell clients
    pub fn ping_clients(&mut self, state: &mut CompositorState) {
        let serial = self.next_serial();
        for shell in state.xdg_shell_resources.values() {
            shell.ping(serial);
        }
    }
}

impl Default for Compositor {
    fn default() -> Self {
        Self::new_default().expect("Failed to create default compositor")
    }
}

// ============================================================================
// Tests
// ============================================================================

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_config_default() {
        let config = CompositorConfig::default();
        assert_eq!(config.socket_name, "wayland-0");
        assert_eq!(config.output_width, 1920);
        assert_eq!(config.output_height, 1080);
    }
    
    #[test]
    fn test_serial_generation() {
        let mut compositor = Compositor::new_default().unwrap();
        assert_eq!(compositor.next_serial(), 1);
        assert_eq!(compositor.next_serial(), 2);
        assert_eq!(compositor.next_serial(), 3);
    }
}
