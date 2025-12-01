#!/bin/bash

# install-zlib.sh
# Unified script to build zlib for macOS (native) or iOS Simulator

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
ZLIB_DIR="${ROOT_DIR}/dependencies/zlib"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    export CC="xcrun -sdk iphonesimulator clang"
    export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fPIC"
    export AR="xcrun -sdk iphonesimulator ar"
    export RANLIB="xcrun -sdk iphonesimulator ranlib"
    
    BUILD_DIR="${ZLIB_DIR}/build-ios"
    
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    export CFLAGS="-fPIC"
    BUILD_DIR="${ZLIB_DIR}/build-macos"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${ZLIB_DIR}" ]; then
    echo "Cloning zlib..."
    git clone https://github.com/madler/zlib.git "${ZLIB_DIR}"
fi

cd "${ZLIB_DIR}"

echo "Configuring zlib..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

../configure --prefix="${INSTALL_DIR}" --static

echo "Building zlib..."
make -j$(sysctl -n hw.ncpu)

echo "Installing zlib..."
make install

echo "Success! zlib installed to ${INSTALL_DIR}"
