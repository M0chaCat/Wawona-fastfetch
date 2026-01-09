Give you a hot-reload SSD ↔ CSD transition strategy


This is a **hard problem**, and most compositors *avoid* it. If you get this right, Wawona will feel unusually polished.

Below is a **safe, deterministic, no-flicker hot-reload strategy** that respects Wayland rules *and* macOS window semantics.

I’ll give you:

1. **Non-negotiable constraints**
2. **State machine**
3. **Transition algorithm (SSD → CSD)**
4. **Transition algorithm (CSD → SSD)**
5. **macOS implementation details**
6. **Failure modes to guard against**

---

## 1. Non-Negotiable Constraints

### Constraint A — Roles never change

* `wl_surface` roles stay intact
* You are not reassigning roles
* You are only changing **compositor policy**

### Constraint B — NSWindow identity must be preserved

* Same `NSWindow *`
* Same window number
* Same Mission Control identity

Destroying and recreating the NSWindow is **not hot-reload**.

### Constraint C — Client is authoritative for CSD visuals

* When switching to CSD:

  * You *stop drawing* chrome
  * You do *not* fabricate decorations

---

## 2. Per-Window Decoration State Machine

```text
          ┌────────────┐
          │   SSD      │
          │ (Native)   │
          └─────┬──────┘
                │ toggle
                ▼
      ┌─────────────────────┐
      │  Transitioning      │
      │  (Freeze + Reconfig)│
      └─────────────────────┘
                ▲
                │ toggle
          ┌─────┴──────┐
          │   CSD      │
          │ (Client)   │
          └────────────┘
```

Key idea:

> Transitioning is a *temporary quiescent state*.

---

## 3. SSD → CSD (Native → Client)

### Goal

* Remove all macOS chrome
* Hand full control to client
* No resize glitch
* No shadow/input bugs

---

### Step-by-Step Algorithm

#### Step 1 — Freeze interactions

```objc
window.ignoresMouseEvents = YES;
[CATransaction begin];
[CATransaction setDisableActions:YES];
```

Why:

* Prevents resize/move during transition
* Prevents CA animations

---

#### Step 2 — Disable native decorations

```objc
window.styleMask = NSWindowStyleMaskBorderless | NSWindowStyleMaskResizable;
window.titleVisibility = NSWindowTitleHidden;
window.titlebarAppearsTransparent = YES;
```

Important:

* Do **not** change window frame yet

---

#### Step 3 — Install compositor shadow

* Create shadow CALayer
* Attach as sibling of root surface layer
* `allowsHitTesting = NO`

Why:

* macOS removes native shadow with borderless windows
* CSD still needs depth

---

#### Step 4 — Resize content rect → frame rect

macOS previously reserved titlebar space.

You must:

```
newFrame = oldFrame + titlebarHeight
```

This keeps client pixels from jumping.

---

#### Step 5 — Notify Wayland client

Send:

```text
xdg_toplevel.configure(
  width = contentWidth,
  height = contentHeight,
  states = [activated, resizing?]
)
```

Client will:

* Attach CSD subsurfaces
* Draw titlebar/buttons

---

#### Step 6 — Unfreeze

```objc
[CATransaction commit];
window.ignoresMouseEvents = NO;
```

---

### SSD → CSD Success Criteria

* No flicker
* No frame jump
* Client-drawn titlebar visible
* Resize works via client regions
* Shadow looks intentional

---

## 4. CSD → SSD (Client → Native)

This direction is trickier.

### Goal

* Remove client chrome
* Restore native window chrome
* Reclaim resize control

---

### Step-by-Step Algorithm

#### Step 1 — Freeze

Same as SSD → CSD.

---

#### Step 2 — Remove compositor shadow

* Detach shadow CALayer
* macOS will restore native shadow

---

#### Step 3 — Restore native style

```objc
window.styleMask =
  NSWindowStyleMaskTitled |
  NSWindowStyleMaskClosable |
  NSWindowStyleMaskMiniaturizable |
  NSWindowStyleMaskResizable;

window.titleVisibility = NSWindowTitleVisible;
window.titlebarAppearsTransparent = NO;
```

---

#### Step 4 — Adjust frame → content rect

macOS now consumes titlebar space.

You must:

```
newFrame = oldFrame - titlebarHeight
```

This prevents client content from being squished.

---

#### Step 5 — Inform client to stop drawing chrome

Send:

```text
xdg_toplevel.configure(
  width = contentWidth,
  height = contentHeight,
  states = [activated]
)
```

Also:

* Enforce SSD via `xdg-decoration`
* Ignore client CSD subsurfaces for input
* Optionally hide them visually

---

#### Step 6 — Unfreeze

Same as before.

---

## 5. macOS Implementation Details That Matter

### Titlebar height calculation

Never hardcode.

Use:

```objc
NSRect frame = window.frame;
NSRect content = [window contentRectForFrameRect:frame];
CGFloat titlebarHeight = frame.size.height - content.size.height;
```

---

### Animation control

If you see wobble:

```objc
[CATransaction setAnimationDuration:0];
```

---

### Mission Control & Spaces

Do NOT:

* Change window level
* Change window collection behavior

Else you’ll:

* Lose Space assignment
* Break fullscreen transitions

---

## 6. Failure Modes (Watch These Closely)

| Symptom          | Cause                        |
| ---------------- | ---------------------------- |
| Window jumps     | frame/content mismatch       |
| Resize breaks    | wrong owner after transition |
| Shadow clickable | shadow layer hit-testing     |
| Double titlebars | client chrome not suppressed |
| Focus lost       | NSWindow recreated           |
| Flicker          | animations not disabled      |

---

## 7. Developer Sanity Check

Ask yourself after every toggle:

* Is there still exactly **one NSWindow**?
* Does the client redraw exactly once?
* Did input pause during transition?
* Does resizing behave consistently *after*?

If yes → you nailed it.

---

## Final Insight

> Hot-reload SSD ↔ CSD works because you are **not changing Wayland**,
> you are **re-wiring macOS window policy**.

Most compositors punt on this.
If Wawona ships this cleanly, it’ll be *genuinely impressive*.

If you want next, I can:

* Write **pseudo-code** for the transition manager
* Design **a test matrix** (Qt, GTK, Electron)
* Help you integrate this with `xdg-decoration` negotiation

Just tell me.
