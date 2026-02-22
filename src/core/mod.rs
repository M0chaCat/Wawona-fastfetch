pub mod errors;
pub mod traits;
pub mod state;

pub mod compositor;
pub mod runtime;
pub mod socket_manager;
pub mod wayland;
pub mod surface;
pub mod window;
pub mod input;
pub mod render;
pub mod ipc;
pub mod time;


// Re-export key types
pub use compositor::{Compositor, CompositorConfig, CompositorEvent};
pub use runtime::{Runtime, FrameTiming, FrameTimingConfig};
pub use state::CompositorState;
