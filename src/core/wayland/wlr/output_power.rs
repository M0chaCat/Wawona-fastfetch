//! wlr-output-power-management-unstable-v1 protocol
//!
//! Display power management (DPMS).

pub use wayland_server;
pub use wayland_server::protocol::wl_output;
pub use bitflags;

wayland_scanner::generate_server_code!("protocols/wlroots/wlr-output-power-management-unstable-v1.xml");
