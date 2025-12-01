# Wawona Compositor - Progress Report

**Last Updated**: November 30, 2025

## Overview

Wawona is a Wayland compositor for iOS, macOS, and Android. This document tracks cross‑platform progress, including recent Android emulator bring‑up with Vulkan (SwiftShader fallback) and optional Freedreno/Turnip builds.

## Completed Features

### 1. iOS App Bundle Configuration ✅

- **Bundle Identifier**: `com.aspauldingcode.Wawona` (unified for both iOS and macOS)
- **Info.plist Generation**: CMake correctly generates iOS-specific `Info.plist` with proper bundle metadata
- **Settings.bundle Integration**: iOS Settings app integration with all compositor preferences
  - Display settings (Force Server-Side Decorations, Auto Retina Scaling)
  - Input settings (Render macOS Pointer, Swap Cmd as Ctrl, Universal Clipboard)
  - Color Management (ColorSync Support)
  - Advanced settings (Nested Compositors, Metal 4, Multiple Clients, Waypipe RS Support)
  - **Network / Remote Access**: Controls for TCP listener and port selection ✅
  - **Arbitrary Resolution Support**: Implemented `zwp_fullscreen_shell_v1` and `xdg_shell` improvements for dynamic resizing.

### 2. Wayland Socket Creation ✅

- **Unix Socket Support**: Primary method using `wl_display_add_socket()` with short socket name "w0"
- **TCP Socket Fallback**: Automatic fallback when Unix socket path exceeds 108-byte limit
- **Remote Access Support**: Configurable TCP listener (0.0.0.0) for external client connections ✅
  - Controlled via Settings app ("Enable TCP Listener", "TCP Port")
  - Enables connecting clients like `waypipe` from other machines
- **Path Length Detection**: Proactive checking before socket creation with informative error messages
- **Sandbox Compliance**: All sockets created within app's temporary directory (`NSTemporaryDirectory()`)

### 3. Connection Handling ✅

- **Internal Client (Socketpair)**: Uses `socketpair(AF_UNIX)` for reliable in-process communication
  - Bypasses TCP limitations (supports file descriptor passing via `SCM_RIGHTS`)
  - Secure and robust (no external port exposed for internal client)
  - Fully compliant with Wayland protocol (SHM buffer passing works)
- **External Client (TCP)**: Timer-based manual accept() loop for external connections (e.g. `waypipe`)
  - Timer fires every 50ms to check for pending connections
  - Manual check in event loop dispatch for immediate acceptance
  - Non-blocking socket operations
- **Wayland Integration**: 
  - Internal clients created via `wl_client_create()` with socketpair FD
  - External TCP clients accepted and added via `wl_client_create()`
- **Authentication Patch**: Patched `libwayland-server` to bypass peer credential checks for TCP sockets on iOS (required for `wl_client_create`)

### 4. iOS Launcher Client ✅

- **In-Process Implementation**: App Store compliant - runs as Wayland client within the compositor process
- **Thread-Based**: Uses `pthread` for background execution (no `posix_spawn` - App Store compliant)
- **Socketpair Connection**: Connects via pre-created socketpair FD passed from main thread
- **Wayland Protocol**: Implements registry listener and binds to `wl_compositor`, `xdg_wm_base`, `wl_seat`, `wl_shm`
- **Surface Creation**: Creates Wayland surface for launcher UI
- **SHM Buffer**: Creates shared memory buffer using `mkstemp` + `mmap` (compatible with iOS)
- **Rendering**: Renders visible UI (buttons) with dynamic resizing support
- **Input Handling**: Processes touch events and updates UI state
- **XDG Shell Support**: Handles window management and resizing events

### 5. Build System ✅

- **Fast Rebuild Target**: `make ios-compositor-fast` - skips dependency rebuilds if already present
- **Dependency Management**: Modular targets (`build-ios-deps`, `check-ios-deps`, `build-launch-ios`)
- **CMake Integration**: Proper iOS toolchain configuration and resource bundling

## Current Status

### Working Components

1. ✅ iOS app bundle creation and installation
2. ✅ Wayland compositor initialization
3. ✅ TCP socket creation (local and remote access)
4. ✅ Launcher client connection (via socketpair)
5. ✅ Registry Roundtrip (handshake complete)
6. ✅ **Visible Launcher UI**: 800x600 surface (resizable) with buttons
7. ✅ **Touch Input**: Touch events are detected and processed (Crash fixed, Frame events added)
8. ✅ **External Connections**: TCP listener supports remote clients
9. ✅ **Rotation/Resizing**: Thread-safe output resizing implemented (Weston integration pending verification)
10. ✅ **Android Emulator App Launch**: JNI app builds, installs, launches; Vulkan instance/Surface created
11. ✅ **Android Vulkan Fallback**: SwiftShader ICD selected on Apple Silicon emulator; present loop clears frames

### In Progress

1. **Weston Resizing**: Verify Weston properly resizes its surface on screen rotation (Possible `arbitrary resolutions` flag issue).
2. **Performance**: Evaluate frame rate and responsiveness
3. **Android Compositor Frames**: Wire Wawona compositor frames into Vulkan swapchain (copy/blit, then textured pipeline)

## Android Progress

### Overview

- Minimal Android app via Gradle with JNI Vulkan renderer:
  - Creates `VkInstance` with fallback to SwiftShader ICD
  - Creates `VkSurfaceKHR` from `ANativeWindow`
  - Picks graphics queue, creates swapchain and render pass
  - Records per‑image command buffers to clear and present

### Emulator Bring‑Up (Apple Silicon)

- AVD: `pixel3_arm64` using `system-images;android-35;google_apis;arm64-v8a`
- Emulator booted headless with SwiftShader Vulkan ICD configured by emulator
- App installs and starts via `adb`; logs confirm Vulkan device enumeration and surface creation

### Driver Separation & Gating

- Apple (macOS/iOS): Angle (EGL) + KosmicKrisp (Vulkan); EGL compilation stubs on Apple where needed
- Android: Freedreno/Turnip (Vulkan) + Gallium freedreno (EGL)
- Environment gating in `scripts/android-compositor.sh`:
  - `BUILD_FREEDRENO=1` builds libdrm+Mesa and pushes Freedreno ICD; default skips to SwiftShader/emulator Vulkan

### Build Script Improvements

- Meson cross file uses built‑in options for target/sysroot
- Stubbed Android pkg-config entries: `cutils`, `hardware`, `log`, `sync`, `nativewindow`
- Added header stubs used by Mesa (`cutils/trace.h`, `log/log.h`, `cutils/properties.h`, `sync/sync.h`)
- Removed duplicate `ETIME` definitions from cross file to avoid macro redefinition warnings; rely on Mesa patch to add `-DETIME=ETIMEDOUT`

### Commands

```bash
# Build and run Android emulator app (headless)
make android-compositor

# Optional: build and push Freedreno Vulkan driver (if supported)
BUILD_FREEDRENO=1 make android-compositor

# Inspect logs
adb -e logcat -d | grep -i WawonaJNI | tail -n 50
```

## Technical Details

### iOS Sandbox Constraints

- **File System**: Limited to app container directory
- **Unix Sockets**: 108-byte path length limit enforced
- **Process Spawning**: `posix_spawn` restricted (using in-process clients instead)
- **Network**: TCP sockets allowed within sandbox (localhost only by default, 0.0.0.0 if configured)

### Architecture Decisions

1. **In-Process Launcher**: Required for App Store compliance - no separate process spawning
2. **Socketpair for Internal Client**: Solves file descriptor passing issue (SHM support) and path length limits
3. **TCP Socket Fallback/Remote**: For external clients where Unix sockets fail or for remote access
4. **`wl_client_create`**: Used to add clients (internal & external) to the display
5. **`libwayland` Patch**: Modified `wl_os_socket_peercred` to allow TCP connections on iOS

### App Store Compliance Analysis

- **In-Process Client**: ✅ Compliant. Uses standard threading (`pthread`/`NSThread`), no prohibited process spawning APIs.
- **Socketpair (IPC)**: ✅ Compliant. Standard POSIX API used strictly within the app sandbox.
- **Shared Memory**: ✅ Compliant. Uses `mkstemp` in app's temporary directory and `mmap`.
- **Network**: ✅ Compliant. TCP sockets used for local communication (fallback) or user-enabled remote access.
- **Code Loading**: ✅ Compliant. All code is statically compiled into the app bundle.

### Key Files

- `src/main.m`: iOS app delegate, socket creation, launcher thread management
- `src/WawonaCompositor.m`: Compositor implementation, TCP accept() handling
- `src/ios_launcher_client.m`: In-process Wayland client launcher
- `src/resources/Settings.bundle/Root.plist`: iOS Settings app configuration
- `src/WawonaPreferencesManager.m`: Settings handling
- `src/wayland_seat.c`: Input handling and device resource management
 - `scripts/android-compositor.sh`: Android SDK/NDK provisioning, AVD boot, app build/install, driver gating
 - `scripts/create-android-app.sh`: Gradle project generator and JNI wiring
 - `src/android_jni.c`: Vulkan instance/surface/swapchain and present loop

## Build Commands

```bash
# Full build (with dependencies)
make ios-compositor

# Fast rebuild (skip dependencies if already built)
make ios-compositor-fast

# Android build and run (emulator)
make android-compositor
```

## Environment Variables

When TCP socket is used:
- `WAYLAND_DISPLAY=wayland-0`
- `WAYLAND_TCP_PORT=<port_number>`
- `XDG_RUNTIME_DIR=<app_temp_directory>`
