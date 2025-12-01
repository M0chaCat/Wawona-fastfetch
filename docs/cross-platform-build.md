# Wawona Cross-Platform Build (macOS + iOS)

## Overview
- Platform-specific dependencies are isolated:
  - macOS: `macos-dependencies`
  - iOS: `ios-dependencies`
- App bundles are built under `build/`:
  - macOS: `build/Wawona.app/Contents/MacOS/Wawona`
  - iOS (Simulator): `build/build-ios/Wawona.app/Wawona`
- Unified parallel target: `make Wawona` builds both platforms simultaneously with tagged logs.

## Quick Start
- Clean everything from scratch:
  - `make clean-all`
- Build both platforms in parallel:
  - `make Wawona`
- Build individually:
  - macOS: `make macos-compositor`
  - iOS (Simulator): `make ios-compositor`

## Dependency Isolation
- All install script entries respect `--platform` and install to the matching directory:
  - macOS scripts put outputs in `macos-dependencies/{bin,lib,include,Frameworks}`
  - iOS scripts put outputs in `ios-dependencies/{bin,lib,include,Frameworks}`
- Makefile `clean-deps` removes both dependency trees.

## Build Flags and Warnings
- CMake sets strict warnings but suppresses noise in platform stubs:
  - `-Wno-unused-parameter`, `-Wno-unused-function`, `-Wno-unused-variable`
  - `-Wno-sign-conversion`, `-Wno-implicit-float-conversion`
  - `-Wno-missing-field-initializers`, `-Wno-format-nonliteral`, `-Wno-format-pedantic`, `-Wno-cast-qual`, `-Wno-empty-translation-unit`
- Link warnings are silenced with `-Wl,-w`.

## Sandbox-Safe Runtime
- macOS and iOS set `XDG_RUNTIME_DIR` to a sandbox-safe temp directory:
  - iOS: Simulator app container `tmp/`
  - macOS: `NSTemporaryDirectory()` (via environment)
- Wayland socket: `wayland-0` (or `w0`), created under the runtime dir.

## Feature Parity Notes
- Vulkan (KosmicKrisp):
  - macOS: headers installed; Vulkan renderer disabled unless static driver available.
  - iOS: headers installed; Vulkan bridge compiled out (`HAVE_VULKAN=0`) pending driver availability.
- Waypipe-rs:
  - macOS: built without dmabuf/video when Vulkan driver absent; still usable for non-video features.
  - iOS: launcher client and compositor run in simulator; network TCP listener optional.
- EGL buffers:
  - macOS: EGL initializes only if Zink robustness2 nullDescriptor is supported; otherwise compositor falls back gracefully.

## CI Hints
- macOS job:
  - `make clean-all && make macos-compositor`
- iOS job (Simulator):
  - `make clean-all && make ios-compositor`
- Parallel job:
  - `make clean-all && make Wawona`
- Cache `macos-dependencies/` and `ios-dependencies/` between runs to speed up builds.

## Navigation
- Build system changes:
  - `CMakeLists.txt` uses `ios-dependencies` and `macos-dependencies` and applies platform compile options.
  - Makefile target `Wawona` streams parallel logs.
- Key code paths:
  - macOS compositor init: `src/WawonaCompositor.m`
  - iOS launcher client: `src/ios_launcher_client.m`
  - Vulkan bridge hooks: `src/metal_renderer.m`

