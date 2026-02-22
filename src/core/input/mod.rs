pub mod xkb;
pub mod keyboard;
pub mod pointer;
pub mod touch;
pub mod seat;

// Re-export key types for convenience
pub use keyboard::KeyboardState;
pub use pointer::PointerState;
pub use touch::TouchState;
pub use seat::Seat;
pub use xkb::{XkbContext, XkbState, KeyResult};

/// Button/Key state
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum KeyState {
    Released = 0,
    Pressed = 1,
}

pub type ButtonState = KeyState;

/// Input event type for internal core usage
#[derive(Debug, Clone)]
pub enum InputEvent {
    PointerMotion {
        x: f64,
        y: f64,
        time_ms: u32,
    },
    PointerButton {
        button: u32,
        state: ButtonState,
        time_ms: u32,
    },
    PointerAxis {
        horizontal: f64,
        vertical: f64,
        time_ms: u32,
    },
    KeyboardKey {
        keycode: u32,
        state: KeyState,
        time_ms: u32,
    },
    KeyboardModifiers {
        depressed: u32,
        latched: u32,
        locked: u32,
        group: u32,
    },
    TouchDown {
        id: i32,
        x: f64,
        y: f64,
        time_ms: u32,
    },
    TouchUp {
        id: i32,
        time_ms: u32,
    },
    TouchMotion {
        id: i32,
        x: f64,
        y: f64,
        time_ms: u32,
    },
    TouchCancel,
    TouchFrame,
}
