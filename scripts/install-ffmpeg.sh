#!/bin/bash

# install-ffmpeg.sh
# Unified script to build FFmpeg for macOS (native) or iOS Simulator

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
FFMPEG_DIR="${ROOT_DIR}/dependencies/ffmpeg"

if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${FFMPEG_DIR}/build-ios"
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    # export PKG_CONFIG_PATH="${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig"
    
    CONFIGURE_ARGS=(
        "--enable-cross-compile"
        "--arch=arm64"
        "--target-os=darwin"
        "--cc=xcrun -sdk iphonesimulator clang"
        "--cxx=xcrun -sdk iphonesimulator clang++"
        "--sysroot=${SDK_PATH}"
        "--extra-cflags=-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fPIC"
        "--extra-ldflags=-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"
        "--enable-pic"
        "--enable-small"
    )
elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${FFMPEG_DIR}/build-macos"
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/share/pkgconfig:$PKG_CONFIG_PATH"
    
    CONFIGURE_ARGS=(
        "--extra-cflags=-fPIC"
    )
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${FFMPEG_DIR}" ]; then
    echo "Error: ffmpeg not found"
    exit 1
fi

cd "${FFMPEG_DIR}"

echo "Cleaning previous build..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

# Configure FFmpeg
# Minimal configuration for waypipe
echo "Configuring FFmpeg..."
./configure \
    --prefix="${INSTALL_DIR}" \
    --enable-static \
    --disable-shared \
    --disable-debug \
    --disable-doc \
    --disable-programs \
    --enable-videotoolbox \
    --enable-hwaccel=h264_videotoolbox \
    --enable-hwaccel=hevc_videotoolbox \
    "${CONFIGURE_ARGS[@]}" \
    >"${BUILD_DIR}/configure.log" 2>&1 || {
    echo "Configure failed:"
    tail -50 "${BUILD_DIR}/configure.log"
    exit 1
}

echo "Building FFmpeg..."
make -j$(sysctl -n hw.ncpu) >"${BUILD_DIR}/build.log" 2>&1 || {
    echo "Build failed:"
    tail -100 "${BUILD_DIR}/build.log"
    exit 1
}

echo "Installing FFmpeg..."
make install >"${BUILD_DIR}/install.log" 2>&1 || {
    echo "Install failed:"
    tail -50 "${BUILD_DIR}/install.log"
    exit 1
}

echo "Success! FFmpeg installed to ${INSTALL_DIR}"

if [ "${PLATFORM}" == "ios" ]; then
    echo "Creating FFmpeg framework for ${PLATFORM}..."
    
    # Merge all FFmpeg static libraries into a single libffmpeg.a
    FFMPEG_LIBS=(
        "${INSTALL_DIR}/lib/libavcodec.a"
        "${INSTALL_DIR}/lib/libavdevice.a"
        "${INSTALL_DIR}/lib/libavfilter.a"
        "${INSTALL_DIR}/lib/libavformat.a"
        "${INSTALL_DIR}/lib/libavutil.a"
        "${INSTALL_DIR}/lib/libswresample.a"
        "${INSTALL_DIR}/lib/libswscale.a"
    )
    
    # Check if libraries exist before merging
    EXISTING_LIBS=()
    for lib in "${FFMPEG_LIBS[@]}"; do
        if [ -f "$lib" ]; then
            EXISTING_LIBS+=("$lib")
        fi
    done
    
    if [ ${#EXISTING_LIBS[@]} -gt 0 ]; then
        # Merge libraries using libtool
        libtool -static -o "${INSTALL_DIR}/lib/libffmpeg.a" "${EXISTING_LIBS[@]}"
        
        # Create framework
        "${ROOT_DIR}/scripts/create-static-framework.sh" \
            --platform "${PLATFORM}" \
            --name "FFmpeg" \
            --libs "libffmpeg.a" \
            --include-subdir "" \
            --recursive-headers
            
        echo "Success! FFmpeg framework created at ${INSTALL_DIR}/Frameworks/FFmpeg.framework"
    else
        echo "Warning: No FFmpeg static libraries found to create framework."
    fi
fi
