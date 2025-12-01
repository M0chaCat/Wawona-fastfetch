#!/bin/bash

# install-lz4.sh
# Unified script to build lz4 for macOS (native) or iOS Simulator

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
LZ4_DIR="${ROOT_DIR}/dependencies/lz4"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    export CC="xcrun -sdk iphonesimulator clang"
    export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -Wall -Wextra -Wpedantic -Werror -Wno-sign-conversion -Wno-conversion -Wno-switch-default -Wno-switch-enum -Wno-missing-prototypes -fPIC -std=c17"
    export LDFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"
    
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    export CFLAGS="-Wall -Wextra -Wpedantic -Werror -fPIC"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${LZ4_DIR}" ]; then
    echo "Cloning lz4..."
    git clone https://github.com/lz4/lz4.git "${LZ4_DIR}"
fi

echo "Building lz4..."
cd "${LZ4_DIR}"
make clean || true

make -j$(sysctl -n hw.ncpu) liblz4.a

echo "Installing lz4..."
make install PREFIX="${INSTALL_DIR}" BUILD_SHARED=no

echo "Success! lz4 installed to ${INSTALL_DIR}"

if [ "${PLATFORM}" == "ios" ]; then
    echo "Creating Lz4 framework for ios..."
    "${ROOT_DIR}/scripts/create-static-framework.sh" \
        --platform "${PLATFORM}" \
        --name "Lz4" \
        --libs "liblz4.a" \
        --include-subdir "" \
        --recursive-headers
        
    echo "Success! Lz4 framework created at ${INSTALL_DIR}/Frameworks/Lz4.framework"
fi
