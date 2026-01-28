use wawona::platform::{Platform, api::StubPlatform};
use anyhow::Result;

fn main() -> Result<()> {
    // Initialize logging
    // Set default log level to info
    if std::env::var("RUST_LOG").is_err() {
        std::env::set_var("RUST_LOG", "info,wawona=debug");
    }
    // Initialize logging with standardized format
    tracing_subscriber::fmt()
        .with_timer(tracing_subscriber::fmt::time::ChronoLocal::new("%Y-%m-%d %H:%M:%S".to_string()))
        .with_ansi(false)
        .init();

    // Check for version argument
    let args: Vec<String> = std::env::args().collect();
    if args.len() > 1 && (args[1] == "--version" || args[1] == "-v") {
        println!("wawona {}", include_str!("../VERSION").trim());
        return Ok(());
    }

    // Create a stub platform app (actual frontends are native/FFI)
    let mut app = StubPlatform;
    
    // Initialize the platform (this sets up the event loop, etc.)
    app.initialize()?;

    // Run the application
    app.run()?;

    Ok(())
}
