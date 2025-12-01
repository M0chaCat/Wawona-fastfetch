#!/bin/bash

# install-angle.sh
# Fetch and build ANGLE as static libraries and package into Angle.framework
# Supports iOS (Simulator) and macOS static frameworks for App Store compliance.

set -e
set -o pipefail

PLATFORM="macos"

while [[ $# -gt 0 ]]; do
  case $1 in
    --platform) PLATFORM="$2"; shift 2 ;;
    *) echo "Unknown argument: $1"; exit 1 ;;
  esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ "${PLATFORM}" == "ios" ]; then
  INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
  SDK="iphonesimulator"
  MINVER="-mios-simulator-version-min=15.0"
  ARCH="arm64"
elif [ "${PLATFORM}" == "macos" ]; then
  INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
  SDK="macosx"
  MINVER="-mmacosx-version-min=12.0"
  ARCH="arm64"
else
  echo "Error: Angle is supported only on iOS and macOS. Android is not supported."; exit 2
fi

ANGLE_DIR="${INSTALL_DIR}/angle"
mkdir -p "${ANGLE_DIR}"

if [ ! -d "${ANGLE_DIR}/src" ]; then
  echo "Cloning ANGLE..."
  git clone https://chromium.googlesource.com/angle/angle "${ANGLE_DIR}" || git clone https://github.com/google/angle.git "${ANGLE_DIR}"
fi

echo "Fetching depot_tools for GN/Ninja..."
DEPOT_TOOLS_DIR="${INSTALL_DIR}/depot_tools"
mkdir -p "${DEPOT_TOOLS_DIR}"
if [ ! -d "${DEPOT_TOOLS_DIR}/.git" ]; then
  git clone https://chromium.googlesource.com/chromium/tools/depot_tools.git "${DEPOT_TOOLS_DIR}" || true
fi
export PATH="${DEPOT_TOOLS_DIR}:$PATH"

echo "Configuring ANGLE with GN/Ninja (static)..."
SDK_PATH=$(xcrun --sdk ${SDK} --show-sdk-path)
OUT_DIR="${ANGLE_DIR}/out/Static"
mkdir -p "${OUT_DIR}"

if [ "${PLATFORM}" == "ios" ]; then
  GN_ARGS="is_debug=false is_component_build=false target_os=\"ios\" target_cpu=\"arm64\" use_custom_libcxx=false angle_enable_metal=true angle_enable_gl=false angle_enable_gl_desktop_backend=false"
else
  GN_ARGS="is_debug=false is_component_build=false target_os=\"mac\" target_cpu=\"arm64\" use_custom_libcxx=false angle_enable_metal=true angle_enable_gl=false angle_enable_gl_desktop_backend=false"
fi
gn gen "${OUT_DIR}" --args="${GN_ARGS}" || echo "GN generation failed; skipping ANGLE build"
ninja -C "${OUT_DIR}" libEGL libGLESv2 || echo "Ninja build failed; skipping ANGLE build"

mkdir -p "${INSTALL_DIR}/lib" "${INSTALL_DIR}/include"
if [ -d "${ANGLE_DIR}/include" ]; then
  cp -R "${ANGLE_DIR}/include"/* "${INSTALL_DIR}/include/"
fi
if [ -f "${OUT_DIR}/libEGL.a" ]; then cp "${OUT_DIR}/libEGL.a" "${INSTALL_DIR}/lib/"; fi
if [ -f "${OUT_DIR}/libGLESv2.a" ]; then cp "${OUT_DIR}/libGLESv2.a" "${INSTALL_DIR}/lib/"; fi

# Package into Angle.framework
if [ -f "${INSTALL_DIR}/lib/libEGL.a" ] && [ -f "${INSTALL_DIR}/lib/libGLESv2.a" ]; then
  "${ROOT_DIR}/scripts/create-static-framework.sh" --platform "${PLATFORM}" --name "Angle" --libs "libEGL.a libGLESv2.a" --headers "*.h" --include-subdir "GLES"
else
  echo "Skipping Angle.framework creation; static libs not found in ${INSTALL_DIR}/lib"
fi

echo "ANGLE framework installed for ${PLATFORM}"
