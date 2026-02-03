// C FFI Exports (Plain C, no mangling)
// These are callable directly from Objective-C without Swift
use std::os::raw::c_char;
use std::ffi::{CStr, CString};
use std::sync::Arc;
use super::api::WawonaCore;
use super::types::{WindowId, PointerButton, ButtonState, KeyState, KeyboardModifiers};


/// Create a new WawonaCore instance
#[no_mangle]
pub extern "C" fn wawona_core_new() -> *mut WawonaCore {
    let core = WawonaCore::new();
    Arc::into_raw(core) as *mut WawonaCore
}

/// Start the compositor
#[no_mangle]
pub extern "C" fn wawona_core_start(
    core: *mut WawonaCore,
    socket_name: *const c_char
) -> bool {
    if core.is_null() {
        return false;
    }
    
    let core = unsafe { &*core };
    let socket = if socket_name.is_null() {
        None
    } else {
        unsafe { CStr::from_ptr(socket_name) }
            .to_str()
            .ok()
            .map(|s| s.to_string())
    };
    
    match core.start(socket) {
        Ok(()) => {
            crate::wlog!(crate::util::logging::C_API, "Compositor started successfully");
            true
        }
        Err(e) => {
            crate::wlog!(crate::util::logging::C_API, "Compositor start failed: {:?}", e);
            false
        }
    }
}

/// Stop the compositor
#[no_mangle]
pub extern "C" fn wawona_core_stop(core: *mut WawonaCore) -> bool {
    if core.is_null() {
        return false;
    }
    
    let core = unsafe { &*core };
    core.stop().is_ok()
}

/// Check if compositor is running
#[no_mangle]
pub extern "C" fn wawona_core_is_running(core: *const WawonaCore) -> bool {
    if core.is_null() {
        return false;
    }
    
    let core = unsafe { &*core };
    core.is_running()
}

/// Get socket path (returns malloc'd string, caller must free)
#[no_mangle]
pub extern "C" fn wawona_core_get_socket_path(core: *const WawonaCore) -> *mut c_char {
    if core.is_null() {
        return std::ptr::null_mut();
    }
    
    let core = unsafe { &*core };
    let path = core.get_socket_path();
    
    CString::new(path).ok()
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Get socket name (returns malloc'd string, caller must free)
#[no_mangle]
pub extern "C" fn wawona_core_get_socket_name(core: *const WawonaCore) -> *mut c_char {
    if core.is_null() {
        return std::ptr::null_mut();
    }
    
    let core = unsafe { &*core };
    let name = core.get_socket_name();
    
    CString::new(name).ok()
        .map(|s| s.into_raw())
        .unwrap_or(std::ptr::null_mut())
}

/// Free a string returned by this API
#[no_mangle]
pub extern "C" fn wawona_string_free(s: *mut c_char) {
    if !s.is_null() {
        unsafe { drop(CString::from_raw(s)); }
    }
}

/// Process events
#[no_mangle]
pub extern "C" fn wawona_core_process_events(core: *mut WawonaCore) -> bool {
    if core.is_null() {
        return false;
    }
    
    let core = unsafe { &*core };
    core.process_events()
}

/// Set output size
#[no_mangle]
pub extern "C" fn wawona_core_set_output_size(
    core: *mut WawonaCore,
    width: u32,
    height: u32,
    scale: f32
) {
    if core.is_null() {
        return;
    }
    
    let core = unsafe { &*core };
    core.set_output_size(width, height, scale);
}

/// Set force SSD policy
#[no_mangle]
pub extern "C" fn wawona_core_set_force_ssd(
    core: *mut WawonaCore,
    enabled: bool
) {
    if core.is_null() {
        return;
    }
    
    let core = unsafe { &*core };
    core.set_force_ssd(enabled);
}

/// Inject window resize
#[no_mangle]
pub extern "C" fn wawona_core_inject_window_resize(
    core: *mut WawonaCore,
    window_id: u64,
    width: u32,
    height: u32
) {
    if core.is_null() { return; }
    let core = unsafe { &*core };
    core.resize_window(WindowId { id: window_id }, width, height);
}

/// Set window activation state (focus)
#[no_mangle]
pub extern "C" fn wawona_core_set_window_activated(
    core: *mut WawonaCore,
    window_id: u64,
    active: bool
) {
    if core.is_null() { return; }
    let core = unsafe { &*core };
    core.set_window_activated(WindowId { id: window_id }, active);
}

/// Free WawonaCore instance
#[no_mangle]
pub extern "C" fn wawona_core_free(core: *mut WawonaCore) {
    if !core.is_null() {
        unsafe {
            drop(Arc::from_raw(core));
        }
    }
}

/// C-compatible window event type
#[repr(u32)]
#[derive(Debug, Copy, Clone)]
pub enum CWindowEventType {
    Created = 0,
    Destroyed = 1,
    TitleChanged = 2,
    SizeChanged = 3,
    PopupCreated = 4,
    PopupRepositioned = 5,
}

/// C-compatible window event structure
#[repr(C)]
pub struct CWindowEvent {
    pub event_type: u64, // Use u64 for alignment stability
    pub window_id: u64,
    pub surface_id: u32,
    pub title: *mut c_char,
    pub width: u32,
    pub height: u32,
    pub parent_id: u64,
    pub x: i32,
    pub y: i32,
    pub padding: u32, // explicit padding for the 8-byte boundary if needed
}

/// Pop the next pending window event
#[no_mangle]
pub extern "C" fn wawona_core_pop_window_event(core: *mut WawonaCore) -> *mut CWindowEvent {
    if core.is_null() {
        return std::ptr::null_mut();
    }
    
    let core = unsafe { &*core };
    
    if let Some(event) = core.pop_window_event() {
        let mut c_event = Box::new(CWindowEvent {
            event_type: CWindowEventType::Created as u64, // Default
            window_id: 0,
            surface_id: 0,
            title: std::ptr::null_mut(),
            width: 0,
            height: 0,
            parent_id: 0,
            x: 0,
            y: 0,
            padding: 0,
        });

        let should_return = match event {
            super::types::WindowEvent::Created { window_id, config } => {
                c_event.event_type = CWindowEventType::Created as u64;
                c_event.window_id = window_id.id;
                // We don't have surface_id in Created event from api.rs yet, 
                // but we might need it for completeness. For now just window_id is fine for toplevels.
                // However, the event from CompositorEvent has it.
                // Let's check api.rs handle_compositor_event
                c_event.width = config.width;
                c_event.height = config.height;
                c_event.title = CString::new(config.title).ok()
                    .map(|s| s.into_raw())
                    .unwrap_or(std::ptr::null_mut());
                true
            },
            super::types::WindowEvent::Destroyed { window_id } => {
                c_event.event_type = CWindowEventType::Destroyed as u64;
                c_event.window_id = window_id.id;
                true
            },
            super::types::WindowEvent::TitleChanged { window_id, title } => {
                c_event.event_type = CWindowEventType::TitleChanged as u64;
                c_event.window_id = window_id.id;
                c_event.title = CString::new(title).ok()
                    .map(|s| s.into_raw())
                    .unwrap_or(std::ptr::null_mut());
                true
            },
            super::types::WindowEvent::SizeChanged { window_id, width, height } => {
                c_event.event_type = CWindowEventType::SizeChanged as u64;
                c_event.window_id = window_id.id;
                c_event.width = width;
                c_event.height = height;
                true
            },
            super::types::WindowEvent::PopupCreated { window_id, parent_id, x, y, width, height } => {
                c_event.event_type = CWindowEventType::PopupCreated as u64;
                c_event.window_id = window_id.id;
                c_event.parent_id = parent_id.id;
                c_event.x = x;
                c_event.y = y;
                c_event.width = width;
                c_event.height = height;
                
                // For popups, the surface_id is often the same as window_id in this compositor's internal mapping
                c_event.surface_id = window_id.id as u32; 

                tracing::info!("FFI: PopupCreated {} parent={} at {},{}", window_id.id, parent_id.id, x, y);
                true
            },
            super::types::WindowEvent::PopupRepositioned { window_id, x, y, width, height } => {
                c_event.event_type = CWindowEventType::PopupRepositioned as u64;
                c_event.window_id = window_id.id;
                c_event.x = x;
                c_event.y = y;
                c_event.width = width;
                c_event.height = height;
                tracing::info!("FFI: PopupRepositioned {} at {},{} {}x{}", window_id.id, x, y, width, height);
                true
            },
            _ => {
                // Ignore other events for now
                false
            }
        };
        
        if should_return {
            return Box::into_raw(c_event);
        } else {
            // Box is dropped here automatically
        }
    }
    
    std::ptr::null_mut()
}

/// Free a CWindowEvent structure
#[no_mangle]
pub extern "C" fn wawona_window_event_free(event: *mut CWindowEvent) {
    if !event.is_null() {
        unsafe {
            let event = Box::from_raw(event);
            if !event.title.is_null() {
                drop(CString::from_raw(event.title));
            }
        }
    }
}

/// C-compatible window info structure
#[repr(C)]
pub struct CWindowInfo {
    pub window_id: u64,
    pub width: u32,
    pub height: u32,
    pub title: *mut c_char,  // Caller must free with wawona_string_free
}

/// Get count of pending window created events
#[no_mangle]
pub extern "C" fn wawona_core_pending_window_count(core: *const WawonaCore) -> u32 {
    if core.is_null() {
        return 0;
    }
    0
}

/// Pop and return the next pending window creation info
/// Returns NULL if no pending windows
/// Caller must free title with wawona_string_free
#[no_mangle]
pub extern "C" fn wawona_core_pop_pending_window(_core: *mut WawonaCore) -> *mut CWindowInfo {
    // DEPRECATED: Use wawona_core_pop_window_event instead
    std::ptr::null_mut()
}

/// Free a CWindowInfo structure
#[no_mangle]
pub extern "C" fn wawona_window_info_free(info: *mut CWindowInfo) {
    if !info.is_null() {
        unsafe {
            let info = Box::from_raw(info);
            if !info.title.is_null() {
                drop(CString::from_raw(info.title));
            }
        }
    }
}

/// C-compatible buffer data structure
#[repr(C)]
pub struct CBufferData {
    pub window_id: u64,
    pub surface_id: u32,
    pub buffer_id: u64,
    pub width: u32,
    pub height: u32,
    pub stride: u32,
    pub format: u32,
    pub pixels: *mut u8,       // Pointer to pixel data (leaked Vec)
    pub size: usize,           // Size of pixel data
    pub capacity: usize,       // Capacity of pixel data (for freeing)
    pub iosurface_id: u32,
}

/// Pop the next pending buffer update
/// Returns NULL if no updates
/// Caller must free with wawona_buffer_data_free
#[no_mangle]
pub extern "C" fn wawona_core_pop_pending_buffer(core: *mut WawonaCore) -> *mut CBufferData {
    if core.is_null() {
        return std::ptr::null_mut();
    }
    
    let core = unsafe { &*core };
    
    if let Some(event) = core.pop_pending_buffer() {
        // Extract data based on buffer type
        match event.buffer.data {
            super::types::BufferData::Shm { pixels, width, height, stride, format: _ } => {
                // Convert Vec<u8> to raw pointer by leaking it
                // We must reconstruct and drop this Vec later in free()
                let mut pixels = pixels;
                let size = pixels.len();
                let capacity = pixels.capacity();
                let ptr = pixels.as_mut_ptr();
                std::mem::forget(pixels);
                
                let data = Box::new(CBufferData {
                    window_id: event.window_id.id,
                    surface_id: event.surface_id.id,
                    buffer_id: event.buffer.id.id,
                    width,
                    height,
                    stride,
                    format: 0, // 0 for ARGB8888 for now (BufferFormat is enum)
                    pixels: ptr,
                    size,
                    capacity,
                    iosurface_id: 0,
                });
                
                return Box::into_raw(data);
            },
            super::types::BufferData::Iosurface { id, width, height, format } => {
                let data = Box::new(CBufferData {
                    window_id: event.window_id.id,
                    surface_id: event.surface_id.id,
                    buffer_id: event.buffer.id.id,
                    width,
                    height,
                    stride: 0, 
                    format,
                    pixels: std::ptr::null_mut(),
                    size: 0,
                    capacity: 0,
                    iosurface_id: id,
                });
                return Box::into_raw(data);
            },
            _ => {
                // Handle DMA-BUF later
                return std::ptr::null_mut();
            }
        }
    }
    
    std::ptr::null_mut()
}

/// Free a CBufferData structure and its pixel data
#[no_mangle]
pub extern "C" fn wawona_buffer_data_free(data: *mut CBufferData) {
    if !data.is_null() {
        unsafe {
            let data = Box::from_raw(data);
            if !data.pixels.is_null() && data.capacity > 0 {
                // Reconstruct Vec to drop it and free memory
                let _ = Vec::from_raw_parts(data.pixels, data.size, data.capacity);
            }
        }
    }
}

/// Notify that a frame has been presented
#[no_mangle]
pub extern "C" fn wawona_core_notify_frame_presented(
    core: *mut WawonaCore,
    surface_id: u32,
    buffer_id: u64,
    timestamp: u32
) {
    if core.is_null() { return; }
    let core = unsafe { &*core };
    
    let sid = super::types::SurfaceId { id: surface_id };
    let bid = if buffer_id != 0 {
        Some(super::types::BufferId { id: buffer_id })
    } else {
        None
    };
    
    core.notify_frame_presented(sid, bid, timestamp);
}

// ----------------------------------------------------------------------------
// Input Injection API
// ----------------------------------------------------------------------------

/// Inject pointer motion event
#[no_mangle]
pub extern "C" fn wawona_core_inject_pointer_motion(
    core: *mut WawonaCore,
    window_id: u64,
    x: f64,
    y: f64,
    timestamp_ms: u32
) {
    if core.is_null() { return; }
    let core = unsafe { &*core };
    core.inject_pointer_motion(WindowId { id: window_id }, x, y, timestamp_ms);
}

/// Inject pointer button event
/// request_code: Linux input event code (0x110=BTN_LEFT, etc)
/// state: 0 = Released, 1 = Pressed
#[no_mangle]
pub extern "C" fn wawona_core_inject_pointer_button(
    core: *mut WawonaCore,
    window_id: u64,
    button_code: u32,
    state: u32,
    timestamp_ms: u32
) {
    if core.is_null() { return; }
    let core = unsafe { &*core };
    
    let button = PointerButton::from_button_code(button_code);
    let button_state = if state == 1 { ButtonState::Pressed } else { ButtonState::Released };
    
    core.inject_pointer_button(WindowId { id: window_id }, button, button_state, timestamp_ms);
}

/// Inject pointer enter event
#[no_mangle]
pub extern "C" fn wawona_core_inject_pointer_enter(
    core: *mut WawonaCore,
    window_id: u64,
    x: f64,
    y: f64,
    timestamp_ms: u32
) {
    if core.is_null() { return; }
    let core = unsafe { &*core };
    core.inject_pointer_enter(WindowId { id: window_id }, x, y, timestamp_ms);
}

/// Inject pointer leave event
#[no_mangle]
pub extern "C" fn wawona_core_inject_pointer_leave(
    core: *mut WawonaCore,
    window_id: u64,
    timestamp_ms: u32
) {
    if core.is_null() { return; }
    let core = unsafe { &*core };
    core.inject_pointer_leave(WindowId { id: window_id }, timestamp_ms);
}

/// Inject keyboard key event
/// keycode: Linux key code
/// state: 0 = Released, 1 = Pressed
#[no_mangle]
pub extern "C" fn wawona_core_inject_key(
    core: *mut WawonaCore,
    keycode: u32,
    state: u32,
    timestamp_ms: u32
) {
    if core.is_null() { return; }
    let core = unsafe { &*core };
    
    let key_state = if state == 1 { KeyState::Pressed } else { KeyState::Released };
    
    core.inject_key(keycode, key_state, timestamp_ms);
}

/// Inject keyboard modifiers
#[no_mangle]
pub extern "C" fn wawona_core_inject_modifiers(
    core: *mut WawonaCore,
    mods_depressed: u32,
    mods_latched: u32,
    mods_locked: u32,
    group: u32
) {
    if core.is_null() { return; }
    let core = unsafe { &*core };
    
    let modifiers = KeyboardModifiers {
        mods_depressed,
        mods_latched,
        mods_locked,
        group,
    };
    
    core.inject_modifiers(modifiers);
}

/// Inject keyboard enter event
#[no_mangle]
pub extern "C" fn wawona_core_inject_keyboard_enter(
    core: *mut WawonaCore,
    window_id: u64,
    keys: *const u32,
    count: usize
) {
    if core.is_null() { return; }
    let core = unsafe { &*core };
    
    let key_slice = if keys.is_null() || count == 0 {
        &[]
    } else {
        unsafe { std::slice::from_raw_parts(keys, count) }
    };
    
    // Convert slice to Vec for API compliance
    let keys_vec = key_slice.to_vec();
    core.inject_keyboard_enter(WindowId { id: window_id }, keys_vec);
}

/// Inject keyboard leave event
#[no_mangle]
pub extern "C" fn wawona_core_inject_keyboard_leave(
    core: *mut WawonaCore,
    window_id: u64
) {
    if core.is_null() { return; }
    let core = unsafe { &*core };
    core.inject_keyboard_leave(WindowId { id: window_id });
}
