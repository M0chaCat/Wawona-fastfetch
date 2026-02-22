#!/usr/bin/env bash
# Build Vulkan CTS (Khronos Conformance Test Suite) for Wawona validation
# Usage: ./scripts/build-vulkan-cts.sh [macos|ios|android]
# Requires: Vulkan SDK (for macOS), NDK (for Android), Xcode (for iOS)

set -e
PLATFORM="${1:-macos}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${BUILD_DIR:-$SCRIPT_DIR/../build/vulkan-cts}"
SRC_DIR="${SRC_DIR:-$BUILD_DIR/src}"

echo "Building Vulkan CTS for $PLATFORM..."

case "$PLATFORM" in
  macos)
    # Requires Vulkan SDK with MoltenVK
    if [ -z "$VULKAN_SDK" ]; then
      echo "Set VULKAN_SDK to your LunarG Vulkan SDK path"
      exit 1
    fi
    mkdir -p "$BUILD_DIR"
    if [ ! -d "$SRC_DIR" ]; then
      git clone --depth 1 https://github.com/KhronosGroup/VK-GL-CTS.git "$SRC_DIR"
    fi
    cd "$SRC_DIR"
    python3 external/fetch_sources.py
    mkdir -p build && cd build
    cmake -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_INSTALL_PREFIX="$BUILD_DIR/install" \
      ..
    ninja
    echo "Vulkan CTS built. Run: $BUILD_DIR/install/external/vulkancts/modules/vulkan/deqp-vk"
    ;;
  android)
    echo "Android build: use NDK and pass -DANDROID_ABI=arm64-v8a etc."
    echo "See: https://github.com/KhronosGroup/VK-GL-CTS#android"
    exit 1
    ;;
  ios)
    echo "iOS build: requires cross-compilation with MoltenVK/KosmicKrisp static libs"
    echo "See docs/2026-GPU-Drivers.md and plan for static linkage"
    exit 1
    ;;
  *)
    echo "Usage: $0 [macos|ios|android]"
    exit 1
    ;;
esac
