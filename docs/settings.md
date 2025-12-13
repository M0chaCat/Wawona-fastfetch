# Wawona Settings Documentation

This document describes all available settings in Wawona across Android, iOS, and macOS platforms.

## Accessing Settings

- **Android**: Open the Wawona app and tap the settings icon to access the settings dialog
- **iOS**: Open the iOS Settings app and navigate to "Wawona"
- **macOS**: Open System Settings (or System Preferences on older macOS) and navigate to "Wawona"

## Settings Overview

Settings are organized into the following sections:
- **Display & Rendering**: Visual and scaling options
- **Input & Interaction**: Keyboard and input behavior
- **Advanced Features**: Advanced compositor features
- **Waypipe Configuration**: Remote display and network options

---

## Display & Rendering

### Force Server-Side Decorations
- **Platforms**: macOS only
- **Default**: Enabled (`true`)
- **Description**: When enabled, all Wayland clients use macOS-style window decorations (titlebar, borders, controls) to integrate better with macOS. When disabled, clients can draw their own decorations (client-side decorations).
- **Key**: `ForceServerSideDecorations`

### Show macOS Cursor
- **Platforms**: macOS only
- **Default**: Disabled (`false`)
- **Description**: When enabled, shows the macOS cursor when the app is focused. When disabled, hides the cursor for a cleaner Wayland experience.
- **Key**: `RenderMacOSPointer`

### Auto Scale
- **Platforms**: Android, iOS, macOS
- **Default**: Enabled (`true`) on all platforms
- **Description**: Automatically detects and matches the platform's UI scaling to ensure proper display scaling.
  - **Android**: Detects and matches Android UI Scaling
  - **iOS**: Detects and matches iOS UI Scaling
  - **macOS**: Detects and matches macOS UI Scaling
- **Key**: `AutoScale`
- **Legacy Key**: `AutoRetinaScaling` (automatically migrated)

### Respect Safe Area
- **Platforms**: Android, iOS only
- **Default**: Enabled (`true`)
- **Description**: Respects the device's safe area insets to avoid system UI elements (notches, status bars, navigation bars). When disabled, content extends to the full screen.
- **Key**: `RespectSafeArea`

---

## Input & Interaction

### Swap CMD with ALT
- **Platforms**: iOS, macOS only
- **Default**: Enabled (`true`)
- **Description**: Swaps the Command (⌘) and Alt/Option (⌥) modifier keys for better compatibility with Linux/Unix keyboard layouts.
- **Key**: `SwapCmdWithAlt`
- **Legacy Key**: `SwapCmdAsCtrl` (automatically migrated)

### Universal Clipboard
- **Platforms**: Android, iOS, macOS
- **Default**: Enabled (`true`) on all platforms
- **Description**: Enables clipboard synchronization between the host system and Wayland clients, allowing copy/paste operations to work seamlessly.
- **Key**: `UniversalClipboard`

---

## Advanced Features

### Color Operations
- **Platforms**: Android, iOS, macOS
- **Default**: Enabled (`true`) on all platforms
- **Description**: Enables color profile support, HDR requests, and advanced color management features for Wayland clients.
- **Key**: `ColorOperations`
- **Legacy Key**: `ColorSyncSupport` (automatically migrated)

### Nested Compositors
- **Platforms**: Android, iOS, macOS
- **Default**: Enabled (`true`) on all platforms
- **Description**: Enables support for nested Wayland compositors, allowing full desktop environments (like Weston, KDE Plasma, GNOME Mutter) to run under Wawona.
- **Key**: `NestedCompositorsSupport`

### Multiple Clients
- **Platforms**: Android, iOS, macOS
- **Default**: 
  - **Android**: Disabled (`false`)
  - **iOS**: Disabled (`false`)
  - **macOS**: Enabled (`true`)
- **Description**: Allows multiple Wayland clients to connect simultaneously. When disabled, only one client connection is allowed at a time.
- **Key**: `MultipleClients`

---

## Waypipe Configuration

Waypipe is a transparent proxy for Wayland applications that enables remote display over SSH or network connections.

### Local IP Address
- **Platforms**: Android, iOS, macOS
- **Type**: Display only (read-only)
- **Description**: Shows the current local IP address of the device, useful for SSH connections from remote machines.
- **Note**: Only visible in Android settings dialog. On iOS/macOS, check your network settings.

### Wayland Display
- **Platforms**: Android, iOS, macOS
- **Default**: `wayland-0`
- **Description**: The Wayland display socket name (e.g., `wayland-0`, `wayland-1`). This determines which display socket Wayland clients connect to.
- **Key**: `WaypipeDisplay`
- **Behavior**: If cleared, automatically reverts to `wayland-0`

### Socket Path
- **Platforms**: Android, iOS, macOS
- **Type**: Read-only (informational)
- **Description**: The Unix socket path used by Waypipe. This is automatically set by the platform:
  - **Android**: `${cacheDir}/waypipe` (sandboxed)
  - **iOS**: `${NSTemporaryDirectory()}/waypipe` (sandboxed)
  - **macOS**: `${NSTemporaryDirectory()}/waypipe`
- **Key**: `WaypipeSocket`
- **Note**: Cannot be modified - set automatically by the platform for security/sandboxing compliance

### Compression
- **Platforms**: Android, iOS, macOS
- **Default**: `lz4`
- **Options**: 
  - `none`: No compression (for high-bandwidth networks)
  - `lz4`: LZ4 compression (intermediate, default)
  - `zstd`: ZSTD compression (for slow connections)
- **Description**: Compression method applied to data transfers between Waypipe client and server.
- **Key**: `WaypipeCompress`

### Compression Level
- **Platforms**: Android, iOS, macOS
- **Default**: `7`
- **Description**: ZSTD compression level (1-22). Only applicable when Compression is set to `zstd`. Higher values provide better compression but use more CPU.
- **Key**: `WaypipeCompressLevel`
- **Visibility**: Only shown when Compression is set to `zstd`

### Threads
- **Platforms**: Android, iOS, macOS
- **Default**: `0` (auto-detect)
- **Description**: Number of threads to use for compression operations. Set to `0` to automatically use half of available CPU threads.
- **Key**: `WaypipeThreads`
- **Behavior**: If cleared, automatically reverts to `0`

### Video Compression
- **Platforms**: Android, iOS, macOS
- **Default**: `none`
- **Options**:
  - `none`: No video compression
  - `h264`: H.264 encoded video
  - `vp9`: VP9 encoded video
  - `av1`: AV1 encoded video
- **Description**: Compresses specific DMABUF formats using a lossy video codec. Useful for reducing bandwidth when transferring video content.
- **Key**: `WaypipeVideo`
- **Note**: Opaque, 10-bit, and multiplanar formats are not supported

### Video Encoding
- **Platforms**: Android, iOS, macOS
- **Default**: `hw` (hardware)
- **Options**:
  - `hw`: Hardware encoding
  - `sw`: Software encoding
  - `hwenc`: Hardware encoding (explicit)
  - `swenc`: Software encoding (explicit)
- **Description**: Encoding method for video compression. Only shown when Video Compression is not `none`.
- **Key**: `WaypipeVideoEncoding`
- **Visibility**: Only shown when Video Compression is not `none`

### Video Decoding
- **Platforms**: Android, iOS, macOS
- **Default**: `hw` (hardware)
- **Options**:
  - `hw`: Hardware decoding
  - `sw`: Software decoding
  - `hwdec`: Hardware decoding (explicit)
  - `swdec`: Software decoding (explicit)
- **Description**: Decoding method for video compression. Only shown when Video Compression is not `none`.
- **Key**: `WaypipeVideoDecoding`
- **Visibility**: Only shown when Video Compression is not `none`

### Bits Per Frame
- **Platforms**: Android, iOS, macOS
- **Default**: Empty (no limit)
- **Description**: Target bit rate for video encoder in bits per frame (e.g., `750000`). Only shown when Video Compression is not `none`.
- **Key**: `WaypipeVideoBpf`
- **Visibility**: Only shown when Video Compression is not `none`

---

## SSH Configuration

### Enable SSH
- **Platforms**: Android, iOS, macOS
- **Default**: Disabled (`false`)
- **Description**: Enables SSH-based Waypipe connections, allowing remote Wayland applications to be displayed locally over SSH.
- **Key**: `WaypipeSSHEnabled`

### SSH Host
- **Platforms**: Android, iOS, macOS
- **Default**: Empty
- **Description**: Remote hostname or IP address for SSH connection (e.g., `user@example.com` or `192.168.1.100`).
- **Key**: `WaypipeSSHHost`
- **Visibility**: Only shown when Enable SSH is enabled

### SSH User
- **Platforms**: Android, iOS, macOS
- **Default**: Empty
- **Description**: SSH username for remote connection.
- **Key**: `WaypipeSSHUser`
- **Visibility**: Only shown when Enable SSH is enabled

### SSH Binary Path
- **Platforms**: Android, iOS, macOS
- **Default**: `ssh`
- **Description**: Path to the SSH binary executable. Defaults to `ssh` if available in PATH.
- **Key**: `WaypipeSSHBinary`
- **Visibility**: Only shown when Enable SSH is enabled

### Remote Command
- **Platforms**: Android, iOS, macOS
- **Default**: Empty
- **Description**: Application or command to run on the remote host via Waypipe. Examples: `weston`, `weston-terminal`, `dolphin`, `firefox`. This command will be executed remotely and its Wayland output will be proxied back to Wawona for display.
- **Key**: `WaypipeRemoteCommand`
- **Visibility**: Only shown when Enable SSH is enabled
- **Note**: If Custom Script is provided, it takes precedence over Remote Command

### Custom Script
- **Platforms**: Android, iOS, macOS
- **Default**: Empty
- **Description**: Full command-line script to execute on the remote host. This allows complete control over the remote command execution, including arguments, environment variables, and complex shell commands. If provided, this overrides the Remote Command setting. Example: `env XDG_SESSION_TYPE=wayland weston --backend=drm-backend.so`.
- **Key**: `WaypipeCustomScript`
- **Visibility**: Only shown when Enable SSH is enabled
- **Note**: When Custom Script is non-empty, it takes precedence over Remote Command. Useful for running nested compositors like Weston within Wawona.

---

## Advanced Waypipe Options

### Debug Mode
- **Platforms**: Android, iOS, macOS
- **Default**: Disabled (`false`)
- **Description**: Enables debug logging for Waypipe operations. Useful for troubleshooting connection issues.
- **Key**: `WaypipeDebug`

### Disable GPU
- **Platforms**: Android, iOS, macOS
- **Default**: Disabled (`false`)
- **Description**: Blocks GPU-accelerated protocols (wayland-drm, linux-dmabuf). Forces CPU-based rendering fallback.
- **Key**: `WaypipeNoGpu`

### One Shot
- **Platforms**: Android, iOS, macOS
- **Default**: Disabled (`false`)
- **Description**: Only permits a single connection, and exits when it is closed. Useful for one-time remote sessions.
- **Key**: `WaypipeOneshot`

### Unlink Socket
- **Platforms**: Android, iOS, macOS
- **Default**: Disabled (`false`)
- **Description**: Removes the Unix socket file on shutdown. Useful for cleanup in temporary environments.
- **Key**: `WaypipeUnlinkSocket`

### Login Shell
- **Platforms**: Android, iOS, macOS
- **Default**: Disabled (`false`)
- **Description**: Opens a login shell if no command is specified when running Waypipe server.
- **Key**: `WaypipeLoginShell`

### VSock
- **Platforms**: Android, iOS, macOS
- **Default**: Disabled (`false`)
- **Description**: Uses vsock instead of Unix sockets for virtual machine communication. Useful when running Waypipe in VMs.
- **Key**: `WaypipeVsock`

### XWayland Support
- **Platforms**: Android, iOS, macOS
- **Default**: Disabled (`false`)
- **Status**: Unavailable (disabled on all platforms)
- **Description**: Would enable XWayland support using xwayland-satellite for X11 clients. Currently not available.
- **Key**: `WaypipeXwls`
- **Note**: This option is visible but disabled/unavailable on all platforms

### Title Prefix
- **Platforms**: Android, iOS, macOS
- **Default**: Empty
- **Description**: Prefix to prepend to window titles specified using the XDG shell protocol. Useful for identifying remote windows.
- **Key**: `WaypipeTitlePrefix`

### Security Context
- **Platforms**: Android, iOS, macOS
- **Default**: Empty
- **Description**: Application ID to attach to the Wayland security context protocol. Used for security isolation.
- **Key**: `WaypipeSecCtx`

---

## Settings Key Reference

All settings are stored using the following keys in their respective preference systems:

### Android (SharedPreferences)
- Keys use camelCase (e.g., `autoScale`, `respectSafeArea`, `waypipeDisplay`)

### iOS/macOS (NSUserDefaults)
- Keys use PascalCase (e.g., `AutoScale`, `RespectSafeArea`, `WaypipeDisplay`)

### Unified Keys
The following keys are unified across all platforms (with automatic case conversion):
- `AutoScale` / `autoScale`
- `ColorOperations` / `colorOperations`
- `NestedCompositorsSupport` / `nestedCompositorsSupport`
- `MultipleClients` / `multipleClients`
- All `Waypipe*` keys (including `WaypipeRemoteCommand`, `WaypipeCustomScript`)

---

## Platform-Specific Behavior

### Android
- Force Server-Side Decorations: Always enabled (not user-configurable)
- Show macOS Cursor: Always disabled (not applicable)
- Swap CMD with ALT: Always disabled (not applicable)
- Socket Path: Automatically set to `${cacheDir}/waypipe` (read-only)
- Multiple Clients: Default disabled

### iOS (iPhone/iPad)
- Force Server-Side Decorations: Not available
- Show macOS Cursor: Not available
- Respect Safe Area: Available (default enabled)
- Swap CMD with ALT: Available (default enabled)
- Socket Path: Automatically set to `${NSTemporaryDirectory()}/waypipe` (read-only)
- Multiple Clients: Default disabled

### macOS
- Force Server-Side Decorations: Available (default enabled)
- Show macOS Cursor: Available (default disabled)
- Respect Safe Area: Not available
- Swap CMD with ALT: Available (default enabled)
- Socket Path: Automatically set to `${NSTemporaryDirectory()}/waypipe` (read-only)
- Multiple Clients: Default enabled

---

## Legacy Settings Migration

The following legacy settings keys are automatically migrated to their new unified names:

- `AutoRetinaScaling` → `AutoScale`
- `ColorSyncSupport` → `ColorOperations`
- `SwapCmdAsCtrl` → `SwapCmdWithAlt`

Migration happens automatically when settings are accessed. Old keys are preserved for backward compatibility but new keys take precedence.

---

## Removed Settings

The following settings have been removed and are no longer available:

- **Use Metal 4 for Nested**: Removed (implementation detail, not user-configurable)
- **Waypipe-rs Support**: Removed (always enabled, not a toggle)
- **Enable TCP Listener**: Removed (always enabled if Waypipe is enabled)
- **Swap CMD with Ctrl**: Removed (replaced by Swap CMD with ALT)

---

## Notes

- Settings changes take effect immediately on Android (via the Apply button)
- Settings changes on iOS/macOS take effect when the app is restarted or when the compositor detects changes
- Platform-specific settings (like Socket Path) are automatically managed and cannot be modified by users
- XWayland Support is visible but disabled on all platforms - it may be enabled in future versions

