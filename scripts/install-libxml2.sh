#!/bin/bash

# install-libxml2.sh
# Unified script to build libxml2 for macOS (native) or iOS Simulator

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
LIBXML2_DIR="${ROOT_DIR}/dependencies/libxml2"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    export CC="xcrun -sdk iphonesimulator clang"
    export CXX="xcrun -sdk iphonesimulator clang++"
    export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -Wall -Wextra -Wpedantic -Wno-error -fPIC"
    export CXXFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"
    
    CONFIGURE_ARGS=(
        "--host=arm64-apple-darwin"
    )
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    export CFLAGS="-Wall -Wextra -Wpedantic -Wno-error -fPIC"
    CONFIGURE_ARGS=()
elif [ "${PLATFORM}" == "host" ]; then
    INSTALL_DIR="${ROOT_DIR}/build/ios-bootstrap"
    export CFLAGS="-Wall -Wextra -Wpedantic -Wno-error -fPIC"
    CONFIGURE_ARGS=()
    BUILD_DIR="${LIBXML2_DIR}/build-host"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${LIBXML2_DIR}" ]; then
    echo "Cloning libxml2..."
    git clone https://gitlab.gnome.org/GNOME/libxml2.git "${LIBXML2_DIR}"
fi

cd "${LIBXML2_DIR}"

# Checkout stable
echo "Checking out stable version..."
git fetch --tags
git checkout v2.13.7 || git checkout $(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)

# Configure
echo "Configuring libxml2..."
if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${LIBXML2_DIR}/build-ios"
elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${LIBXML2_DIR}/build-macos"
elif [ "${PLATFORM}" == "host" ]; then
    BUILD_DIR="${LIBXML2_DIR}/build-host"
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Autogen if needed (run from source dir)
# Note: libxml2 build process is finicky about where autogen runs
if [ ! -f "${LIBXML2_DIR}/configure" ]; then
    (cd "${LIBXML2_DIR}" && ./autogen.sh)
fi

# Configure
"${LIBXML2_DIR}/configure" \
    --prefix="${INSTALL_DIR}" \
    --enable-static \
    --disable-shared \
    --without-python \
    --without-lzma \
    --without-zlib \
    "${CONFIGURE_ARGS[@]}"

echo "Building libxml2..."
make -j$(sysctl -n hw.ncpu)

echo "Installing libxml2..."
make install

echo "Success! libxml2 installed to ${INSTALL_DIR}"

if [ "${PLATFORM}" == "ios" ]; then
    echo "Creating Libxml2 framework for ios..."
    "${ROOT_DIR}/scripts/create-static-framework.sh" \
        --platform "${PLATFORM}" \
        --name "Libxml2" \
        --libs "libxml2.a" \
        --include-subdir "" \
        --recursive-headers
        
    echo "Success! Libxml2 framework created at ${INSTALL_DIR}/Frameworks/Libxml2.framework"
fi
