# Waypipe for iOS

> Build waypipe as a static library for `aarch64-apple-ios-sim`, with all dependencies cross-compiled for iOS. Uses libssh2 for SSH tunnels (no process spawning).

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│  waypipe iOS Build (nix build .#waypipe-ios)        │
│                                                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  libwaypipe.a (Rust staticlib)                │  │
│  │  • Wayland proxy  • lz4/zstd compress         │  │
│  │  • dmabuf (Vulkan)  • libssh2 transport       │  │
│  └──────────────────────────────────────────────┘  │
│                                                     │
│  C Dependencies (static .a for aarch64-ios-sim)    │
│  ┌──────┐ ┌────┐ ┌────────┐ ┌──────────┐ ┌────────┐  │
│  │libffi│ │lz4 │ │libssh2 │ │libwayland│ │ zstd  │  │
│  └──────┘ └────┘ └────────┘ └──────────┘ └────────┘  │
│  ┌────────┐ ┌───────────┐                            │
│  │mbedtls │ │kosmickrisp│ (Vulkan)                   │
│  └────────┘ └───────────┘                            │
└─────────────────────────────────────────────────────┘
```

### Why Nix standalone build (workspace removed)

Two Rust `staticlib` crates each embed the Rust standard library. The iOS linker rejects duplicate symbols. **Workspace approach removed.** Waypipe is built as a separate static library via `dependencies/libs/waypipe/ios.nix`, producing `libwaypipe.a`. Use `nix build .#waypipe-ios` to build. Integration with Wawona app (e.g. loading waypipe when needed) is a follow-up.

---

## Dependency Matrix

| Library | Purpose | Nix Path | iOS Status |
|---------|---------|----------|------------|
| **zstd** | Compression | `dependencies/libs/zstd/` | ✅ Cross-compiled |
| **lz4** | Compression | `dependencies/libs/lz4/` | ✅ Cross-compiled |
| **libssh2** | SSH tunnels (replaces openssh) | `dependencies/libs/libssh2/` | ✅ Cross-compiled |
| **mbedtls** | TLS for libssh2 | `dependencies/libs/mbedtls/` | ✅ Cross-compiled |
| **libwayland** | Wayland client protocol | `dependencies/libs/libwayland/` | ✅ Cross-compiled |
| **libffi** | Required by libwayland | `dependencies/libs/libffi/` | ✅ Cross-compiled |
| **xkbcommon** | Keyboard handling | `dependencies/libs/xkbcommon/` | ✅ Cross-compiled |
| **pixman** | Pixel manipulation | `dependencies/libs/pixman/` | ✅ Cross-compiled |

---

## Waypipe Feature Selection

```toml
# From upstream waypipe Cargo.toml
[features]
default = ["video", "dmabuf", "lz4", "zstd", "gbmfallback", "test_proto"]
```

For iOS, we use:

| Feature | Enabled | Reason |
|---------|---------|--------|
| `lz4` | ✅ | Compression for Wayland protocol data |
| `zstd` | ✅ | Compression for Wayland protocol data |
| `dmabuf` | ✅ | GPU buffer sharing via Vulkan/ash |
| `video` | ❌ | wrap-ffmpeg stubbed; FFmpeg integration blocked on waypipe struct interface (see full-plan) |
| `gbmfallback` | ❌ | GBM not available on iOS |
| `test_proto` | ❌ | Test binary, not needed |

---

## iOS Source Patches

Waypipe was written for Linux. These patches make it iOS-compatible:

### 1. Socket Flags
iOS doesn't support `SOCK_CLOEXEC` / `SOCK_NONBLOCK` in `socket()`. Replace with `fcntl()` after creation:
```rust
// Before: socket::SockFlag::SOCK_CLOEXEC | socket::SockFlag::SOCK_NONBLOCK
// After: socket::SockFlag::empty(), then fcntl(fd, FD_CLOEXEC) + fcntl(fd, O_NONBLOCK)
```

### 2. unlinkat → unlink
iOS lacks `unlinkat()`. Replace with `unlink()`:
```rust
// Before: unistd::unlinkat(&self.folder, file_name, UnlinkatFlags::NoRemoveDir)
// After:  unistd::unlink(&self.full_path)
```

### 3. memfd / F_ADD_SEALS / F_GET_SEALS
iOS lacks `memfd_create` and seal operations. Stub or skip these calls.

### 4. User::from_uid
iOS sandbox has no `/etc/passwd`. Replace with hardcoded user info.

### 5. isatty().unwrap()
iOS may not have a TTY. Use `.unwrap_or(false)`.

### 6. Entry Point
Rename `fn main()` → `fn waypipe_real_main()`, add:
```rust
#[no_mangle]
pub extern "C" fn waypipe_main(argc: i32, argv: *const *const i8) -> i32
```

### 7. Wrapper Crates
- **wrap-lz4**: Replace `build.rs` with manual FFI bindings (no bindgen dependency)
- **wrap-zstd**: Replace `build.rs` with manual FFI bindings (no bindgen dependency)
- **wrap-gbm**: Stub (GBM not on iOS)
- **wrap-ffmpeg**: Disabled via feature flag
- **shaders**: Stub empty SPIR-V constants

---

## Build Integration

### Nix Standalone Build (current)

Waypipe is built via `dependencies/libs/waypipe/ios.nix`:

```bash
nix build .#waypipe-ios
```

Produces `libwaypipe.a` (static library) with:
- **libssh2** for SSH tunnels (no process spawn on iOS)
- **lz4**, **zstd** compression
- **dmabuf** via Vulkan/kosmickrisp
- **video** disabled (wrap-ffmpeg stubbed)

Dependencies use iOS cross-compiled libs from `buildModule.buildForIOS`: libssh2, mbedtls, libwayland, zstd, lz4, kosmickrisp.

**Note:** `libwaypipe.a` cannot be linked alongside `libwawona.a` due to duplicate Rust stdlib symbols. Integration strategies (e.g. separate process, dynamic loading) are a follow-up.

---

## Linker Flags

In `dependencies/wawona/ios.nix`, the final link command:
```bash
$CC $OBJ_FILES \
   -Lios-dependencies/lib \
   -lwawona \                    # includes waypipe symbols
   -lxkbcommon -lwayland-client -lffi -lpixman-1 -lzstd -llz4 \
   -lssh2 -lmbedtls -lmbedx509 -lmbedcrypto \
   -framework Foundation -framework UIKit -framework QuartzCore \
   -framework Metal -framework MetalKit -framework IOKit \
   -framework IOSurface -framework CoreGraphics \
   -o "$out/bin/Wawona"
```

Note: `-lwaypipe` is **not** needed when using the workspace approach — waypipe symbols are inside `libwawona.a`.

---

## SSH via libssh2

Upstream waypipe spawns `ssh` via `Command::new("ssh")`. iOS doesn't allow process spawning. The **libssh2** transport (to be wired) would replace process spawning with direct libssh2 FFI:

1. `libssh2_session_init()` → create session
2. `libssh2_session_handshake()` → negotiate SSH
3. `libssh2_userauth_*()` → authenticate
4. `libssh2_channel_open_session()` → open channel
5. Use the channel fd as the waypipe link fd

The iOS build links `libssh2` and `mbedtls` from `buildModule.ios`. Waypipe v0.10.6 may use the ssh2 crate; a `with_libssh2` feature or equivalent wiring is a follow-up for full openssh-compatible behavior.

---

## Task Checklist

- [x] Phase 1: Verify all C dependencies cross-compile for `aarch64-apple-ios-sim`
- [x] Phase 2: Build waypipe as staticlib via Nix (workspace removed)
  - [x] `dependencies/libs/waypipe/ios.nix` with libssh2, lz4, zstd, dmabuf
  - [x] wrap-ffmpeg stubbed (video disabled)
  - [x] `nix build .#waypipe-ios`
- [ ] Phase 3: Integrate with wawona (follow-up; cannot link both staticlibs)
- [ ] Phase 4: libssh2 transport — add ssh2 crate, update Cargo.lock.patched, implement transport_ssh2.rs (see docs/2026-waypipe-ios-full-plan.md)
- [ ] Phase 5: Test in iOS Simulator

---

*Last updated: 2026-02-11*
