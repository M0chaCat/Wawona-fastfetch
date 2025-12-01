#!/bin/bash

# install-libffi.sh
# Unified script to build libffi for macOS (native) or iOS Simulator

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
LIBFFI_DIR="${ROOT_DIR}/dependencies/libffi"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    # iOS-specific configure options
    export CC="xcrun -sdk iphonesimulator clang"
    export CFLAGS_CONFIGURE="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fno-asynchronous-unwind-tables -Wall -Wextra -Wpedantic -Wno-error -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition -Wmissing-declarations -Wuninitialized -Winit-self -Wpointer-arith -Wcast-qual -Wwrite-strings -Wconversion -Wsign-conversion -Wformat=2 -Wformat-security -Wundef -Wshadow -Wstrict-overflow=5 -Wswitch-default -Wswitch-enum -Wunreachable-code -Wfloat-equal -Wstack-protector -fstack-protector-strong -fPIC -std=c17 -Wno-deprecated-declarations"
    export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fno-asynchronous-unwind-tables -Wall -Wextra -Wpedantic -Werror -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition -Wmissing-declarations -Wuninitialized -Winit-self -Wpointer-arith -Wcast-qual -Wwrite-strings -Wconversion -Wsign-conversion -Wformat=2 -Wformat-security -Wundef -Wshadow -Wstrict-overflow=5 -Wswitch-default -Wswitch-enum -Wunreachable-code -Wfloat-equal -Wstack-protector -fstack-protector-strong -fPIC -std=c17 -Wno-deprecated-declarations"
    export LDFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -Wl,-w"
    
    CONFIGURE_ARGS=(
        "--host=aarch64-apple-darwin"
        "--disable-multi-os-directory"
    )
    
    BUILD_DIR="aarch64-apple-darwin"
    
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    
    # macOS-specific configure options
    export CFLAGS="-Wall -Wextra -Wpedantic -Werror -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition -Wmissing-declarations -Wuninitialized -Winit-self -Wpointer-arith -Wcast-qual -Wwrite-strings -Wconversion -Wsign-conversion -Wformat=2 -Wformat-security -Wundef -Wshadow -Wstrict-overflow=5 -Wswitch-default -Wswitch-enum -Wunreachable-code -Wfloat-equal -Wstack-protector -fstack-protector-strong -fPIC -std=c17 -Wno-deprecated-declarations -fexceptions"
    
    CONFIGURE_ARGS=()
    BUILD_DIR="" # Use current dir or autodetect
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${LIBFFI_DIR}" ]; then
    echo "Cloning libffi..."
    git clone https://github.com/libffi/libffi.git "${LIBFFI_DIR}"
fi

cd "${LIBFFI_DIR}"

# Ensure clean build
if [ "${PLATFORM}" == "ios" ]; then
    rm -rf aarch64-apple-darwin build-ios
fi

# Checkout stable
echo "Checking out stable version..."
git fetch --tags
git checkout v3.4.6 || git checkout $(git tag | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)

# Configure
echo "Configuring libffi..."
if [ ! -f "configure" ]; then
    ./autogen.sh
fi

# Configure
if [ "${PLATFORM}" == "ios" ]; then
    CFLAGS="${CFLAGS_CONFIGURE}" ./configure \
        --prefix="${INSTALL_DIR}" \
        --enable-static \
        --disable-shared \
        "${CONFIGURE_ARGS[@]}" >/dev/null 2>&1 || {
        echo "Configure failed, showing output:"
        CFLAGS="${CFLAGS_CONFIGURE}" ./configure \
            --prefix="${INSTALL_DIR}" \
            --enable-static \
            --disable-shared \
            "${CONFIGURE_ARGS[@]}" 2>&1 | tail -20
        exit 1
    }
    
    # iOS-specific patches
    sed -i '' 's/#define HAVE_AS_CFI_PSEUDO_OP 1/#undef HAVE_AS_CFI_PSEUDO_OP/' aarch64-apple-darwin/fficonfig.h
    if ! grep -q "^#define STDC_HEADERS" aarch64-apple-darwin/fficonfig.h; then
        echo "#define STDC_HEADERS 1" >> aarch64-apple-darwin/fficonfig.h
    fi
    if [ -f include/ffi.h ] && ! grep -q "#include <stdint.h>" include/ffi.h; then
        sed -i '' '/#include <stddef.h>/a\
#include <stdint.h>
' include/ffi.h
    fi
    
    # Patch Makefile to use -Werror
    if [ -f "aarch64-apple-darwin/Makefile" ]; then
        sed -i '' 's/-Wno-error/-Werror/g' aarch64-apple-darwin/Makefile
    fi
    
    # Build
    echo "Building libffi..."
    export LIBTOOLFLAGS="--quiet"
    if [ -d "aarch64-apple-darwin" ]; then
        cd aarch64-apple-darwin
        make -s -j$(sysctl -n hw.ncpu)
        echo "Installing libffi..."
        make -s install
        cd ..
    else
        make -s -j$(sysctl -n hw.ncpu)
        echo "Installing libffi..."
        make -s install
    fi
    unset LIBTOOLFLAGS

elif [ "${PLATFORM}" == "macos" ]; then
    ./configure \
        --prefix="${INSTALL_DIR}" \
        --enable-static \
        --disable-shared
    
    echo "Building libffi..."
    make -j$(sysctl -n hw.ncpu)
    
    echo "Installing libffi..."
    make install
fi

echo "Success! libffi installed to ${INSTALL_DIR}"

if [ "${PLATFORM}" == "ios" ]; then
    echo "Creating FFI framework for ios..."
    "${ROOT_DIR}/scripts/create-static-framework.sh" \
        --platform "${PLATFORM}" \
        --name "FFI" \
        --libs "libffi.a" \
        --include-subdir "" \
        --recursive-headers
        
    echo "Success! FFI framework created at ${INSTALL_DIR}/Frameworks/FFI.framework"
fi
