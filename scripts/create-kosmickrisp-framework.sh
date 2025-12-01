#!/bin/bash

# create-kosmickrisp-framework.sh
# Packages KosmicKrisp static library as a framework for App Store compliance
# Supports iOS (static framework) and macOS (static framework)

set -e

PLATFORM="macos"

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform) PLATFORM="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

echo "Target Platform: ${PLATFORM}"

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FRAMEWORK_NAME="Kosmickrisp"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    FRAMEWORK_DIR="${INSTALL_DIR}/Frameworks/${FRAMEWORK_NAME}.framework"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    STATIC_LIB="${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a"
    SUPPORTED_PLATFORM="iPhoneSimulator"
    MIN_VERSION="15.0"
    CC="xcrun -sdk iphonesimulator clang"
    CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0"
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    FRAMEWORK_DIR="${INSTALL_DIR}/Frameworks/${FRAMEWORK_NAME}.framework"
    SDK_PATH=$(xcrun --sdk macosx --show-sdk-path)
    STATIC_LIB="${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a"
    SUPPORTED_PLATFORM="MacOSX"
    MIN_VERSION="12.0"
    CC="xcrun -sdk macosx clang"
    CFLAGS="-isysroot ${SDK_PATH} -mmacosx-version-min=12.0"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

echo "Using SDK: ${SDK_PATH}"

# Find the static library
if [ ! -f "${STATIC_LIB}" ]; then
    echo "Error: Static library not found at ${STATIC_LIB}"
    echo "Build kosmickrisp first with: make install-kosmickrisp --platform ${PLATFORM}"
    exit 1
fi

echo "Creating Kosmickrisp framework from ${STATIC_LIB}..."

# Create framework directory structure
rm -rf "${FRAMEWORK_DIR}"
mkdir -p "${FRAMEWORK_DIR}/Headers"
mkdir -p "${FRAMEWORK_DIR}/Modules"

# Copy static library to framework
cp "${STATIC_LIB}" "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"

# Create framework Info.plist
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
    <string>com.wawona.kosmickrisp</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>MinimumOSVersion</key>
    <string>${MIN_VERSION}</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>${SUPPORTED_PLATFORM}</string>
    </array>
</dict>
</plist>
EOF

# Create module map for Swift/Objective-C compatibility
cat > "${FRAMEWORK_DIR}/Modules/module.modulemap" <<EOF
framework module ${FRAMEWORK_NAME} {
    umbrella header "${FRAMEWORK_NAME}.h"
    export *
    module * { export * }
}
EOF

# Create umbrella header (empty for now - can be populated with public API if needed)
cat > "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h" <<EOF
//
//  ${FRAMEWORK_NAME}.h
//  Kosmickrisp Framework
//
//  Static framework wrapper for KosmicKrisp Vulkan driver
//

#import <Foundation/Foundation.h>

// Framework version information
FOUNDATION_EXPORT double ${FRAMEWORK_NAME}VersionNumber;
FOUNDATION_EXPORT const unsigned char ${FRAMEWORK_NAME}VersionString[];

// Note: This framework contains the KosmicKrisp Vulkan driver as a static library.
// For iOS App Store compliance, dynamic libraries are not allowed.
// The Vulkan driver is statically linked into the Wawona compositor.
EOF

# Create version header
cat > "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}-Version.h" <<EOF
//
//  ${FRAMEWORK_NAME}-Version.h
//  Kosmickrisp Framework
//

#define ${FRAMEWORK_NAME}_VERSION_NUMBER 1.0
#define ${FRAMEWORK_NAME}_VERSION_STRING "1.0"
EOF

# Create version source file  
VERSION_STR="1.0"
cat > "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.m" <<EOF
//
//  ${FRAMEWORK_NAME}-Version.m
//  Kosmickrisp Framework
//

#import <Foundation/Foundation.h>
#import "${FRAMEWORK_NAME}-Version.h"

double ${FRAMEWORK_NAME}VersionNumber = ${FRAMEWORK_NAME}_VERSION_NUMBER;
const unsigned char ${FRAMEWORK_NAME}VersionString[] = "${VERSION_STR}";
EOF

# Compile version source into the framework
${CC} \
    ${CFLAGS} \
    -fobjc-arc \
    -I"${FRAMEWORK_DIR}/Headers" \
    -c "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.m" \
    -o "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.o"

# Merge version object into the static library
libtool -static \
    -o "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}.tmp" \
    "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}" \
    "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.o"

mv "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}.tmp" "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"

# Clean up temporary files
rm -f "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.m" "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}-Version.o"

# For static frameworks, we can use a simpler structure
# Move Info.plist to Resources
mkdir -p "${FRAMEWORK_DIR}/Resources"
mv "${FRAMEWORK_DIR}/Info.plist" "${FRAMEWORK_DIR}/Resources/Info.plist"

echo "Success! Framework created at ${FRAMEWORK_DIR}"
