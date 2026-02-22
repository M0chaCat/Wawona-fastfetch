

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DecorationMode {
    ClientSide,
    ServerSide,
}

/// Represents a top-level window (XDG Toplevel).
///
/// Corresponds to `WawonaWindowContainer`.
pub struct Window {
    pub id: u32,
    pub title: String,
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub decoration_mode: DecorationMode,
    pub surface_id: u32,
    pub app_id: String,
    
    // Window state
    pub maximized: bool,
    pub minimized: bool,
    pub fullscreen: bool,
    pub activated: bool,
    pub resizing: bool,
    /// Whether this window is a modal dialog
    pub modal: bool,
    
    /// IDs of outputs this window is visible on
    pub outputs: Vec<u32>,
}

impl Window {
    pub fn new(id: u32, surface_id: u32) -> Self {
        Self {
            id,
            title: "Wawona Window".to_string(),
            x: 0,
            y: 0,
            width: 800,
            height: 600,
            decoration_mode: DecorationMode::ClientSide,
            surface_id,
            app_id: "".to_string(),
            maximized: false,
            minimized: false,
            fullscreen: false,
            activated: false,
            resizing: false,
            modal: false,
            outputs: Vec::new(),
        }
    }

    pub fn geometry(&self) -> crate::util::geometry::Rect {
        crate::util::geometry::Rect {
            x: self.x,
            y: self.y,
            width: self.width as u32,
            height: self.height as u32,
        }
    }
}
