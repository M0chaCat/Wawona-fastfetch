tell me about the different types of wayland surfaces.

In Wayland, **“surface”** is a deliberately minimal concept: it’s just a buffer + state that a compositor can place somewhere. All the *meaning* (window, popup, cursor, panel, etc.) comes from **protocols layered on top of `wl_surface`**.

Below is a clean mental model, starting from the base and building up. I’ll keep it structured and concrete, since you’re writing a compositor.

---

## 1. `wl_surface` (the base primitive)

**What it is**

* A drawable rectangle backed by buffers (SHM, dmabuf, EGL, etc.)
* Has no role by itself: no position, no stacking, no input semantics

**What it can do**

* Attach a buffer
* Commit state
* Receive damage
* Be assigned a *role* by exactly one role protocol

**Critical rule**

> A `wl_surface` may have **only one role for its lifetime**

If a client tries to assign a second role → protocol error.

---

## 2. Toplevel surfaces (windows)

These are “real windows” in desktop environments.

### `xdg_toplevel` (modern, standard)

Defined by `xdg-shell`.

**Represents**

* Normal application windows
* Can be moved, resized, maximized, fullscreened, minimized

**Key properties**

* Has decorations via `xdg-decoration` (SSD vs CSD)
* Has states:

  * maximized
  * fullscreen
  * activated
  * resizing
  * tiled (left/right/top/bottom)
* Resize is **compositor-driven**
* Client redraws after receiving `configure`

**In compositor terms**

* Maps cleanly to:

  * macOS `NSWindow`
  * Wayland “managed window”
  * Top-level CALayer tree

---

### Legacy: `wl_shell_surface` (deprecated)

You’ll still see this in very old apps.

**Types**

* `toplevel`
* `popup`
* `transient`

**Reality**

* Avoid unless you need compatibility
* No modern decoration or tiling semantics

---

## 3. Popup surfaces (menus, tooltips, context menus)

### `xdg_popup`

**Represents**

* Right-click menus
* Dropdowns
* Tooltips
* Combobox lists

**Defining traits**

* Always associated with a *parent surface*
* Positioned relative to an **anchor rect**
* Automatically dismissed when:

  * Parent loses focus
  * User clicks outside
* Cannot be resized arbitrarily
* Cannot be maximized or fullscreen

**Important compositor rules**

* Popups must stay within the “popup grab”
* You must enforce repositioning if they go off-screen
* Often rendered **above** their parent

**macOS analogy**

* NSPopover / NSMenu
* Non-activating floating panels

---

## 4. Subsurfaces (surface trees)

### `wl_subsurface`

**Represents**

* Child surfaces that are spatially tied to a parent surface
* Rendered as part of the same window

**Common uses**

* Client-side decorations
* Custom title bars
* Embedded widgets
* Video overlays

**Key properties**

* Position is **relative to parent**
* Z-order can be above or below parent
* Commit can be synchronized or desynchronized

**For your compositor**

* This is how CSD is usually built
* You should NOT treat subsurfaces as separate windows
* They should not get independent shadows or window chrome

---

## 5. Layer surfaces (panels, bars, overlays)

### `zwlr_layer_surface_v1` (wlroots protocol)

**Represents**

* Panels (top bars, docks)
* Desktop backgrounds
* Notifications
* Lock screens
* On-screen displays

**Layer types**

* `background`
* `bottom`
* `top`
* `overlay`

**Properties**

* Anchored to screen edges
* Can reserve exclusive zones
* Can be keyboard-interactive or passive

**Compositor behavior**

* These bypass normal window management
* Often drawn in fixed screen coordinates
* Not resizable or movable like windows

**macOS analogy**

* Menu bar
* Dock
* System overlays
* Full-screen status layers

---

## 6. Cursor & drag surfaces

### Cursor surface

Set via `wl_pointer.set_cursor`

**Represents**

* Mouse cursor image

**Traits**

* Very short-lived
* Not part of normal stacking
* Input-only semantics

---

### Drag-and-drop icon surface

Used during DnD operations.

**Traits**

* Follows pointer
* Client-controlled visuals
* Compositor-controlled lifetime

---

## 7. Input-only & special-purpose surfaces

### `wp_viewporter` + fractional scale

* Used for scaling and viewport cropping

### `wp_relative_pointer`, `pointer_constraints`

* Affect input, not visuals

### `wp_cursor_shape`

* Declarative cursor shape instead of surfaces

These don’t create new *kinds* of surfaces, but modify how a surface behaves.

---

## 8. XWayland surfaces

### X11 → Wayland bridge

**Represents**

* Legacy X11 windows

**Traits**

* Often behave like `xdg_toplevel`
* Decorations may be inconsistent
* Resize semantics are more X11-like

**Compositor note**

* You often need special casing
* Especially for focus, stacking, and CSD/SSD conflicts

---

## 9. Putting it all together (mental model)

```
wl_surface
 ├── xdg_toplevel        → normal window
 ├── xdg_popup           → menus, tooltips
 ├── wl_subsurface       → child surface (CSD, widgets)
 ├── zwlr_layer_surface  → panels, overlays
 ├── cursor surface      → pointer image
 └── xwayland surface    → legacy X11 window
```

---

## 10. Key rules every compositor must enforce

1. **One role per surface**
2. **Client draws, compositor decides size**
3. **Popups are transient and constrained**
4. **Subsurfaces are not windows**
5. **Layer surfaces bypass normal WM rules**

---

## Mapping to your macOS compositor

Given your architecture:

* **`xdg_toplevel`** → `NSWindow` + CALayer tree
* **CSD** → client-rendered subsurfaces (no macOS chrome)
* **SSD** → native NSWindow decorations
* **Shadows** → compositor-owned layers (never subsurfaces)
* **Popups** → floating non-activating windows or layers
* **Layer surfaces** → fixed global CALayers above/below windows

If you want, next we can:

* Walk through **surface lifetimes**
* Design a **Wayland → macOS window state machine**
* Or deep-dive into **CSD vs SSD edge cases** (which you’re already hitting)




compare to native macOS windowing features. 
in Cocoa/AppKit, Metal, and so on. 

Give me parallels. like NSPanel, NSWindow, NSView, or whatever.
What if I made a macOS Native app clone of a wayland app, what components/surfaces would map to what.



This is a great question, and you’re asking it at exactly the *right* abstraction level. Wayland and AppKit solve the same problems but split responsibility **very differently**. Below is a **side-by-side mental model**, not just API names.

I’ll start with a **high-level mapping table**, then drill into each category with *behavioral parallels*, and finally show what a **native macOS clone of a Wayland app** would look like architecturally.

---

# 1. Core Philosophy Difference (important first)

| Wayland                            | macOS                                |
| ---------------------------------- | ------------------------------------ |
| Client draws *everything*          | System draws window chrome           |
| Compositor owns placement & policy | WindowServer owns placement & policy |
| Surfaces are dumb buffers          | Windows & Views are semantic objects |
| Resize is protocol-driven          | Resize is event-driven               |
| Decorations are optional           | Decorations are default              |

This is why **Wayland surfaces ≠ macOS windows** one-to-one.

---

# 2. Base Primitive Mapping

## `wl_surface` ↔ `CALayer` (NOT NSWindow)

This is the most important parallel.

| Wayland           | macOS                      |
| ----------------- | -------------------------- |
| `wl_surface`      | `CALayer`                  |
| Buffer attachment | `contents` / Metal texture |
| `commit()`        | layer transaction          |
| Damage            | layer invalidation         |
| Scale             | `contentsScale`            |

**Why not NSView?**

* NSView is *event + layout + drawing*
* `wl_surface` is **just pixels + state**

In your compositor:

> A `wl_surface` should usually become **one CALayer**, not one NSWindow.

---

# 3. Toplevel Windows

## `xdg_toplevel` ↔ `NSWindow`

This is the cleanest mapping.

| Wayland                    | macOS               |
| -------------------------- | ------------------- |
| `xdg_toplevel`             | `NSWindow`          |
| `configure(width, height)` | `setFrame:`         |
| maximize                   | `zoom:` / tiled     |
| fullscreen                 | `toggleFullScreen:` |
| activated                  | key/main window     |
| close                      | `performClose:`     |

### Resize semantics

| Wayland                           | macOS                             |
| --------------------------------- | --------------------------------- |
| Compositor initiates resize       | WindowServer initiates resize     |
| Client redraws on `configure`     | App redraws in `drawRect` / layer |
| Resize edges are compositor logic | Resize edges are WindowServer     |

**Key insight**

> macOS is *implicitly SSD*. Wayland supports SSD *and* CSD.

---

## SSD vs CSD Mapping

### Server-Side Decoration (SSD)

| Wayland                    | macOS               |
| -------------------------- | ------------------- |
| compositor draws chrome    | NSWindow chrome     |
| client draws content only  | contentView         |
| shadow owned by compositor | WindowServer shadow |

This maps *perfectly* to AppKit.

---

### Client-Side Decoration (CSD)

| Wayland                      | macOS                |
| ---------------------------- | -------------------- |
| client draws titlebar        | custom titlebar view |
| subsurfaces                  | child CALayers       |
| resize via invisible regions | tracking areas       |

**macOS equivalent**

* `titleVisibility = hidden`
* `titlebarAppearsTransparent = YES`
* Client draws chrome inside contentView

This is exactly what Electron, Firefox, and VS Code do on macOS.

---

# 4. Subsurfaces

## `wl_subsurface` ↔ child `CALayer` or `NSView`

| Wayland              | macOS                       |
| -------------------- | --------------------------- |
| subsurface           | sublayer / subview          |
| relative positioning | frame relative to superview |
| CSD widgets          | custom titlebar views       |
| z-order control      | layer ordering              |

**Important**

> Subsurfaces should NEVER become NSWindows.

If you do that, you get:

* broken focus
* broken input routing
* broken shadows

Which matches the bugs you’ve been debugging 🙂

---

# 5. Popups / Menus

## `xdg_popup` ↔ `NSPanel` / `NSMenu` / transient NSWindow

| Wayland                    | macOS            |
| -------------------------- | ---------------- |
| `xdg_popup`                | `NSPanel`        |
| transient                  | non-activating   |
| dismissed on outside click | auto-close       |
| parent-relative            | attachedToWindow |

Recommended AppKit config:

```objc
NSPanel *panel = [[NSPanel alloc]
    initWithContentRect:...
    styleMask:NSWindowStyleMaskBorderless
    backing:NSBackingStoreBuffered
    defer:NO];

panel.level = NSFloatingWindowLevel;
panel.becomesKeyOnlyIfNeeded = YES;
panel.worksWhenModal = YES;
```

This mirrors `xdg_popup` *almost perfectly*.

---

# 6. Layer Surfaces

## `zwlr_layer_surface_v1` ↔ system-level windows

| Wayland Layer | macOS             |
| ------------- | ----------------- |
| background    | desktop window    |
| bottom        | wallpaper layer   |
| top           | menu bar / dock   |
| overlay       | lock screen / HUD |

macOS equivalents:

* `NSWindow` at specific window levels:

  * `NSStatusWindowLevel`
  * `NSDockWindowLevel`
  * `NSPopUpMenuWindowLevel`
* Screen-anchored frames
* Reserved screen space (menu bar, dock)

**Exclusive zone**
→ macOS’s “usable screen frame”

---

# 7. Cursor & Drag Surfaces

## Cursor surface ↔ `NSCursor`

| Wayland               | macOS                   |
| --------------------- | ----------------------- |
| cursor surface        | NSCursor                |
| buffer                | CGImage                 |
| compositor controlled | WindowServer controlled |

Drag icon surface ↔ drag image during `NSDraggingSession`

---

# 8. Input Model Comparison

| Wayland                 | macOS                     |
| ----------------------- | ------------------------- |
| compositor routes input | WindowServer routes input |
| focus explicit          | key/main window           |
| pointer enter/leave     | mouseEntered/mouseExited  |
| grabs                   | modal loops               |

macOS hides this behind:

* responder chain
* hit-testing
* tracking areas

---

# 9. Rendering Stack Parallels

| Wayland    | macOS             |
| ---------- | ----------------- |
| SHM buffer | CPU bitmap        |
| dmabuf     | IOSurface         |
| EGL        | Metal             |
| OpenGL     | deprecated OpenGL |
| commit     | CATransaction     |

Your compositor is essentially:

> a custom WindowServer frontend backed by AppKit + CoreAnimation.

---

# 10. “Clone a Wayland App as Native macOS”

Let’s say you’re cloning a Wayland app **natively**, not via Wayland.

### Wayland App Structure

```
xdg_toplevel
 ├── subsurface (titlebar)
 ├── subsurface (buttons)
 └── subsurface (content)
```

### Native macOS Clone

```
NSWindow
 └── contentView
     ├── Titlebar NSView
     ├── Control NSView
     └── Content NSView
```

Or layer-backed:

```
NSWindow
 └── root CALayer
     ├── shadow (WindowServer)
     ├── titlebar CALayer
     ├── controls CALayer
     └── content CALayer
```

### Behavior Mapping

| Wayland Behavior | macOS Implementation    |
| ---------------- | ----------------------- |
| configure        | setFrame                |
| redraw           | displayIfNeeded         |
| CSD resize       | tracking areas          |
| popup            | NSPanel                 |
| fullscreen       | native fullscreen space |
| maximize         | zoom / tile             |

---

# 11. Key Insight (this matters for your compositor)

> Wayland is **protocol-first**
> macOS is **object-first**

Your job (which you’re already doing) is:

* Translate *protocol state* → *object graph*
* Avoid inventing semantics macOS already gives you
* Use NSWindow when the surface has **window semantics**
* Use CALayer when the surface has **pixel semantics**

---

If you want next:

* A **one-page cheat sheet** mapping every Wayland protocol → AppKit class
* A **state machine diagram** for xdg_toplevel ↔ NSWindow
* Or a deep dive into **why macOS resize feels different from Wayland** (edge vs protocol driven)

Just tell me where you want to zoom in.



I'm writing a wayland compositor for macOS called Wawona Compositor.

it will support both SSD (Server-Side Decorations, macOS Native Cocoa drawing) and CSD (Client-Side Decorations, the wayland client app chooses decorations for the window surfaces). 


Give me a plan to bridge all wayland surfaces properly, and how I can make my SSD (Server-Side Decorations) on native macOS more native to macOS, had I connected a wayland client to my macOS wayland compositor with SSD enabled. 


This is a **systems design problem**, not an API question — so I’m going to give you a **clear, implementable architecture** that matches both Wayland *and* macOS semantics, and avoids the failure modes you’ve already been hitting.

I’ll structure this as:

1. **Foundational rules (non-negotiable invariants)**
2. **Surface → macOS object model**
3. **SSD vs CSD decision pipeline**
4. **Window construction on macOS**
5. **Input, resize, and shadow ownership**
6. **Popup & layer handling**
7. **Making SSD feel truly “macOS native”**
8. **Debug checklist (things that always break)**

---

## 1. Foundational Rules (lock these in)

These rules prevent 90% of compositor bugs.

### Rule 1 — One NSWindow per *toplevel*

* `xdg_toplevel` → **exactly one `NSWindow`**
* Never create multiple NSWindows for subsurfaces, shadows, or popups

### Rule 2 — All Wayland surfaces are CALayers

* Every `wl_surface` becomes **one CALayer**
* Subsurfaces → sublayers
* No exceptions

### Rule 3 — macOS owns chrome *only* in SSD

* If SSD is enabled:

  * Wayland client **never draws chrome**
  * macOS draws titlebar, buttons, shadow
* If CSD is enabled:

  * macOS chrome is **fully disabled**
  * Client draws everything

### Rule 4 — Shadows are compositor-owned, never client-owned

* Shadow = WindowServer or compositor layer
* Never attach shadow to a `wl_surface`
* Never hit-test shadows

---

## 2. Surface → macOS Object Model

### Core mapping (final form)

```
Wayland client
  └─ wl_surface (role)
       ├─ xdg_toplevel      → NSWindow
       ├─ xdg_popup         → NSPanel
       ├─ wl_subsurface     → CALayer (child)
       ├─ layer_surface     → NSWindow (special level)
       └─ cursor surface    → NSCursor
```

### Internal compositor objects

```
WawonaSurface
 ├─ wl_surface
 ├─ role
 ├─ CALayer *
 ├─ input_region
 └─ opaque_region

WawonaWindow
 ├─ xdg_toplevel
 ├─ NSWindow *
 ├─ root CALayer *
 ├─ decoration_mode (SSD | CSD)
 └─ state (max, fullscreen, tiled)
```

---

## 3. SSD vs CSD Decision Pipeline

This must be **deterministic** and **hot-reloadable**.

### Inputs

* Global compositor setting: `force_ssd`
* Client preference: `xdg-decoration`
* Fallback: client supports / doesn’t support CSD

### Decision Logic (authoritative)

```
if force_ssd:
    decoration_mode = SSD
else if client requests CSD:
    decoration_mode = CSD
else:
    decoration_mode = SSD
```

### Enforcement

* SSD:

  * Reject client-drawn decorations
  * Strip subsurfaces intended for titlebar
* CSD:

  * Disable all macOS chrome
  * No titlebar, no traffic lights, no shadow chrome

**Important**

> Decoration mode is per-toplevel, not global.

---

## 4. macOS Window Construction

### SSD Window (native feel)

```objc
NSWindowStyleMask style =
    NSWindowStyleMaskTitled |
    NSWindowStyleMaskClosable |
    NSWindowStyleMaskMiniaturizable |
    NSWindowStyleMaskResizable;

NSWindow *window = [[NSWindow alloc]
    initWithContentRect:initialFrame
    styleMask:style
    backing:NSBackingStoreBuffered
    defer:NO];

window.titleVisibility = NSWindowTitleVisible;
window.titlebarAppearsTransparent = NO;
window.toolbar = nil;
window.hasShadow = YES;
```

**Wayland content**

```
NSWindow
 └── contentView
     └── root CALayer
         └── wl_surface layer tree
```

---

### CSD Window (client owns everything)

```objc
NSWindowStyleMask style =
    NSWindowStyleMaskBorderless |
    NSWindowStyleMaskResizable;

window.titleVisibility = NSWindowTitleHidden;
window.titlebarAppearsTransparent = YES;
window.hasShadow = YES; // compositor shadow
```

**Client owns**

* Titlebar
* Buttons
* Resize visuals

**You own**

* Resize logic
* Hit-test regions
* Shadow

---

## 5. Resize, Input, and Shadow Ownership

### Resize (SSD)

| Responsibility | Owner               |
| -------------- | ------------------- |
| Edge detection | WindowServer        |
| Resize begin   | macOS               |
| Frame change   | macOS               |
| Redraw request | Wayland `configure` |

**You do**

* Convert `setFrame:` → `xdg_toplevel.configure`

---

### Resize (CSD)

| Responsibility | Owner  |
| -------------- | ------ |
| Edge detection | Wawona |
| Resize begin   | Wawona |
| Frame change   | Wawona |
| Redraw         | Client |

**Implementation**

* Invisible resize zones (like Chromium)
* Map drag → `xdg_toplevel.configure`

---

### Shadows

| Mode | Shadow source      |
| ---- | ------------------ |
| SSD  | WindowServer       |
| CSD  | Compositor CALayer |

**Shadow CALayer**

* Sibling to content layer
* `allowsHitTesting = NO`
* Excluded from input regions

---

## 6. Popups, Menus, and Layer Surfaces

### `xdg_popup`

→ `NSPanel`

Properties:

* Borderless
* Floating
* Non-activating
* Parent-relative positioning
* Auto-dismiss on outside click

Never:

* Give popups shadows like windows
* Let popups become key windows

---

### `zwlr_layer_surface_v1`

→ Specialized NSWindow

| Layer      | macOS Window Level   |
| ---------- | -------------------- |
| background | Desktop level        |
| bottom     | Below normal windows |
| top        | Status / Dock        |
| overlay    | Screen saver / HUD   |

Respect:

* Anchors
* Exclusive zones
* Output-local placement

---

## 7. Making SSD Feel *Truly* Native on macOS

This is where Wawona wins.

### Use native macOS affordances

**Do this**

* Native traffic-light buttons
* Native window snapping
* Native fullscreen spaces
* Native Mission Control behavior
* Native window shadows
* Native vibrancy (optional)

**Avoid**

* Fake titlebars
* Fake buttons
* Custom shadows in SSD
* Nonstandard resize behavior

---

### Wayland → macOS polish mappings

| Wayland Concept | Native macOS Behavior |
| --------------- | --------------------- |
| maximize        | zoom / tile           |
| fullscreen      | native Space          |
| minimize        | Dock                  |
| activated       | key window            |
| urgent          | bounce Dock icon      |
| app_id          | bundle identifier     |
| window title    | NSWindow title        |

---

### Bonus: App Identity

Map:

* `xdg_toplevel.set_app_id`
  →
* Bundle ID
* Dock icon
* App menu name

This massively improves perceived “nativeness”.

---

## 8. Debug Checklist (save this)

If something feels wrong, check:

* ❌ Multiple NSWindows for one toplevel?
* ❌ Shadow layer receiving input?
* ❌ Subsurface promoted to window?
* ❌ CSD window still has macOS chrome?
* ❌ SSD window letting client draw titlebar?
* ❌ Resize initiated by wrong side?
* ❌ Popup stealing focus?

If **any** answer is yes, you’ve found the bug.

---

## Final Mental Model

> **Wawona is a Wayland policy engine driving AppKit objects**

* Wayland decides *what* exists
* macOS decides *how* it behaves (when SSD)
* CALayer is the glue
* NSWindow is a privilege, not a default

---

If you want next, I can:

* Draw a **lifecycle diagram** for `xdg_toplevel`
* Give you a **hot-reload SSD ↔ CSD transition strategy**
* Help you design **input region & hit-testing code**
* Or help spec a **Wayland conformance test plan**

Just say the word.
