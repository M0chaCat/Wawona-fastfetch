#!/bin/bash

# install-libpng.sh
# Unified script to build libpng for macOS (native) or iOS Simulator

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
LIBPNG_DIR="${ROOT_DIR}/dependencies/libpng"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    export CC="xcrun -sdk iphonesimulator clang"
    export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fPIC"
    export AR="xcrun -sdk iphonesimulator ar"
    export RANLIB="xcrun -sdk iphonesimulator ranlib"
    
    CONFIGURE_ARGS=("--host=aarch64-apple-darwin")
    BUILD_DIR="${LIBPNG_DIR}/build-ios"
    
    # Use iOS-specific PKG_CONFIG_PATH pointing to ios-bootstrap for native tools
    export PKG_CONFIG_PATH="${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig"
    
    elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    export CFLAGS="-fPIC"
    CONFIGURE_ARGS=()
    BUILD_DIR="${LIBPNG_DIR}/build-macos"
    
    # Use macOS-specific PKG_CONFIG_PATH
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${LIBPNG_DIR}" ]; then
    echo "Cloning libpng..."
    git clone https://github.com/glennrp/libpng.git "${LIBPNG_DIR}"
fi

cd "${LIBPNG_DIR}"

# Generate configure if needed
if [ ! -f "configure" ]; then
    echo "Generating configure script..."
    if [ -f "autogen.sh" ]; then
        ./autogen.sh >/dev/null 2>&1 || true
    elif [ -f "configure.ac" ] || [ -f "configure.in" ]; then
        autoreconf -fi >/dev/null 2>&1 || true
    fi
fi

echo "Configuring libpng..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

../configure \
    --prefix="${INSTALL_DIR}" \
    --enable-static \
    --disable-shared \
    "${CONFIGURE_ARGS[@]}"

echo "Building libpng..."
make -j$(sysctl -n hw.ncpu)

echo "Installing libpng..."
make install

echo "Success! libpng installed to ${INSTALL_DIR}"
