# Waypipe iOS Full Implementation Plan

> Goal: Fully working libwaypipe.a for iOS with FFmpeg support and libssh2 transport (openssh-like behavior). Fix all linking issues.

---

## Current State

- **Built:** `libwaypipe.a` with dmabuf, lz4, zstd and with_libssh2 transport
- **Hard constraint:** App Store distributable iOS build must use static libraries only
- **Missing:** static-only video/FFmpeg integration, final app-linking validation

---

## Phase 1: Re-enable FFmpeg (video feature)

### 1.1 Dependencies
- **FFmpeg** from `buildModule.buildForIOS "ffmpeg"` — already exists in `dependencies/libs/ffmpeg/ios.nix`
- For iOS distribution, FFmpeg must produce static archives (`.a`) only

### 1.2 Changes to waypipe ios.nix

1. **Add ffmpeg to buildInputs:**
   ```nix
   ffmpeg = buildModule.buildForIOS "ffmpeg" { };
   buildInputs = [ ... ffmpeg ];
   ```

2. **Restore wrap-ffmpeg bindgen** (remove stub):
   - wrap-ffmpeg uses bindgen to generate FFmpeg bindings
   - Need: `libavutil`, `libavcodec`
   - Add ffmpeg to `LIBRARY_PATH`, `PKG_CONFIG_PATH`, `C_INCLUDE_PATH`, `BINDGEN_EXTRA_CLANG_ARGS`

3. **Re-enable video feature:**
   - Remove `#[cfg(feature = "video")]` gate on `mod video`
   - Add `"video"` to `buildFeatures` / cargo `--features`

4. **Cargo.lock:** Update `Cargo.lock.patched` if needed for new deps (bindgen, video)

### 1.3 Static-only risks
- **Wrapper mismatch:** waypipe wrap-ffmpeg currently expects dynamic-loading symbols
- **Feature gating:** video must stay disabled until wrapper compiles and links statically
- **Codec footprint:** static FFmpeg may increase `libwaypipe.a` size significantly

---

## Phase 2: libssh2 Transport (with_libssh2)

### 2.1 Waypipe's current SSH path
Upstream waypipe spawns:
```rust
Command::new("ssh")
  .args(["-W", "host:port", "user@host"])
  .stdin(Stdio::piped()).stdout(Stdio::piped())
  // ... use stdin/stdout as the link fd
```
iOS cannot spawn processes → we need an in-process libssh2 transport.

### 2.2 Implementation approach

**Option A: Add `with_libssh2` feature to waypipe Cargo.toml**

1. Add to Cargo.toml:
   ```toml
   [features]
   with_libssh2 = ["ssh2"]

   [dependencies]
   ssh2 = { version = "0.9", optional = true }
   libssh2-sys = { version = "0.3", optional = true }
   ```

2. Create `src/transport_ssh2.rs`:
   - `connect_ssh2(user: &str, host: &str, port: u16) -> Result<impl Read + Write>`
   - Use libssh2: session_init, handshake, userauth_* (password or agent), channel_open_session, exec "waypipe"
   - Return a type that impls `Read`/`Write` for the channel's stdin/stdout

3. In link/connection code, branch:
   ```rust
   #[cfg(feature = "with_libssh2")]
   if use_ssh2 { return transport_ssh2::connect(...) }
   #[cfg(not(feature = "with_libssh2"))]
   else { /* Command::new("ssh") */ }
   ```

**Option B: Fork/vendor waypipe with our patches**

- Copy waypipe into `third_party/waypipe-ios/` or equivalent
- Apply patches as Nix `patches` or in `prePatch`
- Gives full control over Cargo.toml and source

### 2.3 ssh2 crate details
- **ssh2** crate: high-level bindings to libssh2
- Requires libssh2 built with compatible crypto (mbedTLS ✅)
- PKG_CONFIG / LIBSSH2_SYS_USE_PKG_CONFIG for cross-compile

### 2.4 Nix integration
- `buildInputs`: libssh2, mbedtls (already present)
- `cargoBuildFlags`: add `--features with_libssh2`
- Ensure `LIBSSH2_SYS_USE_PKG_CONFIG=1` and `PKG_CONFIG_PATH` includes libssh2

---

## Phase 3: Fix Linking

### 3.1 Known issues
1. **Duplicate symbols:** Cannot link libwaypipe.a with libwawona.a (both embed Rust std)
2. **Missing -l flags:** Ensure all native libs are passed to linker
3. **Final app link:** ensure all static native archives are linked into app target

### 3.2 Linker flags for libwaypipe.a consumers
```
-L${waypipe}/lib -lwaypipe
-L${libwayland}/lib -lwayland-client -lffi
-L${zstd}/lib -lzstd
-L${lz4}/lib -llz4
-L${libssh2}/lib -lssh2
-L${mbedtls}/lib -lmbedtls -lmbedx509 -lmbedcrypto
-L${kosmickrisp}/lib -lvulkan_kosmickrisp  # or linked by waypipe
-L${ffmpeg}/lib  # for runtime dylib loading
-framework Foundation -framework UIKit -framework Metal ...
```

### 3.3 Static vs dynamic
- **libwaypipe.a** is static — all Rust + C deps must be statically linked
- **FFmpeg** must be static for iOS App Store distribution in this project

### 3.4 Build fixes
- **cargoBuildFlags:** Explicit `-L native=` for each dep
- **RUSTFLAGS:** Link-args for iOS SDK, sysroot
- **PKG_CONFIG_ALLOW_CROSS=1**

---

## Task Checklist

### FFmpeg (static-only)
- [x] **1.1** Add ffmpeg to waypipe ios.nix buildInputs
- [x] **1.2** Change `ffmpeg-ios` to static-only (`--disable-shared --enable-static`)
- [x] **1.3** Replace wrap-ffmpeg dynamic loader assumptions with static-link compatible bindings (symbols resolved from process image)
- [x] **1.4** Re-enable video feature after static wrapper compiles on `aarch64-apple-ios`
- [x] **1.5** Verify video module compiles with static FFmpeg on iOS device target (`nix build ".#waypipe-ios"` succeeds)

### libssh2
- [x] **2.1** Add `ssh2 = { version = "0.9", optional = true }` and `with_libssh2 = ["dep:ssh2"]` to waypipe Cargo.toml
- [x] **2.2** Update `dependencies/libs/waypipe/Cargo.lock.patched` for ssh2; add `OPENSSL_DIR` for libssh2-sys build
- [x] **2.3** Create `src/transport_ssh2.rs` stub; add `mod transport_ssh2` to main.rs when `with_libssh2`
- [x] **2.4** Build with `--features with_libssh2`, set `LIBSSH2_SYS_USE_PKG_CONFIG=1`
- [x] **2.5** Implement full transport: TCP forward_listen + exec waypipe server -s 127.0.0.1:port; added SocketSpec::Tcp

### Linking
- [x] **3.1** libwaypipe.a builds successfully
- [ ] **3.2** When video enabled: verify full static app link (no FFmpeg dylibs)

---

## Files to Modify

| File | Changes |
|------|---------|
| `dependencies/libs/waypipe/ios.nix` | ffmpeg, wrap-ffmpeg, video, with_libssh2, linker |
| `dependencies/libs/waypipe/Cargo.toml` (patched) | Add ssh2 dep, with_libssh2 feature |
| `dependencies/libs/waypipe/ios.nix` (Python script) | Cargo.toml patch for ssh2, revert video gate |
| New: `src/transport_ssh2.rs` | Applied via Nix patch from inline or file |

---

## Current Status (2026-02-11)

- **Build:** `nix build ".#waypipe-ios"` succeeds for `aarch64-apple-ios` and produces device-target `libwaypipe.a` with dmabuf, lz4, zstd, with_libssh2, video
- **Video:** Static-only FFmpeg integration compiles on iOS-device target; runtime validation in app remains
- **libssh2:** Full impl: TCP forward_listen + exec waypipe server -s 127.0.0.1:port; SocketSpec::Tcp added; wired into run_client_oneshot when with_libssh2
- **Distribution target:** static-only iOS artifacts for App Store

*Created 2026-02-11*
