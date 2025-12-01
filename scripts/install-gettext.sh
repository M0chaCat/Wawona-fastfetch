#!/bin/bash

# install-gettext.sh
# Unified script to build gettext for macOS (native) or iOS Simulator

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
GETTEXT_DIR="${ROOT_DIR}/dependencies/gettext"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    echo "Using SDK: ${SDK_PATH}"
    
    export CC="xcrun -sdk iphonesimulator clang"
    export CFLAGS="-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0 -fPIC"
    export AR="xcrun -sdk iphonesimulator ar"
    export RANLIB="xcrun -sdk iphonesimulator ranlib"
    
    CONFIGURE_ARGS=(
        "--host=aarch64-apple-darwin"
    )
    BUILD_DIR="${GETTEXT_DIR}/build-ios"
    
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    export CFLAGS="-fPIC"
    CONFIGURE_ARGS=()
    BUILD_DIR="${GETTEXT_DIR}/build-macos"
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${GETTEXT_DIR}" ]; then
    echo "Cloning gettext..."
    git clone https://git.savannah.gnu.org/git/gettext.git "${GETTEXT_DIR}"
fi

cd "${GETTEXT_DIR}"

# Checkout release tag if needed
if [ ! -f "configure" ]; then
    echo "Checking out gettext release tag..."
    git fetch --tags >/dev/null 2>&1 || true
    LATEST_TAG=$(git tag | grep -E "^v?[0-9]+\.[0-9]+(\.[0-9]+)?$" | sort -V | tail -1)
    if [ -z "${LATEST_TAG}" ]; then
        LATEST_TAG=$(git tag | grep -E "^[0-9]+\.[0-9]+" | sort -V | tail -1)
    fi
    if [ -n "${LATEST_TAG}" ]; then
        git checkout -q "${LATEST_TAG}" 2>&1 || git checkout -q master 2>&1 || true
    fi
fi

# If still no configure, skip if optional
if [ ! -f "configure" ]; then
    echo "Warning: gettext configure not found, skipping (optional)"
    exit 0
fi

echo "Configuring gettext..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

../configure \
    --prefix="${INSTALL_DIR}" \
    --enable-static \
    --disable-shared \
    --disable-java \
    --disable-csharp \
    --disable-libasprintf \
    --disable-curses \
    "${CONFIGURE_ARGS[@]}"

echo "Building gettext..."
make -j$(sysctl -n hw.ncpu)

echo "Installing gettext..."
make install

echo "Success! gettext installed to ${INSTALL_DIR}"
