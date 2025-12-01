#!/bin/bash

# install-atk.sh
# Unified script to build ATK for macOS (native) or iOS Simulator

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
ATK_DIR="${ROOT_DIR}/dependencies/atk"

if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${ATK_DIR}/build-ios"
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    CROSS_FILE="${ROOT_DIR}/dependencies/wayland/cross-ios.txt"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig"
    MESON_EXTRA_ARGS=("--cross-file" "${CROSS_FILE}")
elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${ATK_DIR}/build-macos"
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"
    MESON_EXTRA_ARGS=()
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${ATK_DIR}" ]; then
    echo "Error: atk not found"
    exit 1
fi

cd "${ATK_DIR}"

echo "Configuring ATK..."
rm -rf "${BUILD_DIR}"

meson setup "${BUILD_DIR}" \
    --prefix="${INSTALL_DIR}" \
    --default-library=static \
    -Ddocs=false \
    -Dintrospection=false \
    "${MESON_EXTRA_ARGS[@]}"

echo "Building ATK..."
ninja -C "${BUILD_DIR}"

echo "Installing ATK..."
ninja -C "${BUILD_DIR}" install

echo "Success! ATK installed to ${INSTALL_DIR}"
