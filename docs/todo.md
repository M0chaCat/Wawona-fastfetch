# Wawona Compositor Todo

- [ ] Open Source the project. Hello?
- [ ] Implement additional Wayland protocol extensions
- [ ] Add multi-touch protocol.. 
- [ ] and trackpad input style vs touch option in compositor settings.
- [ ] Create Wawona Compositor's seamless waypipe configuration interface for ios/android

### Compilation Status (Completed)
- [x] **Architecture**: `wawona.nix` acts as the primary driver, calling CMake with Nix-provided environment and dependencies.
- [x] **macOS**: Builds `wawona-macos` using custom Xcode wrapper (SDK 26) and links Nix-built dependencies (libwayland, ffmpeg, etc.).
- [x] **iOS**: Cross-compiles `wawona-ios` using Xcode toolchain and iOS SDK 26, linking ios-compiled dependencies.
- [x] **Android**: Cross-compiles `wawona-android` using NDK r27c, linking android-compiled dependencies.

### Build System & Multiplexing (Completed)
- [x] **Multiplexed Runner**: `nix run` (default app) launches a `tmux` session that builds all 3 platforms in parallel.
- [x] **Per-Platform Builds**: Available via `nix build .#wawona-macos`, `nix build .#wawona-ios`, `nix build .#wawona-android`.
- [x] **Dependency Management**: All dependencies (libwayland, waypipe, etc.) are hermetically built by Nix and exposed to CMake.

### Usage
- Run all builds: `nix run`
- Run specific build: `nix build .#wawona-<platform>`
