# Graphics Driver Settings Design

> **Key names and value formats** for Wawona Settings > Graphics > Drivers (Phase 1).

## Settings Keys

| Platform | Key | Type | Default | Description |
|----------|-----|------|---------|-------------|
| All | `VulkanDriver` | string | platform-specific | Vulkan driver selection |
| All | `OpenGLDriver` | string | platform-specific | OpenGL/GLES driver selection |

## Value Formats

### Vulkan Driver (`VulkanDriver` / `vulkanDriver`)

| Platform | Values | Default |
|----------|--------|---------|
| **Android** | `none`, `swiftshader`, `turnip`, `system` | `system` |
| **macOS** | `none`, `moltenvk`, `kosmickrisp` | `moltenvk` |
| **iOS** | `none`, `moltenvk`, `kosmickrisp` | `moltenvk` |

### OpenGL Driver (`OpenGLDriver` / `openglDriver`)

| Platform | Values | Default |
|----------|--------|---------|
| **Android** | `none`, `angle`, `system` | `system` |
| **macOS** | `none`, `angle`, `moltengl` | `angle` |
| **iOS** | `none`, `angle` | `angle` |

## Platform-Specific Keys

- **iOS / macOS (NSUserDefaults):** `VulkanDriver`, `OpenGLDriver`
- **Android (SharedPreferences):** `vulkanDriver`, `openglDriver`

## Backward Compatibility

- `VulkanDriversEnabled` (bool): If `VulkanDriver` is unset and `VulkanDriversEnabled` is `false`, treat as `VulkanDriver = "none"`. If `true`, use platform default.
- Migration: On first read of new keys, migrate from `VulkanDriversEnabled` → `VulkanDriver` (`none` or default).
