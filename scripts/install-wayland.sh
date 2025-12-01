#!/bin/bash

# install-wayland.sh
# Unified script to build Wayland for macOS (native) or iOS Simulator

set -e
set -o pipefail

# Default to native build if no platform specified
PLATFORM="macos"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

echo "Target Platform: ${PLATFORM}"

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAYLAND_DIR="${ROOT_DIR}/dependencies/wayland"

# Platform-specific settings
if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${WAYLAND_DIR}/build-ios"
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    CROSS_FILE="${WAYLAND_DIR}/cross-ios.txt"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    # Generate cross file if needed
    "${ROOT_DIR}/scripts/generate-cross-ios.sh"
    
    # Native build tools path (for wayland-scanner)
    HOST_TOOLS_DIR="${ROOT_DIR}/build/ios-bootstrap"
    
    # Force pkg-config to look in ios-install AND ios-bootstrap
    # ios-install first for target libs. wayland-scanner.pc in ios-install is patched to point to host binary.
    export PKG_CONFIG_LIBDIR="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:${INSTALL_DIR}/share/pkgconfig:${HOST_TOOLS_DIR}/lib/pkgconfig:${HOST_TOOLS_DIR}/share/pkgconfig"
    unset PKG_CONFIG_PATH
    
    # Enable finding native tools in ios-bootstrap
    # export PKG_CONFIG_PATH="${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig"
    
    # Extra Meson options for iOS
    MESON_EXTRA_ARGS=(
        "--cross-file" "${CROSS_FILE}"
        "-Dscanner=true" # Enable scanner build for iOS (ported)
    )
    
    # Ensure native wayland-scanner exists
    if [ ! -f "${HOST_TOOLS_DIR}/bin/wayland-scanner" ]; then
        echo "Native wayland-scanner not found. Checking native dependencies..."

        # Build native expat if missing
        if [ ! -f "${HOST_TOOLS_DIR}/lib/pkgconfig/expat.pc" ]; then
            echo "Building native expat..."
            "${ROOT_DIR}/scripts/install-expat.sh" --platform host
        fi

        # Build native libxml2 if missing
        if [ ! -f "${HOST_TOOLS_DIR}/lib/pkgconfig/libxml-2.0.pc" ]; then
            echo "Building native libxml2..."
            "${ROOT_DIR}/scripts/install-libxml2.sh" --platform host
        fi

        echo "Building native wayland-scanner first..."
        # Run in subshell with unset PKG_CONFIG_PATH to avoid picking up iOS libs
        (
            unset PKG_CONFIG_PATH
            export PKG_CONFIG_LIBDIR=""
            "${ROOT_DIR}/scripts/install-wayland-scanner-only.sh"
        )
    fi
    export PATH="${HOST_TOOLS_DIR}/bin:${PATH}"
    
elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${WAYLAND_DIR}/build-macos"
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    
    # Use macOS-specific PKG_CONFIG_PATH (local only, no homebrew)
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"
    
    # Extra Meson options for macOS
    MESON_EXTRA_ARGS=(
        "-Dscanner=true"
        "-Ddefault_library=static"
    )
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

# Create install directory
mkdir -p "${INSTALL_DIR}"

# Check source
if [ ! -d "${WAYLAND_DIR}" ]; then
    echo "Cloning Wayland..."
    git clone https://gitlab.freedesktop.org/wayland/wayland.git "${WAYLAND_DIR}"
fi

cd "${WAYLAND_DIR}"

# Checkout stable version (only if not already on a specific version)
if [ -z "$(git describe --tags --exact-match HEAD 2>/dev/null)" ]; then
    echo "Checking out stable version..."
    git fetch --tags
    git checkout 1.24.0 || git checkout $(git tag | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
fi

# Configure
echo "Configuring Wayland for ${PLATFORM}..."
rm -rf "${BUILD_DIR}"

meson setup "${BUILD_DIR}" \
    --prefix "${INSTALL_DIR}" \
    -Ddocumentation=false \
    -Dtests=false \
    -Dlibraries=true \
    -Dwerror=false \
    "${MESON_EXTRA_ARGS[@]}"

# Build
echo "Building Wayland..."
meson compile -C "${BUILD_DIR}"

# Install
echo "Installing Wayland..."
meson install -C "${BUILD_DIR}"

if [ "${PLATFORM}" == "ios" ]; then
    # Patch wayland-scanner.pc to point to host scanner
    echo "Patching wayland-scanner.pc for cross-compilation..."
    PC_FILE="${INSTALL_DIR}/lib/pkgconfig/wayland-scanner.pc"
    if [ -f "${PC_FILE}" ]; then
        sed -i.bak "s|wayland_scanner=.*|wayland_scanner=${HOST_TOOLS_DIR}/bin/wayland-scanner|" "${PC_FILE}"
        rm "${PC_FILE}.bak"
    fi
fi

echo "Success! Wayland installed to ${INSTALL_DIR}"

# Create framework (Platform specific)
echo "Creating Wayland framework for ${PLATFORM}..."
"${ROOT_DIR}/scripts/create-wayland-framework.sh" --platform "${PLATFORM}"
