#!/bin/bash

# create-wayland-framework.sh
# Creates a framework from Wayland static libraries for iOS or macOS

set -e
set -o pipefail

PLATFORM="ios"

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform) PLATFORM="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

echo "Target Platform: ${PLATFORM}"

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORK_NAME="Wayland"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    FRAMEWORK_DIR="${INSTALL_DIR}/Frameworks/${FRAMEWORK_NAME}.framework"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    ARCH="arm64"
    MIN_VERSION="-mios-simulator-version-min=15.0"
    SUPPORTED_PLATFORM="iPhoneSimulator"
    LIBTOOL_FLAGS="-static -arch_only arm64 -syslibroot ${SDK_PATH}"
    
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    FRAMEWORK_DIR="${INSTALL_DIR}/Frameworks/${FRAMEWORK_NAME}.framework"
    SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
    ARCH="arm64" # Assuming arm64 for modern macs, or universal? Let's default to host arch or arm64
    # For macOS host build, we usually just let clang decide arch, but for framework we might want specific
    # Let's rely on what static libs were built as.
    MIN_VERSION="-mmacosx-version-min=12.0"
    SUPPORTED_PLATFORM="MacOSX"
    # libtool on macOS for static libs doesn't need -arch_only if inputs are single arch or fat
    LIBTOOL_FLAGS="-static -syslibroot ${SDK_PATH}"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

# Create framework directory structure
mkdir -p "${FRAMEWORK_DIR}/Headers"
mkdir -p "${FRAMEWORK_DIR}/Modules"
mkdir -p "${FRAMEWORK_DIR}/Resources"

# Copy headers
echo "Copying Wayland headers..."
if [ -d "${INSTALL_DIR}/include" ]; then
    find "${INSTALL_DIR}/include" -name "wayland*.h" -exec cp {} "${FRAMEWORK_DIR}/Headers/" \;
fi

# Create module map
cat > "${FRAMEWORK_DIR}/Modules/module.modulemap" <<EOF
framework module ${FRAMEWORK_NAME} {
    umbrella header "${FRAMEWORK_NAME}.h"
    
    export *
    module * { export * }
}
EOF

# Create umbrella header
cat > "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h" <<EOF
//
//  ${FRAMEWORK_NAME}.h
//  ${FRAMEWORK_NAME}
//
//  Wayland Protocol Implementation
//

#import <Foundation/Foundation.h>

// Wayland Server
#import <${FRAMEWORK_NAME}/wayland-server.h>
#import <${FRAMEWORK_NAME}/wayland-server-core.h>
#import <${FRAMEWORK_NAME}/wayland-server-protocol.h>

// Wayland Client
#import <${FRAMEWORK_NAME}/wayland-client.h>
#import <${FRAMEWORK_NAME}/wayland-client-core.h>
#import <${FRAMEWORK_NAME}/wayland-client-protocol.h>

// Wayland Utilities
#import <${FRAMEWORK_NAME}/wayland-util.h>
#import <${FRAMEWORK_NAME}/wayland-version.h>

// Wayland Cursor
#import <${FRAMEWORK_NAME}/wayland-cursor.h>

// Wayland EGL
#import <${FRAMEWORK_NAME}/wayland-egl.h>
#import <${FRAMEWORK_NAME}/wayland-egl-core.h>
#import <${FRAMEWORK_NAME}/wayland-egl-backend.h>

FOUNDATION_EXPORT double ${FRAMEWORK_NAME}VersionNumber;
FOUNDATION_EXPORT const unsigned char ${FRAMEWORK_NAME}VersionString[];
EOF

# Create version header
cat > "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}-Version.h" <<EOF
//
//  ${FRAMEWORK_NAME}-Version.h
//  ${FRAMEWORK_NAME}
//
//  Version information for Wayland framework
//

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double ${FRAMEWORK_NAME}VersionNumber;
FOUNDATION_EXPORT const unsigned char ${FRAMEWORK_NAME}VersionString[];
EOF

# Create version source file
cat > "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.m" <<EOF
//
//  ${FRAMEWORK_NAME}-Version.m
//  ${FRAMEWORK_NAME}
//
//  Version information for Wayland framework
//

#import <Foundation/Foundation.h>

FOUNDATION_EXPORT double ${FRAMEWORK_NAME}VersionNumber;
FOUNDATION_EXPORT const unsigned char ${FRAMEWORK_NAME}VersionString[];

double ${FRAMEWORK_NAME}VersionNumber = 1.24;
const unsigned char ${FRAMEWORK_NAME}VersionString[] = "1.24.0";
EOF

# Compile the version source file into an object file
# For macOS we might not force arch if we want native
if [ "${PLATFORM}" == "ios" ]; then
    xcrun --sdk "${SDK_PATH}" clang \
        -arch ${ARCH} \
        ${MIN_VERSION} \
        -I"${FRAMEWORK_DIR}/Headers" \
        -Wno-extern-initializer \
        -c "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.m" \
        -o "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.o"
else
    xcrun --sdk "${SDK_PATH}" clang \
        ${MIN_VERSION} \
        -I"${FRAMEWORK_DIR}/Headers" \
        -Wno-extern-initializer \
        -c "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.m" \
        -o "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.o"
fi

# Combine static libraries into a single framework library
echo "Combining Wayland static libraries..."

# Collect all static libraries (in dependency order)
STATIC_LIBS=(
    "${INSTALL_DIR}/lib/libwayland-util.a"
    "${INSTALL_DIR}/lib/libwayland-private.a"
    "${INSTALL_DIR}/lib/libwayland-server.a"
    "${INSTALL_DIR}/lib/libwayland-client.a"
    "${INSTALL_DIR}/lib/libwayland-cursor.a"
    "${INSTALL_DIR}/lib/libwayland-egl.a"
)

# Check which libraries exist
EXISTING_LIBS=()
for lib in "${STATIC_LIBS[@]}"; do
    if [ -f "${lib}" ]; then
        EXISTING_LIBS+=("${lib}")
        echo "Found: $(basename ${lib})"
    fi
done

if [ ${#EXISTING_LIBS[@]} -eq 0 ]; then
    echo "Error: No Wayland static libraries found!"
    echo "Expected libraries in: ${INSTALL_DIR}/lib/"
    exit 1
fi

# Create a temporary directory for extraction
TEMP_DIR=$(mktemp -d)
trap "rm -rf ${TEMP_DIR}" EXIT

# Extract all object files from static libraries
for lib in "${EXISTING_LIBS[@]}"; do
    echo "Extracting objects from $(basename ${lib})..."
    (cd "${TEMP_DIR}" && ar x "${lib}" 2>/dev/null || true)
done

# Add the version object file
if [ -f "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.o" ]; then
    cp "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.o" "${TEMP_DIR}/"
fi

# Create the framework library by combining all static libraries
FRAMEWORK_LIB="${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"

# Use libtool to combine all static libraries
xcrun --sdk "${SDK_PATH}" libtool \
    ${LIBTOOL_FLAGS} \
    -o "${FRAMEWORK_LIB}" \
    "${EXISTING_LIBS[@]}" \
    "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.o"

# Create Info.plist
cat > "${FRAMEWORK_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.wayland.${FRAMEWORK_NAME}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.24.0</string>
    <key>CFBundleVersion</key>
    <string>1.24.0</string>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>${SUPPORTED_PLATFORM}</string>
    </array>
</dict>
</plist>
EOF

# Clean up temporary files
rm -f "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.m"
rm -f "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.o"

# For static frameworks, move Info.plist to Resources if it exists, or root if not?
# Standard macOS frameworks have Info.plist in Resources (inside Versions/A/Resources).
# But for static framework flat structure, let's put it in Resources or root.
# create-kosmickrisp-framework.sh puts it in Resources.
mkdir -p "${FRAMEWORK_DIR}/Resources"
mv "${FRAMEWORK_DIR}/Info.plist" "${FRAMEWORK_DIR}/Resources/Info.plist"

echo "Success! Wayland framework created at ${FRAMEWORK_DIR}"
