#!/bin/bash

# install-expat.sh
# Unified script to build expat for macOS (native) or iOS Simulator

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
EXPAT_DIR="${ROOT_DIR}/dependencies/expat"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    export CC="xcrun -sdk iphonesimulator clang"
    export CXX="xcrun -sdk iphonesimulator clang++"
    export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -Wall -Wextra -Wpedantic -Wno-error -fPIC"
    export CXXFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"
    export LDFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"
    
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
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${EXPAT_DIR}" ]; then
    echo "Cloning expat..."
    git clone https://github.com/libexpat/libexpat.git "${EXPAT_DIR}"
fi

cd "${EXPAT_DIR}"

# Checkout stable
echo "Checking out stable version..."
git fetch --tags
git checkout R_2_6_3 || git checkout $(git tag | grep -E '^R_[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)

# expat source in subdir
if [ -d "expat" ]; then
    SOURCE_DIR="${EXPAT_DIR}/expat"
else
    SOURCE_DIR="${EXPAT_DIR}"
fi

cd "${SOURCE_DIR}"

# Buildconf if needed
if [ ! -f "configure" ]; then
    echo "Running buildconf..."
    if [ -f "buildconf.sh" ]; then ./buildconf.sh
    elif [ -f "../buildconf.sh" ]; then cd .. && ./buildconf.sh && cd "${SOURCE_DIR}"
    elif [ -f "autogen.sh" ]; then ./autogen.sh
    elif [ -f "configure.ac" ]; then autoreconf -fi
    fi
fi

# Clean any in-tree build artifacts to prevent conflicts
if [ -f "Makefile" ]; then
    echo "Cleaning previous in-tree build artifacts..."
    make distclean || true
fi

# Setup out-of-tree build
BUILD_DIR="${EXPAT_DIR}/build-${PLATFORM}"
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Configure
echo "Configuring expat..."
"${SOURCE_DIR}/configure" \
    --prefix="${INSTALL_DIR}" \
    --enable-static \
    --disable-shared \
    --without-docbook \
    --without-examples \
    --without-tests \
    "${CONFIGURE_ARGS[@]}"

echo "Building expat..."
make -j$(sysctl -n hw.ncpu)

echo "Installing expat..."
make install

echo "Success! expat installed to ${INSTALL_DIR}"

if [ "${PLATFORM}" == "ios" ]; then
    echo "Creating Expat framework for ios..."
    "${ROOT_DIR}/scripts/create-static-framework.sh" \
        --platform "${PLATFORM}" \
        --name "Expat" \
        --libs "libexpat.a" \
        --include-subdir "" \
        --recursive-headers
        
    echo "Success! Expat framework created at ${INSTALL_DIR}/Frameworks/Expat.framework"
fi
