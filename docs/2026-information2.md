Wawona is a native wayland compositor for macOS. it takes advantage of our waypipe fork for macOS, which utilices Vulkan 1.3 conformant userland driver “KosmicKrisp" for macOS (which compiles to libvulkan.dylib), and is used as a runtime loader for use with waypipe on macOS. 

That allows us to render macOS Windows with wayland clients on the surface. 

What we need to focus on:
We need to focus on adding support for window resize, focus, keyboard input, drawing methods, and other wayland protocol implementations for macOS Windows.

Here’s how I test wayland clients; I use nix run.#waypip-macos to pipe in a local linux machine running a bunch of weston compositor and libweston wayland software. This serves as test apps for me to use against Wawona for macOS.

I first run nix run .#wawona-macos to get the macOS Wayland compositor up and running.

Each wayland client I connect to macOS (via Wawona Compositor), will render as a seperate native macOS Window. Wawona should support Nested Compositors in a macOS Window. 


This means I need to support all of wayland’s (Updated) protocols. 


