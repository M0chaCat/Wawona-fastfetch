#!/bin/bash

# install-zstd.sh
# Unified script to build zstd for macOS (native) or iOS Simulator

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
ZSTD_DIR="${ROOT_DIR}/dependencies/zstd"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    export CC="xcrun -sdk iphonesimulator clang"
    export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -Wall -Wextra -Wpedantic -Werror -Wno-sign-conversion -Wno-conversion -Wno-switch-default -Wno-switch-enum -Wno-missing-prototypes -fPIC -std=c17"
    export LDFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"
    
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    # Standard macOS flags
    export CFLAGS="-Wall -Wextra -Wpedantic -Werror -fPIC"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${ZSTD_DIR}" ]; then
    echo "Cloning zstd..."
    git clone https://github.com/facebook/zstd.git "${ZSTD_DIR}"
fi

echo "Building zstd..."
cd "${ZSTD_DIR}"
make clean || true

make -j$(sysctl -n hw.ncpu) lib

echo "Installing zstd..."
make install PREFIX="${INSTALL_DIR}"

# Remove shared libraries (iOS doesn't support dylibs easily, want static)
rm -f "${INSTALL_DIR}/lib/"*.dylib

# Fix pkg-config file to use correct prefix
if [ -f "${INSTALL_DIR}/lib/pkgconfig/libzstd.pc" ]; then
    sed -i.bak "s|^prefix=.*|prefix=${INSTALL_DIR}|" "${INSTALL_DIR}/lib/pkgconfig/libzstd.pc"
    rm -f "${INSTALL_DIR}/lib/pkgconfig/libzstd.pc.bak"
fi

echo "Success! zstd installed to ${INSTALL_DIR}"

if [ "${PLATFORM}" == "ios" ]; then
    echo "Creating Zstd framework for ios..."
    "${ROOT_DIR}/scripts/create-static-framework.sh" \
        --platform "${PLATFORM}" \
        --name "Zstd" \
        --libs "libzstd.a" \
        --include-subdir "" \
        --recursive-headers
        
    echo "Success! Zstd framework created at ${INSTALL_DIR}/Frameworks/Zstd.framework"
fi
