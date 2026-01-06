Below is a **complete, structured map of Wayland protocols**, plus **where they live, how to discover them, and how compositors decide what to support**.
This is the same mental model used by **Weston, wlroots, Mutter, KWin, and Waypipe**.

I’ll give you:

1. **What “complete list” really means in Wayland terms**
2. **Authoritative sources (where protocols come from)**
3. **The actual protocol families (core + extensions)**
4. **Which ones are essential vs optional**
5. **How projects like Wawona should track them**

---

# 1. First: what “complete list” means (important)

There is **no single canonical list** of *all* Wayland protocols.

Wayland protocols are:

* XML files
* Versioned
* Distributed across multiple repositories
* Some are standardized, others are compositor-specific

So “complete” means:

> **All standardized protocols + all widely-used de facto protocols + knowing how to discover new ones**

That’s what you actually need.

---

# 2. Authoritative places to find Wayland protocols

### 2.1 Core Wayland protocols (the official base)

**Repository:**
👉 [https://gitlab.freedesktop.org/wayland/wayland](https://gitlab.freedesktop.org/wayland/wayland)

Location:

```
protocol/
```

These define:

* `wl_display`
* `wl_registry`
* `wl_compositor`
* etc.

---

### 2.2 Wayland Protocols Extensions (MOST IMPORTANT)

**Repository:**
👉 [https://gitlab.freedesktop.org/wayland/wayland-protocols](https://gitlab.freedesktop.org/wayland/wayland-protocols)

This is where **almost everything** lives.

Structure:

```
stable/
unstable/
staging/
```

This repo is the **de facto standard set**.

---

### 2.3 wlroots protocols (practically important)

**Repository:**
👉 [https://gitlab.freedesktop.org/wlroots/wlroots](https://gitlab.freedesktop.org/wlroots/wlroots)

Location:

```
protocol/
```

These are:

* Widely deployed
* Not “officially” Wayland yet
* Required for real desktops

---

### 2.4 Desktop-specific protocols

* GNOME (Mutter)
* KDE (KWin)
* ChromeOS (Sommelier)
* River / Sway extensions

You usually **don’t implement these unless needed**.

---

# 3. Core Wayland Protocols (mandatory)

These come from `wayland/wayland`.

You **must** implement these.

### Core

* `wl_display`
* `wl_registry`
* `wl_callback`
* `wl_compositor`
* `wl_surface`
* `wl_region`
* `wl_shm`
* `wl_buffer`
* `wl_seat`
* `wl_pointer`
* `wl_keyboard`
* `wl_touch`
* `wl_output`

Without these, you don’t have Wayland.

---

# 4. Stable extension protocols (from wayland-protocols)

These are **widely expected**.

### Window management

* `xdg_wm_base`
* `xdg_surface`
* `xdg_toplevel`
* `xdg_popup`
* `xdg_positioner`

This replaces `wl_shell`.

---

### Rendering & presentation

* `wp_viewporter`
* `wp_presentation`
* `wp_fractional_scale_v1`
* `wp_content_type_v1`

---

### Buffer sharing

* `zwp_linux_dmabuf_v1`

**Critical for Vulkan, Waypipe, GPU clients**

---

### Input enhancements

* `zwp_relative_pointer_manager_v1`
* `zwp_pointer_constraints_v1`
* `zwp_text_input_v3`
* `zwp_input_method_v2`
* `zwp_virtual_keyboard_v1`

---

### Data & clipboard

* `wl_data_device_manager`
* `zwp_primary_selection_device_manager_v1`
* `zwp_data_control_manager_v1`

---

### Session & power

* `zwp_idle_inhibit_manager_v1`

---

# 5. Unstable protocols (still widely used)

These are prefixed with `z` or `zwp`.

They are **expected by modern apps**.

### Examples

* `zxdg_decoration_manager_v1`
* `zwp_tablet_manager_v2`
* `zwp_linux_dmabuf_feedback_v1`
* `zwp_security_context_v1`
* `zwp_pointer_gestures_v1`

Unstable does **not** mean optional in practice.

---

# 6. wlroots protocols (very important for real desktops)

If you want **Waypipe, nested compositors, and advanced use cases**, these matter.

Common wlroots protocols:

* `wlr_layer_shell_v1`
* `wlr_foreign_toplevel_management_v1`
* `wlr_output_management_v1`
* `wlr_gamma_control_v1`
* `wlr_screencopy_v1`
* `wlr_export_dmabuf_v1`

For Wawona:

* `wlr_foreign_toplevel_management_v1` → optional
* `wlr_layer_shell_v1` → optional (panels)
* `wlr_export_dmabuf_v1` → very useful

---

# 7. Rare / compositor-specific protocols

You usually **do not implement these initially**.

Examples:

* KDE-specific decoration protocols
* GNOME private extensions
* Experimental color management protocols

Implement only if needed.

---

# 8. How compositors decide what to support (important)

### Tier 1 – Required

Must-have for *any* Wayland compositor:

* Core Wayland
* `xdg_shell`
* Basic input
* `wl_output`

### Tier 2 – Expected

Needed for modern apps:

* `linux-dmabuf`
* fractional scaling
* presentation-time
* relative pointer

### Tier 3 – Power-user / advanced

Needed for:

* Waypipe
* Nested compositors
* Screen capture
* Panels

---

# 9. How to discover protocols programmatically

### From a running compositor

```bash
wayland-info
```

or

```bash
weston-info
```

This lists:

* Globals
* Protocol versions
* Extensions

---

### From source trees

```bash
find /usr/share/wayland-protocols -name "*.xml"
```

or in repos:

```bash
git grep protocol
```

---

# 10. How Wawona should track protocols (recommended)

For Wawona, do this:

```
protocols/
 ├─ core/
 ├─ stable/
 ├─ unstable/
 ├─ wlr/
 └─ experimental/
```

Each protocol:

* Generated bindings
* Capability flags
* Versioned support

Expose to clients via:

```c
wl_global_create(...)
```

---

# 11. Practical “complete list” summary

### Absolutely essential

* Core Wayland
* `xdg_shell`

### Required for Vulkan + Waypipe

* `linux-dmabuf`
* `presentation-time`
* External memory sync

### Required for nested compositors

* `foreign_toplevel`
* `export_dmabuf`
* Relative pointer

---

## Final takeaway

> **Wayland has no single “complete list” — instead, it has a living ecosystem of protocols distributed across several authoritative repos. A real compositor supports a curated, tiered subset.**

If you want, next I can:

* Produce a **Wawona-specific protocol support matrix**
* Generate a **“minimum viable Wayland compositor” protocol list**
* Show how to **auto-generate protocol bindings**
* Or map **Waypipe-required protocols exactly**

Just tell me which one.
