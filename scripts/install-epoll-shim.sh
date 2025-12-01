#!/bin/bash

# install-epoll-shim.sh
# Unified script to build epoll-shim for macOS (native) or iOS Simulator

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
EPOLL_SHIM_DIR="${ROOT_DIR}/dependencies/epoll-shim"
HOST_TOOLS_DIR="${ROOT_DIR}/build/ios-bootstrap"

# Use locally built CMake if available (for iOS cross-compilation consistency)
if [ -f "${HOST_TOOLS_DIR}/bin/cmake" ]; then
    CMAKE="${HOST_TOOLS_DIR}/bin/cmake"
    export PATH="${HOST_TOOLS_DIR}/bin:${PATH}"
else
    CMAKE="cmake"
fi

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    CMAKE_ARGS=(
        "-DCMAKE_SYSTEM_NAME=iOS"
        "-DCMAKE_OSX_SYSROOT=${SDK_PATH}"
        "-DCMAKE_OSX_ARCHITECTURES=arm64"
        "-DCMAKE_OSX_DEPLOYMENT_TARGET=15.0"
        "-DCMAKE_C_FLAGS=-Wall -Wextra -Werror -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition -Wmissing-declarations -Wuninitialized -Winit-self -Wpointer-arith -Wcast-qual -Wwrite-strings -Wconversion -Wsign-conversion -Wformat=2 -Wformat-security -Wundef -Wshadow -Wstrict-overflow=5 -Wswitch-default -Wswitch-enum -Wunreachable-code -Wfloat-equal -Wstack-protector -fstack-protector-strong -fPIC -Werror=incompatible-pointer-types-discards-qualifiers -Wno-pedantic"
    )
    BUILD_SUBDIR="build-ios"
    
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    
    CMAKE_ARGS=(
        "-DCMAKE_BUILD_TYPE=Release"
        "-DCMAKE_C_FLAGS=-Wall -Wextra -Werror -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition -Wmissing-declarations -Wuninitialized -Winit-self -Wpointer-arith -Wcast-qual -Wwrite-strings -Wconversion -Wsign-conversion -Wformat=2 -Wformat-security -Wundef -Wshadow -Wstrict-overflow=5 -Wswitch-default -Wswitch-enum -Wunreachable-code -Wfloat-equal -Wstack-protector -fstack-protector-strong -fPIC"
    )
    BUILD_SUBDIR="build-macos"
elif [ "${PLATFORM}" == "host" ]; then
    INSTALL_DIR="${ROOT_DIR}/build/ios-bootstrap"
    
    CMAKE_ARGS=(
        "-DCMAKE_BUILD_TYPE=Release"
        "-DCMAKE_C_FLAGS=-Wall -Wextra -Werror -Wstrict-prototypes -Wmissing-prototypes -Wold-style-definition -Wmissing-declarations -Wuninitialized -Winit-self -Wpointer-arith -Wcast-qual -Wwrite-strings -Wconversion -Wsign-conversion -Wformat=2 -Wformat-security -Wundef -Wshadow -Wstrict-overflow=5 -Wswitch-default -Wswitch-enum -Wunreachable-code -Wfloat-equal -Wstack-protector -fstack-protector-strong -fPIC"
    )
    BUILD_SUBDIR="build-host"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${EPOLL_SHIM_DIR}" ]; then
    echo "Cloning epoll-shim..."
    git clone https://github.com/jiixyj/epoll-shim.git "${EPOLL_SHIM_DIR}"
fi

cd "${EPOLL_SHIM_DIR}"

echo "Configuring epoll-shim..."
rm -rf "${BUILD_SUBDIR}"
mkdir "${BUILD_SUBDIR}"
cd "${BUILD_SUBDIR}"

"${CMAKE}" .. \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
    -DBUILD_TESTING=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    -DALLOWS_ONESHOT_TIMERS_WITH_TIMEOUT_ZERO_EXITCODE=0 \
    -DENABLE_COMPILER_WARNINGS=ON \
    --log-level=WARNING \
    "${CMAKE_ARGS[@]}"

echo "Building epoll-shim..."
make -j$(sysctl -n hw.ncpu)

echo "Installing epoll-shim..."
make install

# Fix pkg-config file (remove -lrt on macOS/iOS)
if [ -f "${INSTALL_DIR}/libdata/pkgconfig/epoll-shim.pc" ]; then
    sed -i.bak 's/-lrt//g' "${INSTALL_DIR}/libdata/pkgconfig/epoll-shim.pc"
    rm "${INSTALL_DIR}/libdata/pkgconfig/epoll-shim.pc.bak"
fi
if [ -f "${INSTALL_DIR}/lib/pkgconfig/epoll-shim.pc" ]; then
    sed -i.bak 's/-lrt//g' "${INSTALL_DIR}/lib/pkgconfig/epoll-shim.pc"
    rm "${INSTALL_DIR}/lib/pkgconfig/epoll-shim.pc.bak"
fi

echo "Success! epoll-shim installed to ${INSTALL_DIR}"

if [ "${PLATFORM}" == "ios" ]; then
    echo "Creating EpollShim framework for ios..."
    "${ROOT_DIR}/scripts/create-static-framework.sh" \
        --platform "${PLATFORM}" \
        --name "EpollShim" \
        --libs "libepoll-shim.a" \
        --include-subdir "" \
        --recursive-headers
        
    echo "Success! EpollShim framework created at ${INSTALL_DIR}/Frameworks/EpollShim.framework"
fi
