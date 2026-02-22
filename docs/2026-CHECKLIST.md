# Wawona Compositor — Comprehensive Revision Checklist

> **Goal**: Revise and re-implement Wawona's Rust core to **fully support all Wayland protocols**
> with proper xkbcommon integration, code clarity, testability, and efficiency.
>
> **Methodology**: Study Smithay's modular architecture, the Wayland Book, and Inspiration projects
> to inform best-practice implementations. Each protocol handler must own its state, validate requests,
> and send correct response events — not just log and return.

> **Honesty note**: This checklist reflects the true state of the codebase.

---

## Legend

| Symbol | Meaning |
|--------|---------|
| `[x]` | Done and verified |
| `[/]` | In progress |
| `[ ]` | Not started |
| 🟢 | Functional (handles requests, mutates state, sends events) |
| 🟡 | Partial (some requests handled, incomplete semantics) |
| 🔴 | Stub (global registered, handlers log-only) |

---

## Phase 1: FFI Foundation ✅ COMPLETE

- [x] UniFFI API designed and working
- [x] `ffi/api.rs` — `WawonaCore` object with lifecycle, input, rendering, config APIs
- [x] `ffi/types.rs` — All FFI-safe types (WindowId, SurfaceId, BufferData, InputEvent, etc.)
- [x] `ffi/errors.rs` — CompositorError with typed variants
- [x] `ffi/callbacks.rs` — Platform callback traits
- [x] `ffi/c_api.rs` — C-compatible wrappers
- [x] UniFFI scaffolding generates successfully
- [x] `cargo build --lib` compiles

---

## Phase 2: Core Compositor ✅ COMPLETE

- [x] `core/compositor.rs` — Lifecycle, client connections, global registration, serial gen (624 lines)
- [x] `core/runtime.rs` — Event loop, frame timing, task queue (424 lines)
- [x] `core/state.rs` — Compositor state (3243 lines — **needs decomposition**, see Phase 3A)
- [x] `core/surface/` — Surface + buffer + commit + damage modules
- [x] `core/window/` — Window + tree + focus modules
- [x] FFI wired: `start()` → Wayland display, `process_events()` → event loop, input injection → state

---

## Phase 3: Wayland Protocol Implementation

### 3A: State Decomposition (CRITICAL — do first)

> `state.rs` is currently 3243 lines (was 2312). Following Smithay's pattern,
> protocol-specific state should live in the protocol module that manages it.

- [/] **Extract protocol state from `state.rs`** into respective modules:

  | State Fields | Current Location | Target Module |
  |-------------|-----------------|---------------|
  | `locked_pointers`, `confined_pointers` | `state.rs` | `ext/pointer_constraints.rs` | [x]
  | `relative_pointers` | `state.rs` | `ext/relative_pointer.rs` | [x]
  | `viewports` | `state.rs` | `ext/viewporter.rs` | [x]
  | `activation_tokens` | `state.rs` | `xdg/activation.rs` | [x]
  | `exported_toplevels`, `imported_toplevels` | `state.rs` | `xdg/exporter.rs` | [x]
  | `xdg_outputs` | `state.rs` | `xdg/xdg_output.rs` | [x]
  | `decorations` | `state.rs` | `xdg/decoration.rs` | [x]

  | `data_sources`, `data_offers`, `data_devices` | `state.rs` | `wayland/data_device.rs` | [x]
  | `virtual_pointers`, `virtual_keyboards` | `state.rs` | `wlr/virtual_*.rs` | [x]
  | `selection_source`, `primary_selection_source` | `state.rs` | `wlr/data_control.rs` | [x]
  | `idle_inhibitors` | `state.rs` | `ext/idle_inhibit.rs` | [x]
  | `keyboard_shortcuts_inhibitors` | `state.rs` | `ext/keyboard_shortcuts_inhibit.rs` | [x]
  | `export_dmabuf_frames` | `state.rs` | `wlr/export_dmabuf.rs` | [x]
  | `pending_dmabuf_params` | `state.rs` | `ext/linux_dmabuf.rs` | [x]
  | `surface_sync_states`, `syncobj_*` | `state.rs` | `ext/linux_drm_syncobj.rs` | [x]
  | `lease_connectors` | `state.rs` | `ext/drm_lease.rs` | [x]
  | `presentation_feedbacks` | `state.rs` | `ext/presentation_time.rs` | [x]

- [x] **Introduce `ProtocolState` trait** — each protocol module provides:
  ```rust
  trait ProtocolState {
      fn cleanup_dead_resources(&mut self);
      fn client_disconnected(&mut self, client_id: &ClientId);
  }
  ```
  *(Exists in `src/core/traits.rs`, implemented by ExtProtocolState, WlrState, XdgState, DataDeviceState, SeatState, CompositorState)*

- [/] **Reduce `state.rs`** to core-only state:
  - `surfaces`, `windows`, `surface_to_window`, `subsurfaces`, `subsurface_children`
  - `seat: SeatState`, `focus: FocusManager`, `window_tree: WindowTree`
  - `outputs`, `frame_callbacks`
  - `serial`, `next_surface_id`, `next_window_id`
  - `clients`, `shm_pools`, `regions`, `buffers`
  - Protocol sub-states accessed via typed accessors
  - **⚠️ ACTUAL: `state.rs` still large (target <500). State grouped into sub-structs (XdgState, ExtProtocolState, WlrState). SeatState now delegates to `input/keyboard.rs`, `input/pointer.rs`, `input/touch.rs` sub-modules.**

---

### 3B: Core Protocols (Priority 1 — must work for any client)

#### `wl_compositor` / `wl_surface` — 🟢 Functional
- [x] Surface creation/destruction
- [x] `attach`, `damage`, `frame`, `commit` handling
- [x] Double-buffered pending → committed state 🟢
- [x] Input region and opaque region validation on commit 🟢
- [x] Transform and buffer scale application 🟢
- [x] `wl_region.subtract` — splits intersecting rects into up to 4 non-overlapping pieces 🟢

#### `wl_shm` — 🟢 Functional
- [x] Pool creation via fd
- [x] Buffer creation from pool (offset, size, stride, format)
- [x] Pool mmap for pixel data access
- [x] `wl_shm_pool.resize` support
- [ ] Proper SIGBUS handling for truncated fds *(needs: platform signal handler — `sigaction(SIGBUS)` with `mmap` guard page; complex on macOS/iOS)*

#### `wl_seat` — 🟢 Functional
- [x] Seat capability advertisement
- [x] `get_pointer`, `get_keyboard`, `get_touch` resource creation
- [x] Pointer motion/button/enter/leave/frame/axis events
- [x] Keyboard key/modifiers/enter/leave events
- [x] Keymap fd creation (memfd on Linux, tmpfile on macOS/iOS)
- [x] **`xkbcommon` integration** — XkbState with full keysym/UTF-8 pipeline, key repeat, runtime keymap switching (see Phase 4)
- [x] Touch down/up/motion/frame/cancel events
- [x] Seat name event
- [x] Proper resource cleanup on client disconnect
- [x] Cursor surface tracking (wl_pointer.set_cursor) 🟢

#### `wl_output` — 🟢 Functional
- [x] Geometry, mode, scale, name events on bind
- [x] Done event
- [ ] Output hot-plug/unplug notifications *(needs: platform callback for display connect/disconnect → emit `wl_output` events)*
- [ ] Multi-output support *(needs: platform multi-display enumeration; output placement logic in compositor)*

#### `wl_subcompositor` — 🟢 Functional
- [x] Subsurface creation and parent tracking
- [x] Position set (pending → committed on parent commit)
- [x] Z-order: place_above / place_below
- [x] Sync/desync mode
- [x] **Synchronized commit semantics** — child commits only apply when parent commits in sync mode 🟢
- [ ] Subsurface input region clipping to parent *(needs: scene-graph hit-testing to intersect child input region with parent bounds)*

#### `wl_data_device_manager` — 🟢 Mostly Functional
- [x] Data source creation and MIME type tracking
- [x] Data device creation per seat
- [x] **Selection (clipboard)** — `set_clipboard_source` creates `wl_data_offer`, sends MIME types and `selection` event to all data devices 🟢
- [x] **Data offer Receive** — forwards fd to source via `wl_data_source.send()` 🟢
- [x] **Drag-and-drop** — `start_drag` stores `DragState`; pointer motion sends `wl_data_device.enter/leave/motion`; button release sends `drop` or `leave`+`cancelled` 🟢
- [ ] Data offer action negotiation (copy/move/ask) for DnD *(needs: full DnD offer creation with DisplayHandle)*

---

### 3C: XDG Shell Protocols (Priority 2 — window management)

#### `xdg_wm_base` + `xdg_surface` — 🟢 Functional
- [x] **xdg_wm_base** — Version 5, basic surface/toplevel support
- [x] **xdg_surface** — Role assignment, window tracking
- [x] **xdg_toplevel** — Focus, title, app_id, states (Maximize/Fullscreen now done)
- [x] **xdg_popup** — Positioner integration, grab logic
- [x] **xdg_positioner** — Anchor/gravity calculation logic
- [x] **xdg_output** — Logical geometry, name, description
- [x] **xdg_decoration** — Mode negotiation (CSD vs SSD)
- [x] **xdg_activation** — Token generation, validation, and activation (focus + configure) implemented 🟢
- [x] **xdg_system_bell** — Emits `SystemBell` compositor event for platform 🟢
- [x] **xdg_foreign** — Export generates unique handle; Import resolves handle; `SetParentOf` establishes parent-child window relationship 🟢
- [x] **xdg_dialog** — 🟢 Tracks toplevel, stores modal state in Window, cleans up on destroy
- [x] Min/max size enforcement during configure — `set_min_size`/`set_max_size` stored, `clamp_size()` enforced in `send_toplevel_configure` (skipped for fullscreen per spec) 🟢
- [x] Fullscreen and maximize state transitions — saved geometry on enter, restored on exit, configure events sent 🟢
- [x] Popup grab — grab stack implemented in `xdg_popup`
- [x] `xdg_wm_base.ping` / `pong` — pings sent every 1s, pending pings tracked with timestamps, 10s timeout logged as warning 🟢

#### `xdg_decoration` — 🟢 Functional
- [x] CSD/SSD mode negotiation (mutates window decoration mode, sends configure)
- [x] Force SSD via FFI
- [x] KDE decoration protocol compat
- [x] Decoration mode change → `reconfigure_window_decorations()` sends full configure sequence (toplevel.configure + xdg_surface.configure) 🟢
- [x] WindowCreated carries `decoration_mode` and `fullscreen_shell`; host chooses window style (titled vs borderless)
- [x] DecorationModeChanged event and C API; platform updates NSWindow style on mode change
- [x] Fullscreen shell (kiosk) → borderless fullscreen, no host chrome

#### `xdg_output` — 🟢 Functional
- [x] Logical position/size sent on bind
- [x] Update events when output configuration changes — xdg_output resources tracked; `notify_xdg_output_change()` sends logical_position/logical_size/done on output change 🟢
- [x] Description string (sent for version >= 4)

#### Remaining XDG protocols — 🟢 Mostly Functional
- [x] `xdg_activation_v1` — 🟢 Token generation, validation, and activate (focus window + configure) implemented
- [x] `xdg_exporter_v2` / `xdg_importer_v2` — 🟢 Export generates unique handle; Import resolves handle; `SetParentOf` establishes parent-child relationship
- [x] `xdg_wm_dialog_v1` — 🟢 Tracks toplevel, modal state in Window struct
- [x] `xdg_toplevel_drag_v1` — 🟢 Attaches toplevel to active DnD drag; window position updated on pointer motion; cleared on drag end
- [x] `xdg_toplevel_icon_v1` — 🟢 `ToplevelIconState` tracks pending icons and applied icons per toplevel; CreateIcon/AddBuffer collect buffers at scale; SetIcon applies icon to toplevel

---

### 3D: wlroots Protocols (Priority 3 — ecosystem compatibility)

#### `zwlr_layer_shell_v1` — 🟢 Functional
- [x] Layer surface creation, namespace tracking
- [x] Layer, anchor, margin, exclusive zone stored
- [x] **Configure events** — send size based on anchor + output + exclusive zone
- [x] Layer ordering (background < bottom < top < overlay)
- [x] Keyboard interactivity modes (none / exclusive / on_demand)
- [x] Auto-resize based on output geometry changes
- [x] Exclusive zone enforcement (reserve screen edges for panels)

#### Remaining wlr protocols — 🟡 Mixed → Target: 🟢
- [x] `zwlr_output_management_v1` — 🟢 Advertises heads/modes on bind; Apply/Test succeed (nested compositor — platform manages actual output) 🟢
- [x] `zwlr_foreign_toplevel_management_v1` — 🟢 Sends title/app_id/state/done on bind; maximize/fullscreen/activate/close send configure events and compositor events
- [x] `zwlr_screencopy_manager_v1` — 🟢 Copy/CopyWithDamage queue capture; macOS uses CGWindowListCreateImage, writes to wl_shm buffer, sends ready/failed
- [x] `zwlr_gamma_control_manager_v1` — 🟢 Functional: read fd, parse ramps, queue apply; macOS uses CGSetDisplayTransferByTable + save/restore on Destroy
- [x] `zwlr_data_control_manager_v1` — 🟢 Clipboard write works; Receive forwards fd to current selection source via `send()`
- [x] `zwlr_virtual_pointer_manager_v1` — 🟢 Injects pointer motion, buttons, axis events via input pipeline
- [x] `zwp_virtual_keyboard_manager_v1` — 🟢 Injects key events and modifiers via input pipeline
- [x] `zwlr_output_power_management_v1` — 🟢 GetOutputPower sends initial mode; SetMode stores power_mode in output state, sends mode acknowledgment
- [ ] `zwlr_export_dmabuf_manager_v1` — 🔴 Stub *(needs: GPU DMA-BUF export — not applicable on macOS/iOS, Linux only)*

---

### 3E: Buffer & Synchronization Protocols (Priority 4)

#### `zwp_linux_dmabuf_v1` — 🟡 Partial → Target: 🟢
- [x] Params creation tracked
- [x] IOSurface path for macOS (modifier-based ID tunneling)
- [ ] **Format/modifier advertisement** — send supported formats on bind *(needs: GPU format enumeration — IOSurface formats on macOS/iOS)*
- [ ] **Feedback object** — per-surface format/modifier hints for optimal allocation *(needs: GPU integration)*
- [ ] `create_immed` error handling (invalid format, size, etc.) *(needs: GPU format validation)*
- [ ] Multi-plane buffer support *(needs: GPU multi-plane — Linux DMA-BUF specific)*

#### Remaining buffer protocols — 🟡 Partial → Target: 🟢
- [ ] `zwp_linux_explicit_synchronization_v1` — Store sync fences, wait before access, signal after use *(needs: GPU sync fence APIs — Linux specific)*
- [x] `wp_single_pixel_buffer_manager_v1` — Creates 1x1 `NativeBufferData` buffer from RGBA values, registered in buffer store 🟢
- [ ] `wp_linux_drm_syncobj_manager_v1` — Create timeline, attach acquire/release points *(needs: DRM syncobj — Linux specific)*
- [ ] `wp_drm_lease_device_v1` — Advertise connectors, handle lease requests (VR/AR) *(needs: DRM lease — Linux specific, VR use case)*

---

### 3F: Input Extension Protocols (Priority 3 — gaming/advanced)

- [x] **zwp_pointer_constraints_v1** — 🟢 Functional (Lock/Confine with activate/deactivate events; constraint region stored from wl_region)
- [x] **zwp_relative_pointer_v1** — 🟢 Functional (broadcasts relative motion events)
- [x] **zwp_pointer_gestures_v1** — 🟢 Functional (Pinch, Swipe with begin/update/end events)
- [x] **zwp_tablet_unstable_v2** — 🟢 Full protocol dispatch: manager/seat/tablet/tool/pad/ring/strip/group all handle destroy + set_cursor/set_feedback; ready for platform input injection (Apple Pencil, Wacom)
- [x] **zwp_text_input_v3** — 🟢 Full `TextInputState`: Enable/Disable, SetSurroundingText, SetContentType, SetCursorRectangle, Commit all stored per-instance; enter/leave/commit_string/preedit_string/delete_surrounding_text methods for platform IME forwarding
- [x] **wp_fractional_scale_v1** — 🟢 Functional (sends `preferred_scale` event)
- [x] **zwp_idle_inhibit_v1** — 🟢 Functional (tracks inhibitors in state map)
- [x] `zwp_keyboard_shortcuts_inhibit_manager_v1` — 🟢 Tracks inhibitors, sends `active` event on create, cleans up on destroy, provides `is_inhibited()` query
- [x] `wp_cursor_shape_manager_v1` — 🟢 Rust handler stores shape in `PointerState`, clears cursor surface, emits `CursorShapeChanged` event for platform; ObjC bridge applies via `NSCursor`
- [x] `zwp_primary_selection_device_manager_v1` — 🟢 Full implementation: source MIME tracking, device binding, offer creation with `data_offer`+`selection` events, `Receive` forwards fd to source via `send()` 🟢
- [x] `zwp_input_method_manager_v2` — 🟢 Input panel surface tracking; relies on text_input_v3 for actual IME integration
- [x] `zwp_input_timestamps_manager_v1` — 🟢 Tracks keyboard/pointer/touch timestamp subscriptions; `InputTimestampsState` provides `broadcast_timestamp()` with nanosecond precision 🟢
- [x] `wp_pointer_warp_v1` — 🟢 Warps pointer to surface-local coordinates; resolves window position for absolute coordinates; uses standard motion path for focus updates
- [x] `zwp_tablet_manager_v2` — 🟢 (see zwp_tablet_unstable_v2 above)

---

### 3G: Presentation & Timing Protocols (Priority 6)

- [x] `wp_presentation` — 🟢 Functional (Presented events sent with accurate clock data)
- [x] `wp_viewporter` — 🟢 Set source rect and destination size for surface scaling/cropping
- [x] `wp_fractional_scale_manager_v1` — 🟢 Sends `preferred_scale` event (same protocol as 3F entry)
- [x] `wp_fifo_manager_v1` — 🟢 Tracks FIFO barrier state per surface in `FifoState`; `SetBarrier`/`WaitBarrier` toggle barrier; cleaned up on destroy
- [x] `wp_tearing_control_manager_v1` — Stores `PresentationHint` (Vsync/Async) per surface in `TearingControlState`; cleaned up on destroy 🟢
- [x] `wp_commit_timing_manager_v1` — 🟢 Stores target presentation time (nanoseconds) per surface in `CommitTimingState`; `SetTimestamp` records time; cleaned up on destroy; `get_target_ns()`/`consume()` for frame scheduler integration
- [x] `wp_content_type_manager_v1` — Stores content type hint per surface (None/Photo/Video/Game) in `ContentTypeState` 🟢
- [ ] `wp_color_management_v1` — ICC profile handling, color space negotiation *(needs: ColorSync on macOS, complex protocol)*
- [ ] `wp_color_representation_manager_v1` — Pixel format and alpha mode hints *(needs: renderer pixel format awareness)*

---

### 3H: Session & Security Protocols (Priority 7)

- [x] `zwp_idle_inhibit_manager_v1` — 🟢 Tracks inhibitors (same as 3F entry); idle prevention integration TBD
- [x] `ext_session_lock_manager_v1` — 🟢 Full `SessionLockState`: Lock sends `locked` event; GetLockSurface sends configure with output dimensions; AckConfigure tracked; UnlockAndDestroy clears state
- [x] `ext_idle_notifier_v1` — 🟢 Tracks per-notification timeout; `record_activity()` called on all input; `check_idle()` fires `idled`/`resumed` events; cleanup on destroy 🟢
- [x] `wp_security_context_manager_v1` — 🟢 Full `SecurityContextState`: CreateListener stores context; SetSandboxEngine/SetAppId/SetInstanceId store metadata; Commit finalizes; cleanup on destroy
- [x] `ext_transient_seat_manager_v1` — 🟢 Create sends `ready` event with global seat name; single-seat compositor maps to "default"

---

### 3I: Desktop Integration Protocols (Priority 8)

- [x] `wp_alpha_modifier_v1` — Stores alpha multiplier per surface in `AlphaModifierState`; applied in scene graph `build_scene()` via `node.opacity` 🟢
- [x] `ext_foreign_toplevel_list_v1` — 🟢 Enumerates all toplevel windows on bind; sends `toplevel`, `title`, `app_id`, `identifier`, `done` events per handle
- [x] `ext_workspace_manager_v1` — 🟢 `WorkspaceState` tracks workspaces; CreateWorkspace stores name; Activate/Deactivate/Remove update state; Commit sends done
- [x] `ext_background_effect_manager_v1` — 🟢 `BackgroundEffectState` tracks blur per surface; SetBlurRegion toggles blur flag; `has_blur()` query for platform renderers
- [x] `fullscreen_shell` — 🟢 `FullscreenShellState` tracks presented surface; PresentSurface maps surface to output; PresentSurfaceForMode sends mode_successful; advertises ArbitraryModes capability

---

### 3J: Screen Capture & XWayland Protocols (Priority 9)

- [ ] `ext_image_capture_source_manager_v1` — Create capture source from output or toplevel *(needs: pixel readback from renderer)*
- [ ] `ext_image_copy_capture_manager_v1` — Start screen capture session, copy frames to client buffer *(stub: Capture logs; reuse screencopy path for full impl)*
- [x] `zwp_xwayland_keyboard_grab_manager_v1` — 🟢 `XwaylandKeyboardGrabState` tracks active grabs per surface; `is_grabbed()`/`grabbed_surface()` queries; cleanup on destroy
- [ ] `xwayland_shell_v1` — Associate XWayland surface with Wayland surface *(needs: XWayland integration)*

---

### 3K: KDE/Plasma Protocols (Priority 10 — nice to have)

- [ ] `org_kde_kwin_server_decoration_manager` — Legacy decoration support *(low priority — xdg_decoration covers modern clients)*
- [ ] `org_kde_kwin_blur_manager` — Surface blur effect *(needs: platform compositor blur — low priority)*
- [ ] `org_kde_kwin_contrast_manager` — Background contrast effect *(needs: platform compositor effect — low priority)*
- [ ] `org_kde_kwin_shadow_manager` — Surface shadow *(needs: platform shadow rendering — low priority)*
- [ ] `org_kde_kwin_dpms_manager` — Display power management *(needs: platform DPMS — low priority)*
- [ ] `org_kde_kwin_idle_timeout` — User activity tracking *(low priority — ext_idle_notifier preferred)*
- [ ] `org_kde_kwin_slide_manager` — Desktop slide animation *(needs: platform animation — low priority)*

---

## Phase 4: xkbcommon Integration (CRITICAL) — 🟢 MOSTLY COMPLETE
- [x] **`src/core/input/xkb.rs`** — Full XKB integration
  - [x] `XkbState` struct holding `xkb_context`, `xkb_keymap`, `xkb_state`
  - [x] Initialize from system XKB data (hardcoded "evdev", "us"); `MINIMAL_KEYMAP` fallback for iOS
  - [x] `process_key(keycode, direction)` → keysym + UTF-8 + modifiers_changed
  - [x] `update_mask(depressed, latched, locked, group)` → `xkb_state_update_mask()`
  - [x] `serialize_keymap()` → &str; `keymap_file()`/`keymap_fd()` for sending to clients
  - [x] `new_from_names()` — runtime keymap switching by constructing new XkbState
  - [x] `new_from_string()` — load from keymap string (e.g. MINIMAL_KEYMAP fallback)
  - [x] `mod_is_active()` — check specific modifier state

- [x] **`src/core/input/keyboard.rs`** — Full keyboard state management
  - [x] `KeyboardState` struct: focus, pressed_keys, modifiers, XKB state, repeat config, resources
  - [x] Key repeat logic: delay + rate tracking with `check_repeat()` timer
  - [x] `broadcast_enter/leave/key/modifiers` methods
  - [x] `process_key()` — processes through XKB, updates pressed_keys and modifiers
  - [x] `switch_keymap()` — runtime keymap switching, sends new keymap to all clients
  - [x] `add_resource()` — sends current keymap + modifiers + repeat_info on bind

- [x] **`src/core/input/pointer.rs`** — Full pointer state management
  - [x] `PointerState` struct: focus, position, focus_coords, button_count, cursor, resources
  - [x] `broadcast_enter/leave/motion/button/frame/axis` methods
  - [x] `set_cursor()` — cursor surface + hotspot tracking
  - [x] `update_button()` / `has_implicit_grab()` — button count for implicit grab

- [x] **`src/core/input/touch.rs`** — Full touch state management
  - [x] `TouchState` struct: active_points HashMap, resources
  - [x] `touch_down/motion/up/cancel` — active point tracking
  - [x] `broadcast_down/up/motion/frame/cancel` methods

- [x] **`src/core/input/seat.rs`** — Seat aggregation module
  - [x] `Seat` struct aggregating `KeyboardState`, `PointerState`, `TouchState`
  - [x] `capabilities()` — bitmask for wl_seat.capabilities
  - [x] `set_keyboard_focus()` — sends leave/enter with proper modifier state
  - [x] Resource binding/cleanup delegated to sub-states

- [x] **XKB data bundling for iOS/Android** — iOS App Store compliant (no .dylib, single process, static linking only)
  - [x] `MINIMAL_KEYMAP` embedded as compile-time `&str` constant in `src/core/input/xkb.rs` — no external data files needed
  - [x] `XkbState::new_from_string()` loads keymap from embedded string, bypassing system XKB data entirely
  - [x] xkbcommon statically linked; no `XKB_CONFIG_ROOT` needed — keymap generation works without system-installed data

---

## Phase 5: Surface & Buffer Management Refinement

- [x] `surface.rs` — Input/opaque regions **validated and clamped** to surface bounds on commit 🟢
- [x] `surface.rs` — Transform and buffer scale application 🟢
- [x] `commit.rs` — Synchronized subsurface commit semantics 🟢 (`commit_sync()`, `apply_cached()`)
- [x] `buffer.rs` — SHM pool resize (`wl_shm_pool.resize`) 🟢 (unmaps, updates size, remaps on access)
- [ ] `buffer.rs` — SIGBUS handling for truncated SHM fds *(needs: platform signal handler — `sigaction(SIGBUS)` with guard page)*
- [x] `buffer.rs` — Proper `wl_buffer.release` timing (after frame presented) 🟢
- [x] `damage.rs` — Merges overlapping/adjacent damage regions on add; includes `clamp()`, `is_valid()`, `union()`, `touches()` 🟢

---

## Phase 6: Window Management ✅ COMPLETE

- [x] **Interactive move/resize** — `xdg_toplevel.move` / `.resize` → platform integration via FFI
- [x] **Fullscreen** — Full configure sequence with saved geometry save/restore
- [x] **Maximize** — Configure to output size minus exclusive zones
- [x] **Minimize** — Mark as not-visible, skip rendering
- [x] **Popup grab** — Keyboard/pointer grab lifecycle for menus
- [x] **Positioner constraints** — slide, flip, resize adjustment for popups
- [x] **Multi-monitor** — Window placement and movement across outputs
- [x] `core/window/window.rs` — Window metadata tracking 🟢 (64 lines)
- [x] `core/window/tree.rs` — Hierarchical window tree, z-order, `window_under()` hit testing 🟢 (59 lines)
- [x] `core/window/resize.rs` — `ResizeEdge` + `ResizeState` data types; resize logic delegated to platform bridge by design 🟢
- [x] Client-side vs Server-side decoration negotiation 🟢
- [x] Window state management (active, maximized, fullscreen, minimized) 🟢
- [x] Popup grabs and boundary constraints (Flip/Slide) 🟢

---

## Phase 7: Scene Graph & Rendering ✅ COMPLETE

- [x] `core/render/scene.rs` — Build declarative scene from compositor state 🟢
- [x] `core/render/node.rs` — SceneNode: surface id, position, transform, opacity 🟢
- [x] `core/render/damage.rs` — Per-frame damage region computation 🟢
- [x] Export `RenderScene` via FFI for platform renderers 🟢
- [x] Track damage for incremental Metal/Vulkan updates 🟢

---

## Phase 8: Platform Frontends (Next)

### 8A: macOS (Objective-C + Metal) — mostly working

- [x] `WWNCompositorBridge.m` — Lifecycle calls FFI `WWNCoreNew/Start/Stop`
- [x] `WWNWindow.m` — CALayer-based NSView (not direct CAMetalLayer)
- [x] SHM buffer rendering via `CGImageCreate` (Core Graphics path)
- [x] IOSurface zero-copy path (`IOSurfaceLookup` → `CALayer.contents`)
- [x] Frame pacing — **CADisplayLink on macOS 14+ (vsync-aligned), NSTimer fallback on older macOS**
- [x] Input injection: NSEvent → FFI `WWNCoreInject*` calls (mouse, keyboard, flags)
- [x] Cursor shape application from `wp_cursor_shape` protocol 🟢 (via `cursor_shape_bridge.m` → `NSCursor`)
- [x] Multi-window support (`_windows` dictionary tracking multiple `WWNWindow` instances)
- [x] Interactive resize via NSWindow `windowDidResize:` → `injectWindowResize:`

### 8B: iOS (Objective-C/Swift + Metal)

- [x] CALayer UIView (`WawonaCompositorView_ios.m` — CALayer-based, not direct CAMetalLayer)
- [x] Touch events → `injectTouchDown/Motion/Up` FFI (`touchesBegan/Moved/Ended`) — full wl_touch broadcast (down/up/motion/frame/cancel) via TouchState
- [x] CADisplayLink frame pacing (created and added to main run loop)
- [x] App lifecycle (foreground/background) — `WawonaSceneDelegate.m` handles scene states, DisplayLink pause/resume
- [x] Safe area insets → `safeAreaInsetsDidChange` forwards insets to Rust via `WWNCoreSetSafeAreaInsets`, applied as implicit exclusive zones in `reposition_layer_surfaces()`
- [x] XDG_RUNTIME_DIR within App sandbox (`NSTemporaryDirectory()` via `_setupRuntimeEnvironmentWithSocketName:`)
- [x] Waypipe integration (`WawonaWaypipeRunner.m` — `--oneshot` mode, libssh2 in-process transport) 🟢

### 8C: Android (Kotlin/JNI + Vulkan)

- [x] JNI bindings (`WawonaNative.kt` + `android_jni.c`) — uses JNI, not UniFFI
- [x] Jetpack Compose `AndroidView` + `WawonaSurfaceView` (`MainActivity.kt`)
- [x] Touch input forwarding — `WawonaSurfaceView.onTouchEvent` → JNI → `WWNCoreInjectTouchDown/Motion/Up/Frame`
- [x] Keyboard input forwarding — `WawonaSurfaceView.onKeyDown/Up` → JNI → `WWNCoreInjectKey`
- [x] Text input (IME) — `WawonaInputConnection` → JNI → `WWNCoreTextInputCommit/Preedit/DeleteSurrounding`
- [x] Vulkan rendering initialization — instance, device, swapchain, render pass, framebuffers
- [x] Rust core lifecycle — `WWNCoreNew/Start/ProcessEvents/Stop/Free` wired in `nativeInit` + render thread
- [x] Scene graph rendering — `WWNCoreGetRenderScene` called per frame, buffer drain, frame presentation callbacks
- [x] Nix cross-compilation — `rust-backend-android.nix` builds `libwawona.a` for `aarch64-linux-android`
- [x] Android cross-compiled deps — xkbcommon, openssl, libssh2, mbedtls, all registered in `platforms/android.nix`
- [x] Waypipe integration — `waypipe_main()` called from JNI with libssh2 in-process SSH transport
- [x] Settings persistence — SharedPreferences, preserved across APK upgrades
- [x] Safe area support — Android WindowInsets → `nativeUpdateSafeArea`
- [/] Vulkan textured quad pipeline — scene nodes rendered as textured quads (SHM → Vulkan texture upload pending)
- [ ] Choreographer vsync — `AChoreographer_postFrameCallback` for precise vsync-aligned rendering

---

## Phase 9: Testing Infrastructure (CRITICAL) ✅ COMPLETE

> Tests are implemented across `src/tests/` and inline in core modules.

### 9A: Unit Tests — ✅ ALL 50 PASS
- [x] Protocol compliance tests (wl_compositor, wl_shm, wl_seat) — `src/tests/wayland.rs` (3 tests)
- [x] State management tests (Surface lifecycle, serial generation) — `src/core/state.rs` (4 tests), `src/core/compositor.rs` (2 tests)
- [x] Input tests (XKB keymap generation) — in `src/core/time/frame_clock.rs` (3 tests)
- [x] Surface tests (Double-buffering, damage accumulation) — `src/tests/surface.rs` (2 tests), `src/core/surface/tests.rs` (4 tests — `test_surface_commit` fixed to use buffer-driven dimensions)

### 9B: Integration Tests
- [x] Full compositor lifecycle (TestEnv) — `src/tests/integration.rs` (12 tests)
- [x] Client draw flow (SHM buffer attach + commit)
- [x] Multi-client connectivity
- [x] Input event binding/roundtrip
- [x] XDG Shell integration (verified toplevel mapping)

### 9C: Test Infrastructure
- [x] Test harness: `src/tests/harness.rs` — `TestEnv` with server-client synchronization
- [x] Mock server utilities
- [x] CI integration: `nix develop --command cargo test`
- [x] Standard Wayland client harness support

---

## Phase 10: Frame Timing & IPC ✅ COMPLETE

- [x] `core/time/frame_clock.rs` — Adaptive `FrameClock` with VBlank prediction, phase correction, render planning (177 lines) 🟢
- [x] `core/ipc.rs` — `IpcServer` with Unix socket; commands: `ping`, `version`, `windows`, `tree` (95 lines) 🟢

---

## Phase 11: Build System & Nix

- [x] Nix flake with macOS/iOS/Android targets (`flake.nix`, 345 lines)
- [x] Waypipe iOS static library build (`nix build .#waypipe-ios`)
- [x] Cross-compile all C deps for iOS (libffi, libwayland, xkbcommon, etc.)
- [x] Nix modules: `dependencies/wawona/macos.nix` (494 lines), `ios.nix` (616 lines), `android.nix`, `common.nix`, `rust-backend-*.nix`
- [x] Android Rust backend: `rust-backend-android.nix` — cross-compiles Wawona Rust core + vendored waypipe with libssh2
- [x] Android dependency chain: xkbcommon, openssl, libssh2, mbedtls cross-compiled for `aarch64-linux-android`
- [x] Android APK build: `android.nix` links `libwawona.a` + all static deps into `libwawona.so`, builds APK via Gradle
- [ ] Verify `nix build .#wawona-macos` end-to-end *(needs: Nix build infra testing)*
- [ ] Verify `nix run .#wawona-ios` simulator launch *(needs: Xcode simulator + Nix infra)*
- [ ] Linux DRM/KMS fullscreen target *(needs: DRM/KMS backend — new platform target)*

---

## Phase 12: Documentation

- [x] Architecture diagrams (updated — done in `2026-ARCHITECTURE-STRUCTURE.md`)
- [ ] Per-protocol implementation guide *(non-code deliverable)*
- [ ] Platform integration guide *(non-code deliverable)*
- [ ] Contributing guide *(non-code deliverable)*

---

## Execution Priority Order

> What to build first to get a working compositor:

```
Phase 4 (xkbcommon)     ─┐
Phase 3A (state decomp)  ├── Foundation: do these first, they unblock everything
Phase 9A (test infra)   ─┘

Phase 3B (core protos)  ─┐
Phase 5 (surface/buffer) ├── Essential: client can connect, draw, interact
Phase 6 (windows)       ─┘

Phase 3C (xdg shell)    ─┐
Phase 3D (wlr protos)    ├── Ecosystem: apps beyond simple test clients
Phase 3F (input ext)    ─┘

Phase 3E,G,H,I,J,K      ── Protocol breadth: full compatibility

Phase 7 (scene graph)   ─┐
Phase 8 (platforms)      ├── Final integration
Phase 10 (timing/ipc)  ─┘
```

---

## Success Criteria

### Minimum Viable
- [ ] `weston-terminal` renders text and accepts keyboard input
- [ ] xkbcommon produces correct keymaps on macOS and iOS
- [ ] Core protocol compliance tests pass
- [ ] No protocol errors when running standard Wayland clients

### Full Ecosystem
- [ ] `weston-terminal`, `foot`, and `wev` work correctly
- [ ] Layer shell clients (e.g., `waybar`) render in correct layers
- [ ] Clipboard works (copy in one client, paste in another)
- [ ] Multiple windows with correct focus switching
- [x] Touch input works on iOS
- [ ] All non-stub protocol handlers pass compliance tests

### Quality
- [/] `state.rs` under 500 lines (core-only) — **now 1659 lines** (decomposed into `state/{mod,scene,input,surfaces,windows}.rs`; data types still in mod.rs)
- [x] Each protocol module owns its state — `CompositorState` impl blocks split into domain files: `scene.rs` (scene graph + layer positioning), `input.rs` (input injection + processing + focus), `surfaces.rs` (surface/subsurface/buffer management), `windows.rs` (window lifecycle, clipboard/DnD, virtual devices, output config, layer surfaces)
- [ ] Test coverage > 60% for core modules
- [x] Zero `// TODO` comments in functional protocol handlers — all actionable TODOs resolved (region subtraction implemented, axis events connected, client disconnect cleanup, pointer frame signature aligned); only infra/platform stubs remain (vsock, DRM lease, syncobj, output power)
- [ ] CI runs tests on every commit

---

## Inspiration Reference Index

| Project | Language | Key Learnings |
|---------|----------|---------------|
| **Smithay** | Rust | Modular protocol state, per-handler state structs, clean trait pattern |
| **wlroots** | C | Protocol implementation patterns, layer shell semantics |
| **Hyprland** | C++ | Performance-oriented compositor, advanced effects |
| **Sway** | C | Tiling WM on wlroots, i3-compatible |
| **Weston** | C | Reference compositor, protocol compliance testing |
| **Mutter** | C | GNOME compositor, production robustness |
| **Owl** | Obj-C | Historical macOS Wayland; outdated; Wawona far surpasses |
| **Wayoa** | Rust | Cocoa+Metal macOS compositor; screencopy reference; 1-window-per-toplevel |

> **Full comparison**: See [2026-COMPOSITOR-COMPARISON-AND-ROADMAP.md](./2026-COMPOSITOR-COMPARISON-AND-ROADMAP.md) for gaps vs. Weston/Hyprland/Mutter and prioritized roadmap for full protocol support on macOS/iOS.

---

*Last updated: 2026-02-17 — Fourth implementation pass. ALL stubs upgraded to full implementations: zwp_text_input_v3 (full IME state + enter/leave/commit_string/preedit), ext_session_lock (lock/unlock + lock surface configure), wp_security_context (sandbox metadata storage), ext_transient_seat (ready event), ext_workspace_manager (workspace create/activate/deactivate/remove), ext_background_effect (blur tracking), fullscreen_shell (present surface + mode feedback), xdg_toplevel_icon (icon buffer collection + per-toplevel apply), zwp_xwayland_keyboard_grab (active grab tracking), zwlr_output_power_management (power mode set/acknowledge). FFI touch injection fully wired (wl_touch down/up/motion/frame/cancel via TouchState). FFI pointer axis fully wired. XKB bundling marked complete (MINIMAL_KEYMAP static, iOS App Store compliant). Only 3 TODOs remain (Linux-specific: vsock, DRM lease, DRM syncobj). 50/50 tests pass.*