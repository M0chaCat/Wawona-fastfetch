#!/bin/bash

# install-wayland-protocols.sh
# Unified script to build wayland-protocols for macOS (native) or iOS Simulator

set -e
set -o pipefail

# Default to native build if no platform specified
PLATFORM="macos"

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform) PLATFORM="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

echo "Target Platform: ${PLATFORM}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAYLAND_PROTOCOLS_DIR="${ROOT_DIR}/dependencies/wayland-protocols"

if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${WAYLAND_PROTOCOLS_DIR}/build-ios"
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    CROSS_FILE="${ROOT_DIR}/dependencies/wayland/cross-ios.txt"
    MESON_EXTRA_ARGS=("--cross-file" "${CROSS_FILE}")
    export PKG_CONFIG_PATH="${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig"
elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${WAYLAND_PROTOCOLS_DIR}/build-macos"
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    MESON_EXTRA_ARGS=()
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${WAYLAND_PROTOCOLS_DIR}" ]; then
    echo "Error: wayland-protocols not found"
    exit 1
fi

cd "${WAYLAND_PROTOCOLS_DIR}"
rm -rf "${BUILD_DIR}"

echo "Configuring wayland-protocols..."
meson setup "${BUILD_DIR}" \
    --prefix="${INSTALL_DIR}" \
    -Dtests=false \
    "${MESON_EXTRA_ARGS[@]}"

echo "Building..."
ninja -C "${BUILD_DIR}"

echo "Installing..."
ninja -C "${BUILD_DIR}" install

echo "Success! wayland-protocols installed to ${INSTALL_DIR}"
