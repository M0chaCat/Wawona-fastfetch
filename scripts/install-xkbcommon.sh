#!/bin/bash

# install-xkbcommon.sh
# Unified script to build xkbcommon for macOS (native) or iOS Simulator

set -e
set -o pipefail

PLATFORM="macos"

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform) PLATFORM="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

echo "Target Platform: ${PLATFORM}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
XKBCOMMON_DIR="${ROOT_DIR}/dependencies/xkbcommon"

if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${XKBCOMMON_DIR}/build-ios"
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    CROSS_FILE="${ROOT_DIR}/dependencies/wayland/cross-ios.txt"
    MESON_EXTRA_ARGS=("--cross-file" "${CROSS_FILE}")
    
    # Force pkg-config to look in ios-install AND ios-bootstrap
    export PKG_CONFIG_LIBDIR="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:${INSTALL_DIR}/share/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig"
    unset PKG_CONFIG_PATH
    
    # Add host tools to PATH (wayland-scanner)
    export PATH="${ROOT_DIR}/build/ios-bootstrap/bin:${PATH}"
elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${XKBCOMMON_DIR}/build-macos"
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    MESON_EXTRA_ARGS=()
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:${INSTALL_DIR}/share/pkgconfig:$PKG_CONFIG_PATH"
    
    # Ensure bison is in PATH
    if [ -d "/opt/homebrew/opt/bison/bin" ]; then
        export PATH="/opt/homebrew/opt/bison/bin:${PATH}"
    fi
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${XKBCOMMON_DIR}" ]; then
    echo "Error: xkbcommon not found"
    exit 1
fi

cd "${XKBCOMMON_DIR}"
rm -rf "${BUILD_DIR}"

echo "Configuring xkbcommon..."
meson setup "${BUILD_DIR}" \
    --prefix="${INSTALL_DIR}" \
    --default-library=static \
    -Denable-x11=false \
    -Denable-wayland=true \
    -Dwerror=true \
    "${MESON_EXTRA_ARGS[@]}"

echo "Building..."
ninja -C "${BUILD_DIR}"

echo "Installing..."
ninja -C "${BUILD_DIR}" install

echo "Success! xkbcommon installed to ${INSTALL_DIR}"

if [ "${PLATFORM}" == "ios" ]; then
    echo "Creating Xkbcommon framework for ios..."
    "${ROOT_DIR}/scripts/create-static-framework.sh" \
        --platform "${PLATFORM}" \
        --name "Xkbcommon" \
        --libs "libxkbcommon.a libxkbregistry.a" \
        --include-subdir "xkbcommon" \
        --recursive-headers
        
    echo "Success! Xkbcommon framework created at ${INSTALL_DIR}/Frameworks/Xkbcommon.framework"
fi
