# Nix Build System Conversion

## Summary

This document describes the conversion of Wawona from CMakeLists.txt to a pure Nix build system.

## Changes Made

### 1. macOS Dependency Changes Analysis

The git diff shows that macOS dependencies were changed to:
- **Removed**: `apple-sdk_26` package dependency
- **Added**: Xcode auto-detection using `xcode-wrapper.nix`
- **Changed**: Deployment targets (some from 26.0 to 13.0, some still 26.0)
- **Improved**: Better handling of autotools packages with proper configure/build/install phases
- **Fixed**: libwayland macOS compatibility (epoll-shim integration, socket defines)

**Reason**: The `apple-sdk_26` package was likely causing compatibility issues or wasn't available. Using Xcode auto-detection provides better compatibility with the user's actual Xcode installation.

### 2. Pure Nix Build System (`dependencies/wawona.nix`)

Created a comprehensive Nix build system that replaces CMakeLists.txt:

#### Features:
- **Version reading**: Reads version from VERSION file
- **Source file management**: Lists all source files from CMakeLists.txt
- **Platform-specific builds**: Separate derivations for macOS, iOS, Android
- **Metal shader compilation**: Compiles Metal shaders to .metallib
- **App bundle creation**: Creates proper iOS/macOS app bundles with Info.plist
- **Dependency handling**: Properly links all dependencies via pkg-config
- **Framework linking**: Links Apple frameworks (Cocoa, Metal, etc.)
- **libgbm wrapper**: Builds libgbm wrapper library

#### Build Process:
1. **preConfigure**: Sets up Xcode environment, copies dependencies
2. **preBuild**: Compiles Metal shaders
3. **buildPhase**: 
   - Compiles libgbm wrapper
   - Compiles all source files (.c and .m)
   - Links executable with all frameworks and libraries
4. **installPhase**: Creates app bundle, copies resources, generates Info.plist

### 3. Dependency Compilation Status

All dependencies should compile for iOS, Android, macOS. The build system uses:
- `buildModule.buildForMacOS` / `buildForIOS` / `buildForAndroid` for platform-specific builds
- `pkgs.pixman` for pixman (from nixpkgs)
- `pkgs.vulkan-headers` / `pkgs.vulkan-loader` for Vulkan support

## Current Status

✅ **Completed**:
- Converted CMakeLists.txt logic to Nix
- Created platform-specific builds (macos, ios, android)
- Metal shader compilation
- App bundle creation
- Info.plist generation
- Dependency setup

⚠️ **Needs Testing**:
- Full build of wawona-macos
- Full build of wawona-ios  
- Full build of wawona-android
- Verify all dependencies compile correctly

## Next Steps

1. **Test dependency builds**:
   ```bash
   nix build '.#libwayland-macos'
   nix build '.#libwayland-ios'
   nix build '.#libwayland-android'
   # Test other dependencies...
   ```

2. **Test Wawona builds**:
   ```bash
   nix build '.#wawona-macos'
   nix build '.#wawona-ios'
   nix build '.#wawona-android'
   ```

3. **Refine build if needed**:
   - Fix any compilation errors
   - Improve error handling in build scripts
   - Optimize build process

4. **Remove CMakeLists.txt** (once Nix build is verified):
   - Can be kept as reference initially
   - Remove once Nix build is fully working

## Known Issues / Limitations

1. **Manual compilation**: The current approach compiles files manually in a loop, which:
   - Doesn't handle file dependencies automatically
   - May have ordering issues
   - Error handling could be improved

2. **Build complexity**: Building a complex C/Objective-C project without CMake is challenging. Consider:
   - Using a generated Makefile
   - Using a build script with better dependency tracking
   - Keeping minimal CMake for complex parts (if needed)

3. **Path handling**: Need to ensure all paths are correctly resolved in build phases

## Files Modified

- `dependencies/wawona.nix` - Complete rewrite to pure Nix build system
- `dependencies/deps/*/macos.nix` - Updated to use Xcode auto-detection (already done)

## Files to Remove (after verification)

- `CMakeLists.txt` - No longer needed once Nix build is verified
