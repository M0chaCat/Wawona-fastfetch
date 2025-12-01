#!/bin/bash

# create-static-framework.sh
# Creates a static framework from static libraries for iOS or macOS

set -e
set -o pipefail

PLATFORM="ios"
FRAMEWORK_NAME=""
LIB_NAMES=""
VERSION="1.0.0"
HEADERS_FILTER="*.h"
INCLUDE_SUBDIR=""
RECURSIVE_HEADERS=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform) PLATFORM="$2"; shift 2 ;;
        --name) FRAMEWORK_NAME="$2"; shift 2 ;;
        --libs) LIB_NAMES="$2"; shift 2 ;; # Space separated list of library filenames (e.g. "libzstd.a liblz4.a")
        --version) VERSION="$2"; shift 2 ;;
        --headers) HEADERS_FILTER="$2"; shift 2 ;; # Glob pattern for headers
        --include-subdir) INCLUDE_SUBDIR="$2"; shift 2 ;; # Subdirectory in include/ to look for headers
        --recursive-headers) RECURSIVE_HEADERS=true; shift 1 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

if [ -z "$FRAMEWORK_NAME" ] || [ -z "$LIB_NAMES" ]; then
    echo "Usage: $0 --name Name --libs 'lib1.a lib2.a' [--platform ios|macos] [--version 1.0] [--headers '*.h'] [--include-subdir subdir]"
    exit 1
fi

echo "Creating $FRAMEWORK_NAME.framework for $PLATFORM..."

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    FRAMEWORK_DIR="${INSTALL_DIR}/Frameworks/${FRAMEWORK_NAME}.framework"
    SDK_NAME="iphonesimulator"
    SDK_PATH=$(xcrun --sdk "${SDK_NAME}" --show-sdk-path)
    ARCH="arm64"
    MIN_VERSION="-mios-simulator-version-min=15.0"
    SUPPORTED_PLATFORM="iPhoneSimulator"
    LIBTOOL_FLAGS=(-static -arch_only arm64 -syslibroot "${SDK_PATH}")
    
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    FRAMEWORK_DIR="${INSTALL_DIR}/Frameworks/${FRAMEWORK_NAME}.framework"
    SDK_NAME="macosx"
    SDK_PATH=$(xcrun --sdk "${SDK_NAME}" --show-sdk-path)
    ARCH="arm64"
    MIN_VERSION="-mmacosx-version-min=12.0"
    SUPPORTED_PLATFORM="MacOSX"
    LIBTOOL_FLAGS=(-static -syslibroot "${SDK_PATH}")
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

# Create framework directory structure
rm -rf "${FRAMEWORK_DIR}"
mkdir -p "${FRAMEWORK_DIR}/Headers"
mkdir -p "${FRAMEWORK_DIR}/Modules"
mkdir -p "${FRAMEWORK_DIR}/Resources"

# Copy headers
echo "Copying headers..."
INCLUDE_PATH="${INSTALL_DIR}/include"
if [ -n "$INCLUDE_SUBDIR" ]; then
    INCLUDE_PATH="${INCLUDE_PATH}/${INCLUDE_SUBDIR}"
fi

if [ -d "${INCLUDE_PATH}" ]; then
    if [ "$RECURSIVE_HEADERS" = true ]; then
        echo "Copying headers recursively from ${INCLUDE_PATH} with filter ${HEADERS_FILTER}..."
        # Use find to locate matching files/directories and cp -R to copy them preserving structure
        find "${INCLUDE_PATH}" -maxdepth 1 -name "${HEADERS_FILTER}" -exec cp -R {} "${FRAMEWORK_DIR}/Headers/" \;
    else
        # find doesn't support glob expansion directly in path, so use shell expansion or find options
        # We use -name with the filter
        find "${INCLUDE_PATH}" -maxdepth 1 -name "${HEADERS_FILTER}" -exec cp {} "${FRAMEWORK_DIR}/Headers/" \;
    fi
else
    echo "Warning: Include directory ${INCLUDE_PATH} not found."
fi

# Create module map
cat > "${FRAMEWORK_DIR}/Modules/module.modulemap" <<EOF
framework module ${FRAMEWORK_NAME} {
    umbrella header "${FRAMEWORK_NAME}.h"
    
    export *
    module * { export * }
}
EOF

# Create umbrella header if it doesn't exist
if [ ! -f "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h" ]; then
    echo "// Umbrella header for ${FRAMEWORK_NAME}" > "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
    echo "#import <Foundation/Foundation.h>" >> "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
    
    # Add imports for all other headers
    for header in "${FRAMEWORK_DIR}/Headers/"*.h; do
        header_name=$(basename "$header")
        if [ "$header_name" != "${FRAMEWORK_NAME}.h" ]; then
            echo "#import <${FRAMEWORK_NAME}/${header_name}>" >> "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
        fi
    done
    
    echo "FOUNDATION_EXPORT double ${FRAMEWORK_NAME}VersionNumber;" >> "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
    echo "FOUNDATION_EXPORT const unsigned char ${FRAMEWORK_NAME}VersionString[];" >> "${FRAMEWORK_DIR}/Headers/${FRAMEWORK_NAME}.h"
fi

# Create Info.plist
cat > "${FRAMEWORK_DIR}/Resources/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.wawona.${FRAMEWORK_NAME}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>MinimumOSVersion</key>
    <string>15.0</string>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>${SUPPORTED_PLATFORM}</string>
    </array>
</dict>
</plist>
EOF

# Combine static libraries
echo "Combining static libraries..."
LIBS_ARRAY=()
for lib in $LIB_NAMES; do
    LIB_PATH="${INSTALL_DIR}/lib/${lib}"
    if [ -f "${LIB_PATH}" ]; then
        LIBS_ARRAY+=("${LIB_PATH}")
    else
        echo "Error: Library ${lib} not found in ${INSTALL_DIR}/lib/"
        exit 1
    fi
done

# Use libtool to create the framework binary
xcrun --sdk "${SDK_NAME}" libtool \
    "${LIBTOOL_FLAGS[@]}" \
    -o "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}" \
    "${LIBS_ARRAY[@]}"

echo "Success! Created ${FRAMEWORK_DIR}"
