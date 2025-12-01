#!/bin/bash

# install-pcre2.sh
# Unified script to build PCRE2 for macOS (native) or iOS Simulator

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
PCRE2_DIR="${ROOT_DIR}/dependencies/pcre2"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    export CC="xcrun -sdk iphonesimulator clang"
    export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fPIC"
    export AR="xcrun -sdk iphonesimulator ar"
    export RANLIB="xcrun -sdk iphonesimulator ranlib"
    
    CONFIGURE_ARGS=(
        "--host=aarch64-apple-darwin"
        "--disable-jit"
    )
    BUILD_DIR="${PCRE2_DIR}/build-ios"
    
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    export CFLAGS="-fPIC"
    CONFIGURE_ARGS=()
    BUILD_DIR="${PCRE2_DIR}/build-macos"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${PCRE2_DIR}" ]; then
    echo "Cloning pcre2..."
    git clone https://github.com/PCRE2Project/pcre2.git "${PCRE2_DIR}"
fi

cd "${PCRE2_DIR}"

# Generate configure if needed
if [ ! -f "configure" ]; then
    echo "Generating configure script..."
    if [ -f "autogen.sh" ]; then
        ./autogen.sh >/dev/null 2>&1 || true
    elif [ -f "configure.ac" ] || [ -f "configure.in" ]; then
        autoreconf -fi >/dev/null 2>&1 || true
    fi
fi

echo "Configuring PCRE2..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

../configure \
    --prefix="${INSTALL_DIR}" \
    --enable-static \
    --disable-shared \
    "${CONFIGURE_ARGS[@]}"

echo "Building PCRE2..."
make -j$(sysctl -n hw.ncpu)

echo "Installing PCRE2..."
make install

echo "Success! PCRE2 installed to ${INSTALL_DIR}"
