//! wlr-foreign-toplevel-management-unstable-v1 protocol
//!
//! Task bars, window lists, window switchers.

pub use wayland_server;
pub use wayland_server::protocol::{wl_output, wl_seat, wl_surface};
pub use bitflags;

wayland_scanner::generate_server_code!("protocols/wlroots/wlr-foreign-toplevel-management-unstable-v1.xml");
