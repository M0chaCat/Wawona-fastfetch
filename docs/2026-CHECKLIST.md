# Wawona Rust-First Architecture Migration Checklist

> **Goal**: Migrate from mixed C/Objective-C/Rust codebase to Rust-first architecture where all shared logic lives in `core/` and platform adapters are thin rendering/windowing layers.
> **Current Focus**: Debugging Sway Blackscreen (Regression) & Enforcing Logging Standards.

---

## Active Debugging
- [ ] **Fix Sway Blackscreen** (Regression)
  - [ ] Investigate why screen is black despite successful buffer lookup
  - [ ] Add visual debugging aids (magenta background)
- [ ] **Enforce Logging Format**
  - [ ] Remove all emojis from logs
  - [ ] Standardize timestamp/tag format

---

## Phase 1: FFI Foundation ✅ COMPLETE

Establish the stable FFI boundary between Rust core and all platforms.

- [x] **Design UniFFI API**
  - [x] Create minimal `wawona.udl` (namespace only, types use proc-macros)
  - [x] Expand `ffi/api.rs` with full compositor API
  - [x] Create `ffi/types.rs` with FFI-safe types
  - [x] Create `ffi/errors.rs` with comprehensive error types
  - [x] Create `ffi/callbacks.rs` with platform callback traits

- [x] **FFI Types Implemented**
  - [x] Identifiers: `WindowId`, `SurfaceId`, `BufferId`, `OutputId`, `ClientId`, `TextureHandle`
  - [x] Geometry: `Point`, `Size`, `Rect`, `Mat4`
  - [x] Output: `OutputTransform`, `OutputSubpixel`, `OutputMode`, `OutputInfo`
  - [x] Window: `DecorationMode`, `WindowState`, `ResizeEdge`, `WindowConfig`, `WindowInfo`, `WindowEvent`
  - [x] Surface: `SurfaceRole`, `SurfaceState`
  - [x] Buffer: `BufferFormat`, `BufferData`, `Buffer`
  - [x] Input: `PointerButton`, `ButtonState`, `AxisSource`, `PointerAxis`, `KeyState`, `KeyboardModifiers`, `CursorShape`, `TouchPoint`, `GestureType`, `GestureState`, `GestureEvent`
  - [x] Rendering: `RenderNode`, `RenderScene`
  - [x] Client: `ClientInfo`, `ClientEvent`
  - [x] Debug: `DebugCommand`

- [x] **WawonaCompositor API**
  - [x] Lifecycle: `new()`, `start()`, `stop()`, `is_running()`
  - [x] Event Processing: `process_events()`, `dispatch_events()`, `flush_clients()`
  - [x] Polling API: `poll_window_events()`, `poll_client_events()`, `poll_pending_buffers()`, `poll_redraw_requests()`
  - [x] Input Injection: All pointer, keyboard, touch, gesture events
  - [x] Rendering: `get_render_scene()`, `notify_frame_complete()`
  - [x] Configuration: `set_output_size()`, `set_force_ssd()`, `set_keyboard_repeat()`
  - [x] Window Management: `get_windows()`, `focus_window()`, `request_window_close()`
  - [x] Client Management: `get_client_count()`, `get_clients()`, `disconnect_client()`
  - [x] Debug: `execute_debug_command()`, `get_stats()`

- [x] **Build Verification**
  - [x] UniFFI scaffolding generates successfully
  - [x] `cargo build --lib` compiles without errors

---

## Phase 2: Core Compositor ✅ COMPLETE

Implement the central compositor object and event loop in Rust.

- [x] **Core Compositor Object** (`core/compositor.rs`)
  - [x] Lifecycle management (init, start, stop, shutdown)
  - [x] Client connection handling
  - [x] Global Wayland object management
  - [x] Serial number generation
  - [x] Display integration

- [x] **Runtime/Event Loop** (`core/runtime.rs`)
  - [x] Wayland event source integration
  - [x] Frame timing/scheduling
  - [x] Task queue for deferred operations
  - [x] Platform event loop integration hooks

- [x] **Compositor State** (`core/state.rs`)
  - [x] Surface registry
  - [x] Window registry
  - [x] Client registry
  - [x] Focus state
  - [x] Frame callback management
  - [x] Output configuration

- [x] **Connect FFI to Core**
  - [x] Wire `WawonaCompositor::start()` to actual Wayland display
  - [x] Wire `process_events()` to event loop
  - [x] Wire input injection to state (Wayland dispatch TODO)

**Migrated from:**
- `WawonaCompositor.m` → `core/compositor.rs`
- `WawonaEventLoopManager.m` → `core/runtime.rs`

---

## Phase 3: Wayland Protocol Migration

Migrate Wayland protocol implementations from C to Rust.

> **Protocol Source**: All protocols are re-exported from `wayland-protocols`, `wayland-protocols-wlr`, and `wayland-protocols-misc` crates.
> **Location**: Single unified location at `src/core/wayland/protocol/` with client/server separation.
> No custom generation tool required.

- [x] **Protocol Infrastructure** ✅
  - [x] Removed `wawona-gen-protocols` tool (obsolete)
  - [x] Integrated `wayland-protocols` crate (standard extensions)
  - [x] Integrated `wayland-protocols-wlr` crate (wlroots extensions)
  - [x] Integrated `wayland-protocols-misc` crate (virtual_keyboard)
  - [x] `src/core/wayland/protocol/` uses pure re-exports
  - [x] **Consolidated all protocols into single location** ✅
  - [x] **Removed duplicate directories** (`src/protocols/`, `src/core/protocols/`) ✅
  - [x] **Client/server separation implemented** ✅


- [x] **Priority 1 - Essential Protocols** ✅
  - [x] `wl_compositor` - Complete in `core/wayland/compositor.rs`
  - [x] `wl_shm` - Complete in `core/wayland/compositor.rs`
  - [x] `xdg_shell` - Complete in `core/wayland/xdg_shell.rs` (toplevel, surface, popup)
  - [x] `wl_seat` - Complete in `core/wayland/seat.rs` (pointer, keyboard, touch)
  - [x] `wl_output` - Complete in `core/wayland/output.rs`

- [x] **Priority 2 - Common Protocols** ✅
  - [x] `wl_subcompositor` - Subsurface management ✅
  - [x] `wl_data_device_manager` - Clipboard/drag-and-drop ✅
  - [x] `xdg_decoration` - Window decorations (CSD/SSD) ✅
  - [x] `xdg_output` - Extended output information ✅
  - [x] `xdg_activation` - Focus stealing prevention ✅

- [x] `Priority 3 - Buffer & Synchronization` ✅
  - [x] `linux_dmabuf_v1` - DMA-BUF buffer sharing ✅
  - [x] `linux_explicit_synchronization` - Explicit sync ✅
  - [x] `single_pixel_buffer_v1` - Solid color surfaces ✅
  - [x] `linux_drm_syncobj_v1` - DRM explicit sync ✅
  - [x] `drm_lease_v1` - VR/AR display leasing ✅

- [x] **Phase 3b: macOS DMA-BUF via IOSurface & Metal** ✅
  - [x] Implement `IOSurface` backend for `linux_dmabuf_v1`
  - [x] Replace FD-based transport with Mach ports on macOS (Using IOSurface Global IDs)
  - [x] Implement Metal texture import for `IOSurface` (Direct IOSurface → CALayer path)
  - [x] Direct-to-Metal zero-copy path (bypassing Vulkan/KosmicKrisp)

- [x] **Priority 4 - Input & Interaction** ✅
  - [x] `pointer_constraints` - Pointer locking/confinement ✅
  - [x] `pointer_gestures` - Pinch/swipe gestures ✅
  - [x] `relative_pointer` - Relative pointer motion ✅
  - [x] `tablet_v2` - Graphics tablet support ✅
  - [x] `text_input_v3` - Text input (IME) ✅
  - [x] `keyboard_shortcuts_inhibit` - Shortcut passthrough ✅
  - [x] `cursor_shape` - Predefined cursor shapes ✅
  - [x] `primary_selection` - Middle-click paste ✅
  - [x] `input_method` - Input panel for IME ✅
  - [x] `input_timestamps` - High-resolution input timing ✅
  - [x] `pointer_warp` - Pointer teleportation ✅

- [x] **Priority 5 - Presentation & Timing** ✅
  - [x] `presentation_time` - Frame presentation feedback ✅
  - [x] `fractional_scale` - HiDPI scaling ✅
  - [x] `fifo_v1` - Presentation ordering ✅
  - [x] `tearing_control_v1` - Vsync hints ✅
  - [x] `commit_timing_v1` - Frame timing hints ✅
  - [x] `content_type` - Content type hints ✅
  - [x] `color_management` - HDR and color spaces ✅
  - [x] `color_representation` - Color format hints ✅

- [x] **Priority 6 - Window Extensions** ✅
  - [x] `xdg_foreign` - Cross-client window embedding ✅
  - [x] `xdg_toplevel_drag` - Drag entire windows ✅
  - [x] `xdg_toplevel_icon` - Window icons ✅
  - [x] `xdg_dialog` - Dialog window hints ✅
  - [x] `xdg_toplevel_tag` - Session restore tagging ✅
  - [x] `xdg_system_bell` - Notification sounds ✅

- [x] **Priority 7 - Session & Security** ✅
  - [x] `ext_session_lock` - Screen locking ✅
  - [x] `idle_inhibit` - Idle inhibition ✅
  - [x] `ext_idle_notify` - User idle notifications ✅
  - [x] `security_context` - Sandboxed connections ✅
  - [x] `transient_seat` - Remote desktop seats ✅

- [x] **Priority 8 - Advanced & Desktop Integration** ✅
  - [x] `viewporter` - Viewport cropping/scaling ✅
  - [x] `alpha_modifier` - Alpha blending ✅
  - [x] `fullscreen_shell` - Kiosk mode shell ✅
  - [x] `foreign_toplevel_list` - Task bar support ✅
  - [x] `data_control` - Clipboard managers ✅
  - [x] `workspace` - Virtual desktop management ✅
  - [x] `background_effect` - Blur effects ✅

- [x] **Priority 9 - Screen Capture & XWayland** ✅
  - [x] `image_capture_source` - Capture sources ✅
  - [x] `image_copy_capture` - Screen capture ✅
  - [x] `xwayland_keyboard_grab` - XWayland input ✅
  - [x] `xwayland_shell` - XWayland surface integration ✅

- [x] **Priority 10 - wlroots Protocols (Ecosystem Compatibility)** ✅
  - [x] `zwlr_layer_shell_v1` - Panels, wallpapers, overlays (CRITICAL) ✅
  - [x] `zwlr_output_manager_v1` - Display configuration ✅
  - [x] `zwlr_output_power_manager_v1` - DPMS power management ✅
  - [x] `zwlr_foreign_toplevel_manager_v1` - Task bars, window lists ✅
  - [x] `zwlr_screencopy_manager_v1` - Screen capture ✅
  - [x] `zwlr_gamma_control_manager_v1` - Night light ✅
  - [x] `zwlr_data_control_manager_v1` - Clipboard managers (Functional Stub) ✅
  - [x] `zwlr_export_dmabuf_manager_v1` - GPU buffer export (Skeleton) ✅
  - [x] `zwlr_virtual_pointer_manager_v1` - Virtual pointers (Functional) ✅
  - [x] `zwp_virtual_keyboard_manager_v1` - Virtual keyboards (Functional) ✅

> **Status:** Automated generation infrastructure complete.
> - `wawona-wlr-protocols` crate created and integrated.
> - XMLs fetched via Nix (`nix run .#gen-protocols`).
> - Rust server code generated for all 10 protocols.
>
> **Next Step:** Implement `Dispatch` traits in `src/core/wayland/wlroots/`.

### Protocol Implementation Summary

**✅ Implemented (67 protocols total):**
- **Core (6):** wl_compositor, wl_shm, wl_subcompositor, wl_data_device_manager, wl_output, wl_seat
- **XDG (10):** xdg_wm_base, xdg_decoration, xdg_output, xdg_foreign, xdg_activation, xdg_dialog, xdg_toplevel_drag, xdg_toplevel_icon, xdg_toplevel_tag, xdg_system_bell
- **Buffer (5):** linux_dmabuf_v1, linux_explicit_synchronization, single_pixel_buffer_v1, linux_drm_syncobj, drm_lease
- **Input (11):** relative_pointer, pointer_constraints, pointer_gestures, tablet_v2, text_input_v3, keyboard_shortcuts_inhibit, cursor_shape, primary_selection, input_method, input_timestamps, pointer_warp
- **Timing (9):** presentation_time, viewporter, fractional_scale, fifo_v1, tearing_control_v1, commit_timing_v1, content_type, color_management, color_representation
- **Session (5):** idle_inhibit, ext_session_lock, ext_idle_notify, security_context, transient_seat
- **Desktop (6):** alpha_modifier, fullscreen_shell, foreign_toplevel_list, data_control, workspace, background_effect
- **Capture (4):** image_capture_source, image_copy_capture, xwayland_keyboard_grab, xwayland_shell
- **wlroots (10):** layer_shell, output_manager, output_power, foreign_toplevel, screencopy, gamma_control, data_control, export_dmabuf, virtual_pointer, virtual_keyboard

**Total: 67 protocols implemented or stubbed for full ecosystem compatibility**

---

## Phase 4: Surface & Buffer Management

Implement surface and buffer lifecycle in Rust.

- [ ] **Surface Module** (`core/surface/`)
  - [ ] `surface.rs` - Surface object with pending/committed state
  - [ ] `buffer.rs` - GPU-ready buffer abstraction
  - [ ] `role.rs` - Surface role management (toplevel, popup, subsurface)
  - [ ] `commit.rs` - Double-buffered commit logic
  - [ ] `damage.rs` - Damage region tracking

- [ ] **Buffer Abstraction**
  - [ ] SHM buffer support (pixel data)
  - [ ] DMA-BUF support (file descriptor)
  - [ ] Buffer release/reuse tracking

**Migrate from:**
- `WawonaSurfaceManager.m` (23KB)
- `compositor_implementations/wayland_compositor.c`

---

## Phase 5: Window Management

Implement window management in Rust.

- [ ] **Window Module** (`core/window/`)
  - [ ] `window.rs` - Platform-agnostic window abstraction
  - [ ] `tree.rs` - Window hierarchy (popups, subsurfaces)
  - [ ] `focus.rs` - Focus management
  - [ ] `resize.rs` - Resize constraints and policy
  - [ ] `fullscreen.rs` - Fullscreen/maximize state

- [ ] **Window Lifecycle**
  - [ ] Creation from xdg_toplevel
  - [ ] State changes (maximize, fullscreen, minimize)
  - [x] CSD/SSD mode switching (Implemented Force SSD logic)
  - [ ] Interactive move/resize

**Migrate from:**
- `WawonaWindowManager.m`
- `compositor_implementations/xdg_shell.c`

---

## Phase 6: Input System

Complete input handling in Rust.

- [ ] **Input Module** (`core/input/`)
  - [ ] `seat.rs` - Full wl_seat implementation
  - [ ] `keyboard.rs` - Keyboard state, XKB integration
  - [ ] `pointer.rs` - Pointer state, focus tracking
  - [ ] `touch.rs` - Touch event handling
  - [ ] `gestures.rs` - Gesture recognition

- [ ] **Input Flow**
  - [ ] Platform → Rust input injection
  - [ ] Scene graph hit testing
  - [ ] Rust → Wayland client dispatch

**Migrate from:**
- `src/input/input_handler.m`
- `src/input/wayland_seat.c`

---

## Phase 7: Scene Graph & Rendering

Implement abstract rendering model.

- [ ] **Render Module** (`core/render/`)
  - [ ] `scene.rs` - Scene graph root
  - [ ] `node.rs` - Scene nodes (window, surface, subsurface)
  - [ ] `transform.rs` - Matrix transforms
  - [ ] `damage.rs` - Accumulated damage regions

- [ ] **Rendering Flow**
  - [ ] Build declarative scene from compositor state
  - [ ] Provide `RenderScene` to platform via FFI
  - [ ] Track damage for incremental updates

---

## Phase 8: macOS Platform Adapter (Native Objective-C)

> **Architecture**: Native Objective-C frontend calling Rust via FFI. No Rust GUI code.

- [ ] **Objective-C Frontend** (existing `src/core/*.m` files)
  - [ ] `WawonaCompositor.m` - Main compositor lifecycle, calls FFI
  - [ ] `WawonaCompositorView_macos.m` - NSView with CAMetalLayer
  - [ ] `WawonaWindowManager.m` - NSWindow management
  - [ ] `WawonaRenderManager.m` - Metal rendering using RenderScene from FFI
  - [ ] `WawonaEventLoopManager.m` - CVDisplayLink integration

- [ ] **FFI Integration**
  - [ ] Call `wawona_compositor_start()` / `stop()` for lifecycle
  - [ ] Inject input via `inject_pointer_motion()`, `inject_key()`, etc.
  - [ ] Poll `get_render_scene()` for Metal draw calls
  - [ ] Call `process_events()` in runloop

- [ ] **Metal Rendering**
  - [ ] Consume `RenderScene` from Rust FFI
  - [ ] Draw textured quads for each `RenderNode`
  - [ ] Support damage tracking for efficient updates

---

## Phase 8b: iOS Platform Adapter (Native Objective-C/Swift)

> **Architecture**: Native iOS frontend calling Rust via FFI. No Rust GUI code.

- [ ] **Objective-C/Swift Frontend**
  - [ ] `WawonaCompositorView_ios.m` - UIView with CAMetalLayer
  - [ ] Touch event handling → `inject_touch_*()` FFI calls
  - [ ] CADisplayLink integration for frame pacing

- [ ] **iOS-Specific Concerns**
  - [ ] App lifecycle (foreground/background/suspend)
  - [ ] Safe area insets handling
  - [ ] Keyboard appearance/dismissal
  - [ ] Multi-touch input mapping

- [ ] **App Group / IPC**
  - [ ] XDG_RUNTIME_DIR equivalent for iOS sandbox
  - [ ] Unix socket setup within App Group container
  - [ ] SSH client integration (WawonaSSHRunner)

> **Note**: iOS shares Metal rendering approach with macOS. Focus on UIKit and touch.

---

## Phase 9: Android Platform Adapter (Native Kotlin)

> **Architecture**: Native Kotlin frontend using UniFFI bindings. No Rust GUI code.

- [ ] **Kotlin Frontend** (`src/android/java/`)
  - [ ] Generate UniFFI bindings for Kotlin
  - [ ] `WawonaCompositorView.kt` - Jetpack Compose component
  - [ ] Activity lifecycle → FFI lifecycle calls
  - [ ] Touch events → `inject_*()` FFI calls

- [ ] **GPU Rendering**
  - [ ] Consume `RenderScene` from FFI
  - [ ] Render via Compose Canvas or Vulkan
  - [ ] Support damage tracking for efficient updates

- [ ] **Integration**
  - [ ] Test with Wayland clients on Android
  - [ ] Verify input/output flow through FFI

---

## Phase 10: Frame Timing & IPC

Complete timing and debug systems.

- [ ] **Time Module** (`core/time/`)
  - [ ] `frame_clock.rs` - Frame pacing, vsync orchestration

- [ ] **IPC Module** (`core/ipc/`)
  - [ ] `commands.rs` - Debug/control commands

**Migrate from:**
- `WawonaFrameCallbackManager.m`
- `WawonaDisplayLinkManager.m`

---

## Phase 11: Cleanup & Optimization

Final cleanup and performance work.

- [ ] **Code Removal**
  - [ ] Archive deprecated C/Objective-C code
  - [ ] Remove unused legacy files
  - [ ] Clean up build system

- [ ] **Performance**
  - [ ] Benchmark against legacy implementation
  - [ ] Profile hot paths
  - [ ] Optimize FFI boundary crossings

---

## Phase 12: Testing

Comprehensive testing strategy for all layers.

- [ ] **Core Module Tests** (`src/core/`)
  - [ ] `wayland/` - Protocol state machine tests
  - [ ] `surface/` - Surface lifecycle, commit, damage tests
  - [ ] `window/` - Window tree, focus, state tests
  - [ ] `input/` - Input routing, hit testing tests
  - [ ] `render/` - Scene graph construction tests
  - [ ] `time/` - Frame timing accuracy tests

- [ ] **FFI Correctness** (`src/ffi/`)
  - [ ] All FFI types roundtrip correctly
  - [ ] Error propagation across boundary
  - [ ] Thread safety at FFI boundary
  - [ ] No memory leaks in FFI layer

- [ ] **UniFFI Bindings**
  - [ ] Kotlin bindings generate correctly
  - [ ] Swift bindings generate correctly
  - [ ] Binding API matches Rust API
  - [ ] Callback/polling patterns work

- [ ] **Integration Tests**
  - [ ] Full compositor lifecycle
  - [ ] Client connect → draw → disconnect flow
  - [ ] Multi-client scenarios
  - [ ] Window management (create, resize, close)
  - [ ] Input injection → Wayland event flow

- [ ] **Platform Adapter Tests** (optional/manual)
  - [ ] macOS: Metal rendering output
  - [ ] macOS: Input event translation
  - [ ] iOS: Touch input mapping
  - [ ] Android: Compose view integration

- [ ] **Test Infrastructure**
  - [ ] Mock platform callbacks for headless testing
  - [ ] Test Wayland client helper utilities
  - [ ] CI integration for automated tests

---

## Phase 13: Documentation

Update architecture documentation and diagrams.

- [ ] **Architecture Diagrams** (Mermaid)
  - [ ] Overall system architecture
  - [ ] Event flow diagram (Platform → FFI → Core → Wayland)
  - [ ] Rendering flow diagram (Core → Scene → Platform → GPU)
  - [ ] Module dependency graph
  - [ ] Platform binding diagrams (macOS, iOS, Android)

- [ ] **Per-Phase Diagrams**
  - [ ] Phase 1-2: FFI boundary and core compositor flow
  - [ ] Phase 3-6: Wayland protocol dispatch flow
  - [ ] Phase 7: Scene graph structure
  - [ ] Phase 8-9: Platform adapter architecture

- [ ] **API Documentation**
  - [ ] FFI API reference (types, methods, errors)
  - [ ] Platform integration guide
  - [ ] Core module documentation

- [ ] **Developer Guides**
  - [ ] Contributing guide
  - [ ] Protocol implementation guide
  - [ ] Platform adapter guide

---

## Success Criteria

### Phase 1 ✅
- [x] UniFFI bindings generate successfully
- [x] FFI API documented
- [x] Build passes

### Phase 2 ✅
- [x] Compositor lifecycle works entirely in Rust
- [x] Event loop runs without C dependencies
- [x] State management fully in Rust

### Phase 3 ✅ COMPLETE
- [x] All essential Wayland protocols in Rust ✅
- [x] **57 Wayland protocol globals registered** ✅
- [x] Core, XDG, Buffer, Input, Timing, Session, and Window Extension protocols implemented ✅
- [x] Upgraded to wayland-protocols 0.32.10 with staging/stable protocol access ✅
- [ ] Wayland clients can connect and display content (needs testing)
- [ ] C protocol implementations deprecated (in progress)

### Phase 8 & 8b
- [ ] macOS frontend (Objective-C) calls Rust via FFI
- [ ] iOS frontend (Objective-C/Swift) calls Rust via FFI
- [ ] Metal rendering consumes `RenderScene` from FFI
- [ ] Input injection flows: Native → FFI → Rust → Wayland

### Phase 9
- [ ] Android frontend (Kotlin) uses UniFFI bindings
- [ ] Jetpack Compose view renders `RenderScene`
- [ ] Touch input works on Android

### Phase 12
- [ ] Core module test coverage > 80%
- [ ] FFI roundtrip tests pass
- [ ] Integration tests pass
- [ ] CI runs all tests automatically

### Phase 13
- [ ] Architecture diagrams updated
- [ ] API documentation complete
- [ ] Developer guides available

### Final
- [ ] All compositor logic in Rust (`core/`)
- [ ] Native frontends call Rust via FFI (no Rust GUI code)
- [ ] Stable UniFFI API for all platforms
- [ ] Working on macOS, iOS, Android
- [ ] Native frontends: Objective-C (macOS/iOS), Kotlin (Android)

---

## File Migration Map

| Legacy File | Target | Priority | Status |
|-------------|--------|----------|--------|
| `WawonaCompositor.m` | Keep as native frontend (calls FFI) | P1 | ✅ Architecture |
| `WawonaEventLoopManager.m` | Keep as native frontend | P1 | ✅ Architecture |
| `WawonaFrameCallbackManager.m` | `core/time/frame_clock.rs` (logic only) | P2 | ⬜ |
| `WawonaSurfaceManager.m` | `core/surface/` (logic only) | P2 | ⬜ |
| `WawonaWindowManager.m` | Keep as native frontend (calls FFI) | P2 | ✅ Architecture |
| `input_handler.m` | Keep as native frontend (calls FFI) | P2 | ✅ Architecture |
| `wayland_compositor.c` | `core/wayland/compositor.rs` | P1 | ✅ Complete |
| `xdg_shell.c` | `core/wayland/xdg_shell.rs` | P1 | ✅ Complete |
| `wayland_shm.c` | `core/wayland/compositor.rs` | P1 | ✅ Complete |
| `wayland_output.c` | `core/wayland/output.rs` | P1 | ✅ Complete |
| `wayland_seat.c` | `core/wayland/seat.rs` | P1 | ✅ Complete |
| All `compositor_implementations/*.c` | `core/wayland/` modules | P3 | ✅ Complete |
| `android_jni.c` | Remove (use UniFFI Kotlin bindings) | P2 | ⬜ |

### Architecture Clarification

**Native frontends (Objective-C, Kotlin)** are NOT migrated to Rust. They:
- Remain in native languages for full platform API access
- Call into Rust via FFI for compositor logic
- Handle rendering, input, and lifecycle natively

**Rust backend** handles:
- All Wayland protocol logic (57 globals registered)
- Surface, window, input state management
- Scene graph and damage tracking
- Frame timing coordination

---

## Phase 14: Build System & Nix Infrastructure

> **Goal**: Fully declarative build environment for all platforms using Nix. Use `nix` to define environment variables, dev shells, and build targets.

### Build Reproducibility

Nix requires fully reproducible builds (no network access during build, deterministic outputs).

**Resolved Issues:**
- [x] **Waypipe Cargo.lock**: Pre-generated `Cargo.lock.patched` file committed to repo instead of runtime cargo update (which requires `__noChroot`)
- [x] **Kosmickrisp Mesa pinning**: Use specific commit `rev` instead of `branch = "main"` to ensure reproducible fetches

**Known Limitations (iOS/Xcode):**
- iOS builds require `__noChroot = true` to access Xcode SDK paths (`/Applications/Xcode.app/Contents/Developer/Platforms/iPhoneOS.platform/Developer/SDKs/`)
- This is unavoidable because Apple's Xcode toolchain is not available in nixpkgs
- Affected packages: `waypipe/ios.nix`, `openssh/ios.nix`, `ffmpeg/ios.nix`
- Alternative: Use `apple-sdk` packages from nixpkgs (limited SDK subset)

### Platform Builds

- [ ] **macOS Build**
  - [x] Fix mesa/kosmickrisp hash mismatch
  - [x] Pin kosmickrisp to specific commit for reproducibility
  - [x] Pre-generate waypipe Cargo.lock for reproducibility
  - [ ] Verify `nix build .#wawona-macos` success
  - [ ] Ensure fully declarative environment

- [ ] **iOS Build**
  - [x] Implement `xcodegen` integration via Nix
  - [x] Create `wawona-ios` wrapper script
  - [x] Document Xcode SDK access requirements
  - [ ] Verify `nix run .#wawona-ios` simulator launch

- [ ] **Android Build**
  - [ ] Implement `gradlegen` integration via Nix
  - [ ] Create `wawona-android` wrapper script
  - [ ] Verify `nix run .#wawona-android` emulator launch

- [ ] **Linux Build**
  - [ ] Fullscreen Compositor - use DRM, KMS for GPU access
  - [ ] Verify `nix build .#wawona-linux` success
  - [ ] Verify `nix run .#wawona-linux` success  

Extra:

# Wawona Compositor Todo

- [x] Open Source the project. Hello?
- [ ] Implement additional Wayland protocol extensions
- [ ] Add multi-touch protocol.. 
- [ ] and trackpad input style vs touch option in compositor settings.
- [ ] Create Wawona Compositor's seamless waypipe configuration interface for ios/android

---

*Last updated: 2026-01-26*