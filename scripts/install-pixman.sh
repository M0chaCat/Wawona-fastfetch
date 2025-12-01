#!/bin/bash

# install-pixman.sh
# Unified script to build pixman for macOS (native) or iOS Simulator

set -e
set -o pipefail

# Default to native build if no platform specified
PLATFORM="macos"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

echo "Target Platform: ${PLATFORM}"

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIXMAN_DIR="${ROOT_DIR}/dependencies/pixman"

# Platform-specific settings
if [ "${PLATFORM}" == "ios" ]; then
    BUILD_DIR="${PIXMAN_DIR}/build-ios"
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    CROSS_FILE="${ROOT_DIR}/dependencies/wayland/cross-ios.txt"
    HOST_TOOLS_DIR="${ROOT_DIR}/build/ios-bootstrap" # Use host tools
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    # export PKG_CONFIG_PATH="${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig"
    
    MESON_EXTRA_ARGS=(
        "--cross-file" "${CROSS_FILE}"
    )
    
    # iOS ASM patching logic here (kept from original script)
    MESON_BUILD="${PIXMAN_DIR}/meson.build"
    if [ -f "${MESON_BUILD}" ] && ! grep -q "# Patched for iOS ASM" "${MESON_BUILD}" 2>/dev/null; then
        echo "Patching meson.build for iOS ASM support..."
        # ... (insert patching logic if needed, or assume patched)
        # For brevity, assuming patching logic is handled or pre-patched.
        # In a full merge, I would include the sed/python patching block here.
        # To be safe, I'll include the python patcher.
        python3 -c "
import sys
import os
if os.path.exists('${MESON_BUILD}'):
    with open('${MESON_BUILD}', 'r') as f:
        lines = f.readlines()
    patched = False
    i = 0
    while i < len(lines):
        if 'test for ASM .func directive' in lines[i]:
            indent = len(lines[i-2]) - len(lines[i-2].lstrip())
            lines.insert(i-2, ' ' * indent + '# Patched for iOS: Force .func directive support\n')
            lines.insert(i-1, ' ' * indent + 'if host_machine.system() == \"darwin\" and host_machine.cpu_family() == \"aarch64\"\n')
            lines.insert(i, ' ' * (indent + 4) + 'config.set(\"ASM_HAVE_FUNC_DIRECTIVE\", 1)\n')
            lines.insert(i+1, ' ' * indent + 'elif\n')
            patched = True
            break
        i += 1
    
    # Reset i for next search, but be careful with modified indices
    i = 0
    while i < len(lines):
        if 'test for ASM .syntax unified directive' in lines[i]:
             # Check if already patched to avoid double patching
             if i > 2 and '# Patched for iOS' in lines[i-2]:
                 break
             indent = len(lines[i-2]) - len(lines[i-2].lstrip())
             lines.insert(i-2, ' ' * indent + '# Patched for iOS: Force .syntax unified support\n')
             lines.insert(i-1, ' ' * indent + 'if host_machine.system() == \"darwin\" and host_machine.cpu_family() == \"aarch64\"\n')
             lines.insert(i, ' ' * (indent + 4) + 'config.set(\"ASM_HAVE_SYNTAX_UNIFIED\", 1)\n')
             lines.insert(i+1, ' ' * indent + 'elif\n')
             patched = True
             break
        i += 1

    if patched:
        with open('${MESON_BUILD}', 'w') as f:
            f.writelines(lines)
        print('Patched meson.build')
"
    fi

elif [ "${PLATFORM}" == "macos" ]; then
    BUILD_DIR="${PIXMAN_DIR}/build-macos"
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"
    MESON_EXTRA_ARGS=()
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${PIXMAN_DIR}" ]; then
    echo "Error: pixman not found at ${PIXMAN_DIR}"
    exit 1
fi

cd "${PIXMAN_DIR}"

# Checkout stable
if [ -z "$(git describe --tags --exact-match HEAD 2>/dev/null)" ]; then
    echo "Checking out stable version..."
    git checkout -q pixman-0.46.4 2>/dev/null || git checkout -q 0.46.4 2>/dev/null || true
fi

echo "Configuring pixman for ${PLATFORM}..."
rm -rf "${BUILD_DIR}"

meson setup "${BUILD_DIR}" \
    --prefix="${INSTALL_DIR}" \
    --default-library=static \
    -Dgtk=disabled \
    -Dlibpng=disabled \
    -Dtests=disabled \
    -Dopenmp=disabled \
    -Dwerror=true \
    -Dc_std=gnu99 \
    "${MESON_EXTRA_ARGS[@]}"

echo "Building pixman..."
ninja -C "${BUILD_DIR}"

echo "Installing pixman..."
ninja -C "${BUILD_DIR}" install

echo "Success! pixman installed to ${INSTALL_DIR}"

if [ "${PLATFORM}" == "ios" ]; then
    echo "Creating Pixman framework for ios..."
    "${ROOT_DIR}/scripts/create-static-framework.sh" \
        --platform "${PLATFORM}" \
        --name "Pixman" \
        --libs "libpixman-1.a" \
        --include-subdir "pixman-1" \
        --recursive-headers
        
    echo "Success! Pixman framework created at ${INSTALL_DIR}/Frameworks/Pixman.framework"
fi
