# iOS Static Graphics Drivers

> **Requirement:** On iOS, all graphics drivers must be bundled as **static libraries** (`.a`). Dynamic libraries (`.dylib`) are not allowed.

## Drivers

| Driver | Purpose | Nix/Dep |
|--------|---------|---------|
| KosmicKrisp | Vulkan over Metal | `dependencies/libs/kosmickrisp/ios.nix` |
| MoltenVK | Vulkan over Metal | Add `dependencies/libs/moltenvk/ios.nix` |
| ANGLE | OpenGL ES over Metal | Add `dependencies/libs/angle/ios.nix` |

## Build Strategy

1. **KosmicKrisp:** Mesa with `-Dvulkan-drivers=kosmickrisp -Dplatforms=darwin`; build static `libvulkan_kosmickrisp.a`.
2. **MoltenVK:** Khronos MoltenVK; build static target (check MoltenVK docs for `MOLTENVK_BUILD_STATIC` or similar).
3. **ANGLE:** GN build with `is_component_build=false` and static linkage; produce `libangle.a`.

## Integration

- Link exactly one Vulkan implementation at build time (KosmicKrisp or MoltenVK).
- `WWNSettings_GetVulkanDriver()` returns user preference; if it doesn't match the linked driver, log a warning and use the linked driver.
- For runtime switching, we would need separate app variants (e.g. Wawona-MoltenVK, Wawona-KosmicKrisp) until a viable static multi-driver approach exists.
