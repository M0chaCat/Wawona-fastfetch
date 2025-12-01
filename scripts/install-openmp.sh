#!/bin/bash

# install-openmp.sh
# Unified script to build OpenMP (libomp) for macOS (native) or iOS Simulator

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
LLVM_DIR="${ROOT_DIR}/dependencies/llvm-project"
OPENMP_SRC="${LLVM_DIR}/openmp"
HOST_TOOLS_DIR="${ROOT_DIR}/build/ios-bootstrap"

# Use locally built CMake if available
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
        "-DCMAKE_C_FLAGS=-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fPIC"
        "-DCMAKE_CXX_FLAGS=-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fPIC"
    )
    BUILD_DIR="${OPENMP_SRC}/build-ios"
    
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    CMAKE_ARGS=(
        "-DCMAKE_C_FLAGS=-fPIC"
        "-DCMAKE_CXX_FLAGS=-fPIC"
    )
    BUILD_DIR="${OPENMP_SRC}/build-macos"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${OPENMP_SRC}" ]; then
    echo "Cloning llvm-project (openmp)..."
    if [ ! -d "${LLVM_DIR}" ]; then
        mkdir -p "${ROOT_DIR}/dependencies"
        git clone --depth 1 --filter=blob:none --sparse https://github.com/llvm/llvm-project.git "${LLVM_DIR}"
        cd "${LLVM_DIR}"
        git sparse-checkout set openmp cmake
    fi
fi

cd "${OPENMP_SRC}"

echo "Configuring OpenMP..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

"${CMAKE}" .. \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DLIBOMP_ENABLE_SHARED=OFF \
    -DLIBOMP_ENABLE_STATIC=ON \
    -DOPENMP_ENABLE_LIBOMPTARGET=OFF \
    "${CMAKE_ARGS[@]}"

echo "Building OpenMP..."
make -j$(sysctl -n hw.ncpu)

echo "Installing OpenMP..."
make install

# Create pkg-config file if needed (OpenMP install typically doesn't provide one for static lib)
if [ ! -f "${INSTALL_DIR}/lib/pkgconfig/openmp.pc" ] && [ -f "${INSTALL_DIR}/lib/libomp.a" ]; then
    mkdir -p "${INSTALL_DIR}/lib/pkgconfig"
    cat > "${INSTALL_DIR}/lib/pkgconfig/openmp.pc" << OMP_PC_EOF
prefix=${INSTALL_DIR}
exec_prefix=\${prefix}
libdir=\${exec_prefix}/lib
includedir=\${prefix}/include

Name: OpenMP
Description: OpenMP library
Version: 5.0
Libs: -L\${libdir} -lomp
Cflags: -I\${includedir} -fopenmp
OMP_PC_EOF
    echo "Created pkg-config file for OpenMP"
fi

echo "Success! OpenMP installed to ${INSTALL_DIR}"
