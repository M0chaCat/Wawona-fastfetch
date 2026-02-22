//! Standardized logging utility for Wawona
//! 
//! This module provides the `wlog!` macro which ensures all Rust logs
//! follow the `YYYY-MM-DD HH:MM:SS [MODULE] Message` format.



#[macro_export]
macro_rules! wlog {
    ($module:expr, $($arg:tt)*) => {{
        let now = chrono::Local::now();
        eprintln!("{} [{}] {}", 
            now.format("%Y-%m-%d %H:%M:%S"),
            $module,
            format!($($arg)*)
        );
    }};
}

/// Per-frame trace logging — compiled out by default.
/// Build with `--features verbose-logs` to enable.
#[macro_export]
macro_rules! wtrace {
    ($module:expr, $($arg:tt)*) => {{
        #[cfg(feature = "verbose-logs")]
        {
            let now = chrono::Local::now();
            eprintln!("{} [{}] {}", 
                now.format("%Y-%m-%d %H:%M:%S"),
                $module,
                format!($($arg)*)
            );
        }
        #[cfg(not(feature = "verbose-logs"))]
        {
            let _ = ($module, format_args!($($arg)*));
        }
    }};
}

/// Standardized module identifiers
pub const MAIN: &str = "MAIN";
pub const CORE: &str = "CORE";
pub const FFI: &str = "FFI";
pub const BRIDGE: &str = "BRIDGE";
pub const WAYLAND: &str = "WAYLAND";
pub const METAL: &str = "METAL";
pub const INPUT: &str = "INPUT";
pub const C_API: &str = "C_API";
pub const SEAT: &str = "SEAT";
pub const DISPLAY: &str = "DISPLAY";
pub const COMPOSITOR: &str = "COMPOSITOR";
pub const STATE: &str = "STATE";
pub const PREFS: &str = "PREFS";
pub const BUFFER: &str = "BUFFER";
