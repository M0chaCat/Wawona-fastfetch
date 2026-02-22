# Wawona: Decoration Protocols, Force SSD, and Fullscreen Shell — Implementation Plan

**Goal**: Wawona must fully utilize the host compositor’s userchrome (macOS/iOS/Android) and ensure Wayland clients do **not** render client-side decoration (CSD)—including shadow layers and window frame—when **Force SSD** is enabled. This document is the in-depth plan for correct xdg-decoration behavior, fullscreen shell (kiosk), and the split between automatic client decoration vs Force SSD from **Settings > Display > Force SSD**.

---

## 1. References

### 1.1 Wayland Book — xdg-decoration

From **docs/wayland-book/xdg-shell-in-depth/interactive.md**:

- **Purpose**: Different clients and servers have different preferences for server-side vs client-side window decorations. The **xdg-decoration** protocol (in wayland-protocols) expresses these intentions.
- **Global**: `zxdg_decoration_manager_v1` — request `get_toplevel_decoration(id, toplevel)` to obtain a decoration object for an `xdg_toplevel`.
- **Decoration object** `zxdg_toplevel_decoration_v1`:
  - **Modes**: `client_side` (1), `server_side` (2).
  - **Client**: `set_mode(mode)` expresses preference; `unset_mode()` expresses no preference.
  - **Compositor**: Sends `configure(mode)` to tell the client which mode to use. The client must draw without decorations when the configured mode is `server_side`.
- **Semantics**: The compositor decides the effective mode; the client obeys the `configure` event and updates content (no decorations when server_side). Compliant clients must ack the configure and commit content accordingly.

So: **Wawona’s job** is to send `configure(server_side)` when Force SSD is on and to ensure the **host** draws the only frame (userchrome); the **client** is then obligated not to draw CSD (shadows, titlebar, etc.).

### 1.2 Official xdg-decoration (wayland.app / wayland-protocols)

- If compositor and client do **not** negotiate server-side decoration via this protocol, clients continue to self-decorate.
- **Version 2** allows creating the decoration object after the toplevel already has a buffer; initial mode is client_side if no decoration was previously associated or after a commit following decoration destroy.
- **configure** may be sent at any time; the specified mode must be obeyed by the client.
- Compositors that support it: Weston, Sway, Hyprland, KWin, Mutter, COSMIC, etc.

### 1.3 set_window_geometry (XDG surface)

From the Wayland Book and protocol:

- **Role**: Used mainly for **client-side decorations** to define which part of the surface is “window” (e.g. excluding drop shadows). The compositor may use it for positioning, hit-testing, and window management.
- **When using SSD**: The client typically does not need to set a different geometry (often `(0,0,width,height)` or leaves it unset). The full surface is content.
- **Implication for Wawona**: Store geometry as the **content/frame rect** for hit-testing and input; do not use it to replace the logical window size in all cases (see Section 4).

### 1.4 Fullscreen shell (kiosk)

- **Protocol**: `zwp_fullscreen_shell_v1` — `PresentSurface` / `PresentSurfaceForMode` present a single surface fullscreen on an output (kiosk-style).
- **Wayland Book** (configuration): `xdg_toplevel` has states such as `fullscreen`; fullscreen shell is a separate, simpler path: one surface, full coverage, no window chrome.
- **Wawona today**: `fullscreen_shell.rs` creates a synthetic `Window` and pushes `WindowCreated`; the window is fullscreen. It does **not** set a decoration mode that means “no host chrome.”
- **Requirement**: For fullscreen shell, the host must **not** render window decoration (no macOS titlebar, no Android system decor). So fullscreen shell should be treated as “SSD with no decorations” or a dedicated “kiosk” path so the host uses a borderless/fullscreen window.

### 1.5 Inspiration compositors (from docs/2026-CHECKLIST.md and 2026-COMPOSITOR-COMPARISON-AND-ROADMAP.md)

| Compositor | Decoration / SSD notes |
|------------|------------------------|
| **wlroots** | xdg-decoration + org_kde_kwin_server_decoration; server embeds surface in a frame for SSD. |
| **Weston** | Reference; full protocol set; clear request/event handling. |
| **Sway / Hyprland** | Use wlroots; XDG + decoration protocols. |
| **Wayoa** | One NSWindow per toplevel; useful reference for macOS. |
| **KWin** | org_kde_kwin_server_decoration (legacy); xdg-decoration for modern clients. |

Takeaway: Enforcing SSD is done by (1) advertising and implementing xdg-decoration, (2) sending `configure(server_side)` when the compositor policy is “force server,” and (3) having the **host** draw the only frame (e.g. NSWindow with titled style on macOS). Clients that support xdg-decoration then do not draw CSD.

---

## 2. Current Wawona Behavior (Gaps)

### 2.1 Protocol layer (Rust core)

- **xdg-decoration**: Implemented in `src/core/wayland/xdg/decoration.rs`. Policy `ForceServer` → always send `configure(ServerSide)`; `SetMode` / `UnsetMode` are handled; `reconfigure_window_decorations()` sends full configure sequence. ✅
- **KDE server decoration**: Implemented in `src/core/wayland/plasma/kde_decoration.rs`; policy respected. ✅
- **Decoration policy**: `DecorationPolicy::PreferClient | PreferServer | ForceServer` in `state/mod.rs`; `decoration_mode_for_new_window()` returns the right mode. ✅
- **Force SSD (FFI)**: `set_force_ssd()` updates `decoration_policy`, reconfigures all existing decorations, updates window `decoration_mode`. ✅

### 2.2 Gaps

1. **WindowCreated does not carry decoration_mode**  
   - `CompositorEvent::WindowCreated` in `core/compositor.rs` has `window_id, surface_id, title, width, height` — no `decoration_mode`.  
   - Toplevels are created in `xdg_surface.rs` (GetToplevel); at that moment we can use `state.decoration_mode_for_new_window()` (respects Force SSD) as the **initial** mode, because the client has not yet bound xdg_decoration. So the “default” for the platform is already known.

2. **FFI hardcodes ClientSide for new windows**  
   - In `ffi/api.rs`, when handling `CompositorEvent::WindowCreated`, `WindowInfo` and `WindowConfig` use `decoration_mode: DecorationMode::ClientSide`. So the platform always thinks “client-side” at creation.

3. **macOS window creation ignores decoration mode**  
   - `WWNCompositorBridge.m` `handleWindowCreated` always uses `NSWindowStyleMaskTitled | Closable | Miniaturizable | Resizable` (titled window). It does **not** read any decoration mode.  
   - `WWNPlatformCallbacks.m` has `createNativeWindowWithId:... useSSD:(BOOL)useSSD` and chooses style from `useSSD` (titled vs borderless). That path is the right idea but must be wired to the event that actually creates windows (e.g. WindowCreated with decoration_mode).

4. **set_decoration_mode callback is never used**  
   - When decoration is negotiated (or Force SSD toggled), we update `window.decoration_mode` and call `reconfigure_window_decorations()`. We do **not** invoke the platform callback `set_decoration_mode(window_id, mode)`. So the host never gets a chance to switch window style (e.g. borderless ↔ titled) after creation.

5. **No DecorationModeChanged event to platform**  
   - `DecorationModeChanged` exists in `ffi/types.rs` but is never pushed when decoration mode changes (in decoration.rs or in set_force_ssd). So the UI/platform cannot react to mode changes.

6. **set_window_geometry overwrites window size**  
   - In `xdg_surface.rs`, `SetWindowGeometry { x, y, width, height }` currently sets `window.width` and `window.height`. Per protocol, geometry is the “window” rect (often content or frame); it should be stored separately (e.g. content rect) and used for hit-testing/positioning. Overwriting global window size can break sizing when the client sends a content rect smaller than the surface (e.g. CSD with shadow).

7. **Fullscreen shell and decoration**  
   - Fullscreen shell creates `Window::new()` which defaults `decoration_mode: ClientSide`. For kiosk we want **no** host chrome; the host should create a borderless/fullscreen window. So fullscreen-shell windows need a dedicated signal (e.g. “no decorations” or `decoration_mode` that implies “host draws nothing”).

8. **Android / iOS**  
   - Same idea: when Force SSD is on, use system chrome only; when fullscreen shell, use no chrome. Currently no explicit handling of decoration_mode for window style on these platforms.

---

## 3. Desired Behavior Summary

| Scenario | Compositor behavior | Host behavior | Client obligation |
|----------|---------------------|---------------|--------------------|
| **Force SSD off** | Prefer client or prefer server; negotiate via xdg-decoration. | If SSD chosen: show host chrome (macOS titlebar, etc.). If CSD: borderless so client can draw its own. | If configure(server_side): do not draw decorations. If configure(client_side): may draw CSD. |
| **Force SSD on** | Always send `configure(server_side)`; ignore client preference. | Always show host chrome only; map surface into **content area** only (below titlebar). Do not show any client-drawn frame/shadow. | Must not draw decorations (obey configure). |
| **Fullscreen shell (kiosk)** | One fullscreen surface; no window chrome. | Create borderless/fullscreen window; no titlebar, no system decorations. | N/A (single fullscreen surface). |
| **Toplevel without xdg-decoration** | When Force SSD is on, treat as SSD (`decoration_mode_for_new_window()` = ServerSide). | Same as “Force SSD on” above. | N/A (legacy client; may still draw CSD; best effort). |

So:

- **Automatic**: Normal xdg-decoration negotiation; host uses decoration_mode to choose window style (titled vs borderless on macOS).
- **Force SSD**: Override negotiation to server_side; host always uses its chrome; we must not render or encourage client-drawn decorations (protocol + host behavior).

---

## 4. Implementation Plan

### Phase 1 — Wire decoration mode to window creation and host

1. **Add `decoration_mode` to `CompositorEvent::WindowCreated`**
   - In `src/core/compositor.rs`: extend `WindowCreated` with `decoration_mode: DecorationMode` (use the core type; FFI can map).
   - In `src/core/wayland/xdg/xdg_surface.rs`: when pushing `WindowCreated` for a new toplevel, set `decoration_mode: state.decoration_mode_for_new_window()`. That respects Force SSD and PreferClient/PreferServer for the initial mode before the client binds xdg_decoration.

2. **Fullscreen shell: pass “no decorations” for host**
   - In `src/core/wayland/ext/fullscreen_shell.rs`: when creating the synthetic window, set `decoration_mode: DecorationMode::ServerSide` and ensure the event carries a flag or semantics that mean “kiosk / no host chrome” (e.g. a separate `is_fullscreen_shell: true` or rely on `fullscreen == true` + source = fullscreen_shell). Recommendation: add an optional `no_host_decoration: bool` or use a dedicated event variant `FullscreenShellSurfacePresented { window_id, surface_id, ... }` so the host never draws chrome for that window. Simpler: use `WindowCreated` with `decoration_mode: ServerSide` and a new field `fullscreen_shell: true` so the host can create a borderless fullscreen window.

3. **FFI: use decoration_mode from WindowCreated**
   - In `src/ffi/api.rs`: when handling `WindowCreated`, read `decoration_mode` from the event (add to event struct) and put it in `WindowInfo` and `WindowConfig`. Remove hardcoded `ClientSide`.

4. **macOS: choose window style from decoration_mode**
   - In `WWNCompositorBridge.m` `handleWindowCreated`: receive decoration_mode (and optional fullscreen_shell flag). If `fullscreen_shell` or “no host decoration” → create borderless/fullscreen window. Else if `decoration_mode == ServerSide` → use titled style (current behavior); else → use borderless + resizable so client can draw CSD.
   - Ensure the window that is actually created (whether from bridge or platform callbacks) uses this logic. Unify on one path (e.g. bridge creates window with style from decoration_mode).

5. **Emit DecorationModeChanged and call set_decoration_mode**
   - Whenever `window.decoration_mode` is changed (in `decoration.rs` on configure, in `kde_decoration.rs`, and in `set_force_ssd` in api.rs), push `WindowEvent::DecorationModeChanged { window_id, mode }` so the platform can update UI state.
   - Where the compositor processes events and invokes platform callbacks, invoke `set_decoration_mode(window_id, mode)` when decoration mode changes. Implement `set_decoration_mode` on macOS to update the NSWindow style (e.g. toggle titled vs borderless) if feasible, or document that the initial mode from WindowCreated is authoritative and later changes are for future use (e.g. dynamic toggle of Force SSD with live window update).

### Phase 2 — Geometry and content rect

6. **Store set_window_geometry separately**
   - In `xdg_surface` or window/toplevel state, store `geometry: Option<(i32, i32, i32, i32)>` (x, y, width, height) instead of overwriting `window.width`/`window.height`. Use geometry for:
     - Hit-testing and input (already used in `input_handler.m` via `has_geometry`, `geometry_x/y/width/height` — ensure this comes from the new stored geometry).
     - Optional: content rect for SSD (if we ever want to clip the client surface to “content only” when the client sends a smaller geometry; lower priority).
   - Keep window size from configure (xdg_toplevel configure width/height) as the authoritative logical size; only use geometry for input and frame bounds when in CSD.

7. **Expose geometry to platform if needed**
   - If the host needs the content rect (e.g. to position the surface view below the titlebar), add it to window config or a separate event. For macOS with SSD, the content view is already “below” the titlebar; the surface can be drawn in the content view. Optionally pass titlebar height or content insets so the client buffer is scaled/positioned correctly.

### Phase 3 — Fullscreen shell and kiosk

8. **Fullscreen shell: no host chrome**
   - Ensure fullscreen shell windows are created with a flag or decoration_mode that results in borderless fullscreen on macOS, and equivalent on iOS/Android (no system UI overlay for the Wayland fullscreen surface).
   - In `fullscreen_shell.rs`, when pushing the window creation event, include a clear “fullscreen shell” or “no_host_decoration” so the bridge creates the right window type.

9. **Document fullscreen shell vs xdg fullscreen**
   - xdg_toplevel can set fullscreen state; that is a toplevel in “fullscreen” state (one window fullscreen). Fullscreen shell is a separate protocol (one surface per output, no toplevel). Both should result in “no decorations” from the host when in fullscreen.

### Phase 4 — Android and iOS

10. **Android**
    - When creating the window/activity or view for a Wawona window, use decoration_mode: if Force SSD (or mode ServerSide), use system decor (e.g. action bar / title); if CSD or fullscreen shell, use borderless or fullscreen as appropriate. Mirror the same logic as macOS where applicable.

11. **iOS**
    - Same: use decoration_mode and fullscreen_shell to decide whether to show system chrome (e.g. safe area, status bar) or true fullscreen for the Wayland surface. Docs note that on iOS the compositor view is often a single fullscreen surface; fullscreen shell and “no decorations” should be the default for that path.

### Phase 5 — Testing and compliance

12. **Tests**
    - Unit tests: `decoration_mode_for_new_window()` for each policy; Force SSD → all windows get ServerSide.
    - Integration: client that supports xdg-decoration gets configure(server_side) when Force SSD on; client does not draw decorations (manual or automated if we have a test client).
    - Fullscreen shell: present surface → one borderless fullscreen window; no double titlebar.

13. **Docs**
    - Update 2026-CHECKLIST.md and 2026-ARCHITECTURE-STRUCTURE.md: decoration_mode in WindowCreated; set_decoration_mode and DecorationModeChanged used; fullscreen shell implies no host chrome.
    - User-facing: “Force SSD” in Settings > Display means “only the host’s window decoration is shown; apps must not draw their own titlebar or shadow.”

---

## 5. Protocol Summary (what clients see)

- **zxdg_decoration_manager_v1**: Advertised; client can get_toplevel_decoration(toplevel).
- **zxdg_toplevel_decoration_v1**: Client may set_mode(client_side | server_side) or unset_mode(). Wawona sends configure(mode) where mode is:
  - **Force SSD**: always `server_side`.
  - **PreferClient**: client’s preference if any, else client_side.
  - **PreferServer**: client’s preference if any, else server_side.
- After configure(server_side), client must draw without decorations and ack configure. So “do not render client-side decoration” when Force SSD is enabled is enforced by the protocol; Wawona must enforce it on the host side (only host chrome) and optionally use set_window_geometry for input/frame bounds.

---

## 6. File-level checklist

| Area | File(s) | Change |
|------|---------|--------|
| Event | `src/core/compositor.rs` | Add `decoration_mode` (and optionally `fullscreen_shell`) to `WindowCreated`. |
| Toplevel creation | `src/core/wayland/xdg/xdg_surface.rs` | Set `decoration_mode: state.decoration_mode_for_new_window()` in `WindowCreated`; do not overwrite window size in set_window_geometry (Phase 2). |
| Fullscreen shell | `src/core/wayland/ext/fullscreen_shell.rs` | Set decoration_mode and/or no_host_decoration for created window. |
| Decoration logic | `src/core/wayland/xdg/decoration.rs`, `plasma/kde_decoration.rs` | When mode changes, push DecorationModeChanged and ensure callback set_decoration_mode is invoked (via event processing in api.rs). |
| Force SSD | `src/ffi/api.rs` | When updating all windows’ decoration_mode, push DecorationModeChanged for each; pass decoration_mode in WindowCreated handling; implement or wire set_decoration_mode. |
| Geometry | `src/core/wayland/xdg/xdg_surface.rs` (and surface/window state) | Store set_window_geometry in a dedicated field; use for hit-test; stop overwriting window width/height. |
| macOS bridge | `src/platform/macos/WWNCompositorBridge.m` | In handleWindowCreated, use decoration_mode and fullscreen_shell to choose styleMask (titled vs borderless vs fullscreen borderless). |
| macOS callbacks | `src/platform/macos/WWNPlatformCallbacks.m` | If used for window creation, receive useSSD from decoration_mode. |
| Input | `src/input/input_handler.m` | Keep using geometry for pick and hit-test; ensure geometry source is the new stored field once added. |
| Android/iOS | Relevant platform code | Apply same decoration_mode / no_host_decoration semantics for window style. |
| Docs | `docs/2026-CHECKLIST.md`, `docs/2026-ARCHITECTURE-STRUCTURE.md` | Document Force SSD behavior and fullscreen shell. |

---

## 7. References (in-tree)

- **Wayland Book (xdg-decoration)**: `docs/wayland-book/xdg-shell-in-depth/interactive.md` (§ xdg-decoration).
- **Wayland Book (configuration/fullscreen)**: `docs/wayland-book/xdg-shell-in-depth/configuration.md`.
- **Checklist**: `docs/2026-CHECKLIST.md` (Inspiration index, xdg_decoration status).
- **Compositor comparison**: `docs/2026-COMPOSITOR-COMPARISON-AND-ROADMAP.md`.
- **Core state**: `src/core/state/mod.rs` (DecorationPolicy, decoration_mode_for_new_window).
- **Decoration impl**: `src/core/wayland/xdg/decoration.rs`, `src/core/wayland/plasma/kde_decoration.rs`.
- **Fullscreen shell**: `src/core/wayland/ext/fullscreen_shell.rs`.

This plan ensures Wawona correctly implements decoration protocols, respects Force SSD so that only the host’s compositor userchrome is used and clients do not render CSD when Force SSD is enabled, and treats fullscreen shell as kiosk with no host decoration on macOS, iOS, and Android.
