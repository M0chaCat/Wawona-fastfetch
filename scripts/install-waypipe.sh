#!/bin/bash

# install-waypipe.sh
# Unified script to build Waypipe for macOS (native) or iOS Simulator

set -e

PLATFORM="macos"

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform) PLATFORM="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

echo "Target Platform: ${PLATFORM}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAYPIPE_DIR="${ROOT_DIR}/dependencies/waypipe"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    mkdir -p "${INSTALL_DIR}/bin"
    
    if [ -f "$HOME/.cargo/env" ]; then source "$HOME/.cargo/env"; fi
    export PATH="$HOME/.cargo/bin:$PATH"
    
    if ! command -v rustup >/dev/null 2>&1; then
        echo "Error: rustup not found"
        exit 1
    fi
    
    echo "Installing Rust target for iOS Simulator..."
    rustup target add aarch64-apple-ios-sim
    
    # Use PKG_CONFIG_LIBDIR to replace default search paths, preventing fallback to Homebrew
    export PKG_CONFIG_LIBDIR="${ROOT_DIR}/build/ios-install/lib/pkgconfig:${ROOT_DIR}/build/ios-install/libdata/pkgconfig"
    unset PKG_CONFIG_PATH
    
    export VULKAN_SDK="${INSTALL_DIR}"
    export VK_ICD_FILENAMES="${INSTALL_DIR}/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json"
    
    export IPHONEOS_DEPLOYMENT_TARGET="15.0"
    
    export CARGO_TARGET_AARCH64_APPLE_IOS_SIM_RUSTFLAGS="-C link-arg=-isysroot -C link-arg=${SDK_PATH} -C link-arg=-mios-simulator-version-min=15.0 -L ${INSTALL_DIR}/lib -L framework=${INSTALL_DIR}/Frameworks -D warnings"
    # Alias vkGetInstanceProcAddr to vk_icdGetInstanceProcAddr for static linking without loader
    export CC="xcrun -sdk iphonesimulator clang"
    export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -Wall -Wextra -Wpedantic -Werror -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition -Wmissing-declarations -Wuninitialized -Winit-self -Wpointer-arith -Wcast-qual -Wwrite-strings -Wconversion -Wsign-conversion -Wformat=2 -Wformat-security -Wundef -Wshadow -Wstrict-overflow=5 -Wswitch-default -Wswitch-enum -Wunreachable-code -Wfloat-equal -Wstack-protector -fstack-protector-strong -fPIC -std=c17"
    export PKG_CONFIG_ALLOW_CROSS=1

    # Create wrapper to alias vkGetInstanceProcAddr to vk_icdGetInstanceProcAddr
    cat > "${INSTALL_DIR}/vk_wrapper.c" <<EOF
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>

// Forward declare the ICD entry point
VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vk_icdGetInstanceProcAddr(VkInstance instance, const char* pName);

// Prototype for export
__attribute__((visibility("default")))
VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(VkInstance instance, const char* pName);

// Define the standard entry point
__attribute__((visibility("default")))
VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(VkInstance instance, const char* pName) {
    return vk_icdGetInstanceProcAddr(instance, pName);
}
EOF

    # Compile wrapper using Mesa headers
    $CC $CFLAGS -c "${INSTALL_DIR}/vk_wrapper.c" -o "${INSTALL_DIR}/vk_wrapper.o" -I"${INSTALL_DIR}/include" -I"${ROOT_DIR}/dependencies/kosmickrisp/include"

    # Create libvk_wrapper.a
    rm -f "${INSTALL_DIR}/lib/libvk_wrapper.a"
    ar rcs "${INSTALL_DIR}/lib/libvk_wrapper.a" "${INSTALL_DIR}/vk_wrapper.o"

    # Create libvulkan.a (copy of driver)
    rm -f "${INSTALL_DIR}/lib/libvulkan.a"
    cp "${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a" "${INSTALL_DIR}/lib/libvulkan.a"
    
    # Force load libvulkan.a (driver) and link libvk_wrapper.a (entry point)
    export CARGO_TARGET_AARCH64_APPLE_IOS_SIM_RUSTFLAGS="${CARGO_TARGET_AARCH64_APPLE_IOS_SIM_RUSTFLAGS} -C link-arg=-lvk_wrapper -C link-arg=-Wl,-force_load,${INSTALL_DIR}/lib/libvulkan.a"
    
    # Allow undefined symbols (for unused WSI functions in static lib)
    export CARGO_TARGET_AARCH64_APPLE_IOS_SIM_RUSTFLAGS="${CARGO_TARGET_AARCH64_APPLE_IOS_SIM_RUSTFLAGS} -C link-arg=-Wl,-undefined,dynamic_lookup"
    
    # Link against static frameworks (Kosmickrisp is handled by libvulkan.a above)
    export CARGO_TARGET_AARCH64_APPLE_IOS_SIM_RUSTFLAGS="${CARGO_TARGET_AARCH64_APPLE_IOS_SIM_RUSTFLAGS} -C link-arg=-framework -C link-arg=Wayland -C link-arg=-framework -C link-arg=FFmpeg -C link-arg=-framework -C link-arg=EpollShim -C link-arg=-framework -C link-arg=Lz4 -C link-arg=-framework -C link-arg=Zstd -C link-arg=-framework -C link-arg=Expat -C link-arg=-framework -C link-arg=Xkbcommon -C link-arg=-framework -C link-arg=FFI"
    
    TARGET_FLAG="--target aarch64-apple-ios-sim"
    BUILD_PATH="target/aarch64-apple-ios-sim/release/waypipe"
    
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    
    if [ -f "$HOME/.cargo/env" ]; then source "$HOME/.cargo/env"; fi
    export PATH="$HOME/.cargo/bin:$PATH"
    
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:${INSTALL_DIR}/share/pkgconfig:$PKG_CONFIG_PATH"
    
    # Use local VK_ICD if available
    if [ -f "${INSTALL_DIR}/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json" ]; then
        export VK_ICD_FILENAMES="${INSTALL_DIR}/share/vulkan/icd.d/kosmickrisp_mesa_icd.aarch64.json"
    fi
    
    # Create Vulkan wrapper and static lib alias for macOS (no dynamic loader)
    echo "Preparing static Vulkan wrapper for macOS..."
    cat > "${INSTALL_DIR}/vk_wrapper.c" <<EOF
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vk_icdGetInstanceProcAddr(VkInstance instance, const char* pName);
__attribute__((visibility("default")))
VKAPI_ATTR PFN_vkVoidFunction VKAPI_CALL vkGetInstanceProcAddr(VkInstance instance, const char* pName) {
    return vk_icdGetInstanceProcAddr(instance, pName);
}
EOF
    clang -c "${INSTALL_DIR}/vk_wrapper.c" -o "${INSTALL_DIR}/vk_wrapper.o" -I"${INSTALL_DIR}/include" -fPIC -std=c17
    rm -f "${INSTALL_DIR}/lib/libvk_wrapper.a"
    ar rcs "${INSTALL_DIR}/lib/libvk_wrapper.a" "${INSTALL_DIR}/vk_wrapper.o"
    
    # Provide libvulkan.a that points to KosmicKrisp static driver
    if [ -f "${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a" ]; then
        rm -f "${INSTALL_DIR}/lib/libvulkan.a"
        cp "${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a" "${INSTALL_DIR}/lib/libvulkan.a"
    fi
    
    # Force-load static Vulkan and link wrapper if available
    export RUSTFLAGS="${RUSTFLAGS} -C link-arg=-L${INSTALL_DIR}/lib -C link-arg=-lvk_wrapper -C link-arg=-mmacosx-version-min=12.0"
    if [ -f "${INSTALL_DIR}/lib/libvulkan.a" ]; then
        export RUSTFLAGS="${RUSTFLAGS} -C link-arg=-Wl,-force_load,${INSTALL_DIR}/lib/libvulkan.a"
    fi
    
    TARGET_FLAG=""
    BUILD_PATH="target/release/waypipe"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

if [ ! -d "${WAYPIPE_DIR}" ]; then
    echo "Error: waypipe not found"
    exit 1
fi

cd "${WAYPIPE_DIR}"

# Determine features
FEATURES="dmabuf video lz4 zstd"
if [ "${PLATFORM}" == "macos" ] && [ ! -f "${INSTALL_DIR}/lib/libvulkan.a" ]; then
    echo "Vulkan driver not present; building Waypipe without dmabuf/video on macOS"
    FEATURES="lz4 zstd"
fi
# if pkg-config --exists libavcodec libavformat libavutil libswscale 2>/dev/null || \
#    [ -f "${INSTALL_DIR}/lib/libavcodec.a" ]; then
#     echo "FFmpeg libraries found - enabling video feature..."
#     FEATURES="dmabuf video lz4 zstd"
# else
#     echo "FFmpeg not found - building without video feature"
# fi

echo "Building Waypipe for ${PLATFORM}..."
cargo build \
    --release \
    ${TARGET_FLAG} \
    --no-default-features \
    --features "${FEATURES}"

echo "Installing Waypipe..."
mkdir -p "${INSTALL_DIR}/bin"
cp "${BUILD_PATH}" "${INSTALL_DIR}/bin/"

echo "Success! Waypipe installed to ${INSTALL_DIR}/bin/waypipe"
