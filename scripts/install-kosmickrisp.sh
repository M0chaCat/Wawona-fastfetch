#!/bin/bash

# install-kosmickrisp.sh
# Unified script to build KosmicKrisp (Mesa) for macOS (native) or iOS Simulator

set -e

# Add Homebrew bison/flex to PATH if they exist (fixes build on macOS with newer Xcode/Bison issues)
if [ -d "/opt/homebrew/opt/bison/bin" ]; then
    export PATH="/opt/homebrew/opt/bison/bin:$PATH"
fi
if [ -d "/opt/homebrew/opt/flex/bin" ]; then
    export PATH="/opt/homebrew/opt/flex/bin:$PATH"
fi

PLATFORM="macos"

while [[ $# -gt 0 ]]; do
    case $1 in
        --platform) PLATFORM="$2"; shift 2 ;;
        *) echo "Unknown argument: $1"; exit 1 ;;
    esac
done

echo "Target Platform: ${PLATFORM}"
# Platform gating: KosmicKrisp supports only iOS and macOS
if [ "${PLATFORM}" == "android" ]; then
    echo "Error: KosmicKrisp is supported only on iOS and macOS. Android is not supported."
    exit 2
fi

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KOSMICKRISP_DIR="${ROOT_DIR}/dependencies/kosmickrisp"

if [ "${PLATFORM}" == "ios" ]; then
    INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
    BUILD_DIR="build-ios"
    SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)
    CROSS_FILE="${ROOT_DIR}/dependencies/wayland/cross-ios.txt"
    
    # Regenerate cross file
    "${ROOT_DIR}/scripts/generate-cross-ios.sh"
    
    echo "Using SDK: ${SDK_PATH}"
    
    # Add host tools to PATH
    export PATH="${ROOT_DIR}/build/ios-bootstrap/bin:${PATH}"
    
    # Ensure native wayland-scanner is available
    NATIVE_WAYLAND_SCANNER="${ROOT_DIR}/build/ios-bootstrap/bin/wayland-scanner"
    if [ ! -f "${NATIVE_WAYLAND_SCANNER}" ]; then
        # Try system/homebrew
        if ! command -v wayland-scanner >/dev/null; then
            echo "Error: wayland-scanner not found."
            exit 1
        fi
    fi
    
    # Install stub pkg-config files and headers BEFORE Meson configuration
    # This ensures Meson can find the stubs during configuration
    echo "Installing stub pkg-config files and headers for missing dependencies..."
    STUB_PC_DIR="${ROOT_DIR}/src/compat/macos/stubs/libinput-macos"
    INSTALL_PC_DIR="${INSTALL_DIR}/lib/pkgconfig"
    mkdir -p "${INSTALL_PC_DIR}"
    mkdir -p "${INSTALL_DIR}/include"
    
    # Copy all stub .pc files to install directory
    for pc_file in "${STUB_PC_DIR}"/*.pc; do
        if [ -f "${pc_file}" ]; then
            # Update prefix in stub files to use INSTALL_DIR
            pc_name=$(basename "${pc_file}")
            sed "s|prefix=.*|prefix=${INSTALL_DIR}|g" "${pc_file}" > "${INSTALL_PC_DIR}/${pc_name}"
            echo "  Installed stub: ${pc_name}"
        fi
    done
    
    # Install stub headers for missing dependencies
    STUB_INCLUDE_DIR="${ROOT_DIR}/src/compat/macos/stubs/libinput-macos/include"
    if [ -d "${STUB_INCLUDE_DIR}" ]; then
        # Copy headers recursively
        cp -r "${STUB_INCLUDE_DIR}"/* "${INSTALL_DIR}/include/" 2>/dev/null || true
        echo "  Installed stub headers"
    fi
    
    # Build and install stub libraries (for cc.find_library() to find)
    STUB_SRC_DIR="${ROOT_DIR}/src/compat/macos/stubs/libinput-macos"
    STUB_LIB_DIR="${INSTALL_DIR}/lib"
    mkdir -p "${STUB_LIB_DIR}"
    
    # Determine compiler and flags based on platform
    if [ "${PLATFORM}" == "ios" ]; then
        # Use xcrun to find the correct compiler for the SDK
        CC="$(xcrun --sdk iphonesimulator --find clang 2>/dev/null || echo clang)"
        CFLAGS="-isystem ${SDK_PATH}/usr/include -I${INSTALL_DIR}/include -target arm64-apple-ios15.0-simulator -isysroot ${SDK_PATH} -fPIC -std=c17"
        AR="$(xcrun --sdk iphonesimulator --find ar 2>/dev/null || echo ar)"
    else
        CC="clang"
        CFLAGS="-fPIC -std=c17"
        AR="ar"
    fi
    
    # Build libsensors stub
    if [ -f "${STUB_SRC_DIR}/libsensors-stub.c" ]; then
        echo "  Building stub library: libsensors"
        "${CC}" ${CFLAGS} -c "${STUB_SRC_DIR}/libsensors-stub.c" -o "${STUB_LIB_DIR}/libsensors-stub.o" 2>/dev/null || true
        if [ -f "${STUB_LIB_DIR}/libsensors-stub.o" ]; then
            "${AR}" rcs "${STUB_LIB_DIR}/libsensors.a" "${STUB_LIB_DIR}/libsensors-stub.o" 2>/dev/null || true
            rm -f "${STUB_LIB_DIR}/libsensors-stub.o"
        fi
    fi
    
    # Build libudev-stub
    if [ -f "${STUB_SRC_DIR}/libudev-stub.c" ]; then
        echo "  Building stub library: libudev-stub"
        "${CC}" ${CFLAGS} -c "${STUB_SRC_DIR}/libudev-stub.c" -o "${STUB_LIB_DIR}/libudev-stub.o" 2>/dev/null || true
        if [ -f "${STUB_LIB_DIR}/libudev-stub.o" ]; then
            "${AR}" rcs "${STUB_LIB_DIR}/libudev-stub.a" "${STUB_LIB_DIR}/libudev-stub.o" 2>/dev/null || true
            rm -f "${STUB_LIB_DIR}/libudev-stub.o"
        fi
    fi
    
    # Force pkg-config to look in ios-install AND ios-bootstrap AND stubs
    # This ensures we find target libs (wayland, zstd, etc.) AND host tools (wayland-scanner) AND stub libraries
    export PKG_CONFIG_LIBDIR="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:${INSTALL_DIR}/share/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/lib/pkgconfig:${ROOT_DIR}/build/ios-bootstrap/share/pkgconfig:${ROOT_DIR}/src/compat/macos/stubs/libinput-macos"
    unset PKG_CONFIG_PATH
    
    # Install Vulkan headers and create vulkan.pc for Zink
    mkdir -p "${INSTALL_DIR}/include/vulkan"
    cp -r "${KOSMICKRISP_DIR}/include/vulkan/"* "${INSTALL_DIR}/include/vulkan/"
    
    mkdir -p "${INSTALL_DIR}/lib/pkgconfig"
    cat > "${INSTALL_DIR}/lib/pkgconfig/vulkan.pc" <<EOF
prefix=${INSTALL_DIR}
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: Vulkan
Description: Vulkan Headers
Version: 1.3.268
Cflags: -I\${includedir}
Libs: 
EOF

    # Install libdrm headers and create libdrm.pc (needed for Zink/EGL)
    mkdir -p "${INSTALL_DIR}/include/libdrm"
    if [ -d "${KOSMICKRISP_DIR}/include/drm-uapi" ]; then
        cp "${KOSMICKRISP_DIR}/include/drm-uapi/"*.h "${INSTALL_DIR}/include/libdrm/"
        cp "${KOSMICKRISP_DIR}/include/drm-uapi/"*.h "${INSTALL_DIR}/include/"
    fi
    
    cat > "${INSTALL_DIR}/lib/pkgconfig/libdrm.pc" <<EOF
prefix=${INSTALL_DIR}
includedir=\${prefix}/include
libdir=\${prefix}/lib

Name: libdrm
Description: Userspace interface to kernel DRM services
Version: 2.4.110
Cflags: -I\${includedir} -I\${includedir}/libdrm
Libs: 
EOF
    
    # Disable things not working on iOS
    # Note: Many Meson checks will show "NO" for Linux-specific features (futex, prctl, etc.)
    # and optional dependencies (libudev, lua, valgrind, etc.). This is expected and harmless.
    # The build will work correctly without these features.
    MESON_EXTRA_ARGS=(
        "--cross-file" "${CROSS_FILE}"
        "-Dplatforms=macos,wayland"
        "-Dvulkan-drivers=kosmickrisp"
        "-Dgallium-drivers=[]"
        "-Dglx=disabled"
        "-Dgbm=disabled"
        "-Degl=disabled"
        "-Dopengl=false"
        "-Dgles1=disabled"
        "-Dgles2=disabled"
        "-Dglvnd=disabled"
        "-Dllvm=disabled"
        "-Dshared-llvm=disabled"
        "-Dbuild-tests=false"
        "-Dmesa-clc=auto"
        "-Dwerror=false"
        "-Dc_args=-isystem ${SDK_PATH}/usr/include -I${INSTALL_DIR}/include -target arm64-apple-ios15.0-simulator -isysroot ${SDK_PATH} -idirafter /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include -Wall -Wextra -Wpedantic -Wno-missing-field-initializers -Wno-declaration-after-statement -Wno-sign-conversion -Wno-shadow -Wno-switch-default -Wno-unused-parameter -Wno-implicit-int-conversion -Wno-cast-qual -Wno-nullability-completeness -Wno-nullability-extension -Wno-expansion-to-defined -Wno-unused-function -Wno-fixed-enum-extension -Wno-sign-compare -Wno-gnu-zero-variadic-macro-arguments -Wno-newline-eof -Wno-strict-prototypes -Wno-format-pedantic -Wno-empty-translation-unit -Wno-gnu-statement-expression-from-macro-expansion -Wno-extra-semi -Wno-pedantic -Wno-gnu-anonymous-struct -Wno-nested-anon-types -Wno-c99-extensions -Wno-zero-length-array -Wno-null-pointer-subtraction -Wno-unused-but-set-variable -fPIC -std=c17 -DHAVE_STRUCT_TIMESPEC -DVK_USE_PLATFORM_METAL_EXT -DVK_USE_PLATFORM_IOS_MVK"
        "-Dcpp_args=-isystem ${SDK_PATH}/usr/include/c++/v1 -isystem ${SDK_PATH}/usr/include -I${INSTALL_DIR}/include -target arm64-apple-ios15.0-simulator -isysroot ${SDK_PATH} -stdlib=libc++ -idirafter /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/usr/include -DHAVE_STRUCT_TIMESPEC -Wall -Wextra -Wpedantic -Wno-missing-field-initializers -Wno-nullability-completeness -Wno-nullability-extension -Wno-expansion-to-defined -Wno-gnu-zero-variadic-macro-arguments -Wno-newline-eof -Wno-format-pedantic -Wno-empty-translation-unit -Wno-sign-compare -Wno-error=gnu-anonymous-struct -Wno-error=nested-anon-types -Wno-gnu-anonymous-struct -Wno-nested-anon-types -Wno-c99-extensions -Wno-zero-length-array -Wno-gnu-statement-expression-from-macro-expansion -Wno-gnu-redeclared-enum -Wno-cast-function-type-mismatch -Wno-unused-but-set-parameter -Wno-null-pointer-subtraction -Wno-extra-semi -DVK_USE_PLATFORM_METAL_EXT -DVK_USE_PLATFORM_IOS_MVK"
        "-Dobjc_args=-I${INSTALL_DIR}/include -target arm64-apple-ios15.0-simulator -isysroot ${SDK_PATH} -Wall -Wextra -fPIC -Wno-nullability-completeness -Wno-nullability-extension -Wno-expansion-to-defined -Wno-gnu-zero-variadic-macro-arguments -Wno-newline-eof -Wno-format-pedantic -Wno-empty-translation-unit -Wno-gnu-redeclared-enum -Wno-unguarded-availability-new -Wno-unused-parameter"
        "-Dobjcpp_args=-I${INSTALL_DIR}/include -target arm64-apple-ios15.0-simulator -isysroot ${SDK_PATH} -stdlib=libc++"
    )
    
elif [ "${PLATFORM}" == "macos" ]; then
    INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
    BUILD_DIR="build-macos"
    
    export PKG_CONFIG_PATH="${INSTALL_DIR}/lib/pkgconfig:${INSTALL_DIR}/libdata/pkgconfig:$PKG_CONFIG_PATH"
    # Ensure llvm-config is available for mesa-clc detection
    if command -v brew >/dev/null 2>&1; then
        if [ -d "$(brew --prefix llvm@17 2>/dev/null)" ]; then
            export PATH="$(brew --prefix llvm@17)/bin:$PATH"
        elif [ -d "$(brew --prefix llvm@15 2>/dev/null)" ]; then
            export PATH="$(brew --prefix llvm@15)/bin:$PATH"
        elif [ -d "$(brew --prefix llvm 2>/dev/null)" ]; then
            export PATH="$(brew --prefix llvm)/bin:$PATH"
        fi
    fi
    
    MESON_EXTRA_ARGS=(
        "-Dplatforms=macos,wayland"
        "-Dvulkan-drivers=kosmickrisp"
        "-Dgallium-drivers=[]"
        "-Degl=disabled"
        "-Dopengl=false"
        "-Dgles1=disabled"
        "-Dgles2=disabled"
        "-Dglx=disabled"
        "-Dgbm=disabled"
        "-Dllvm=enabled"
        "-Dshared-llvm=enabled"
        "-Dmesa-clc=auto"
        "-Dbuild-tests=false"
        "-Dwerror=false"
        "-Dvulkan-layers=[]"
        "-Dtools=[]"
        "-Db_lto=false"
        "-Dc_link_args=-L${INSTALL_DIR}/lib"
        "-Dcpp_link_args=-L${INSTALL_DIR}/lib"
    )
else
    echo "Error: Unsupported platform '${PLATFORM}'"
    exit 1
fi

mkdir -p "${INSTALL_DIR}"

if [ ! -d "${KOSMICKRISP_DIR}" ]; then
    echo "Error: kosmickrisp not found"
    exit 1
fi

cd "${KOSMICKRISP_DIR}"

# Find MoltenVK (needed for both?)
MOLTENVK_DIR=""
if [ -d "$(brew --prefix molten-vk 2>/dev/null)" ]; then
    MOLTENVK_DIR=$(brew --prefix molten-vk)
elif [ -d "/opt/homebrew/opt/molten-vk" ]; then
    MOLTENVK_DIR="/opt/homebrew/opt/molten-vk"
elif [ -d "/usr/local/opt/molten-vk" ]; then
    MOLTENVK_DIR="/usr/local/opt/molten-vk"
fi

if [ -n "$MOLTENVK_DIR" ]; then
    MESON_EXTRA_ARGS+=("-Dmoltenvk-dir=${MOLTENVK_DIR}")
else
    echo "Warning: MoltenVK not found"
fi

echo "Configuring KosmicKrisp for ${PLATFORM}..."
rm -rf "${BUILD_DIR}"

meson setup "${BUILD_DIR}" \
    --prefix="${INSTALL_DIR}" \
    --default-library=static \
    "${MESON_EXTRA_ARGS[@]}"

echo "Building KosmicKrisp..."
ninja -C "${BUILD_DIR}"

echo "Installing KosmicKrisp..."
ninja -C "${BUILD_DIR}" install

# Install Vulkan headers and vk_video headers into INSTALL_DIR for downstream builds
echo "Installing Vulkan headers..."
mkdir -p "${INSTALL_DIR}/include/vulkan"
if [ -d "${KOSMICKRISP_DIR}/include/vulkan" ]; then
    cp -r "${KOSMICKRISP_DIR}/include/vulkan/"* "${INSTALL_DIR}/include/vulkan/"
fi
if [ -d "${KOSMICKRISP_DIR}/include/vk_video" ]; then
    echo "Installing Vulkan video headers..."
    mkdir -p "${INSTALL_DIR}/include/vulkan/vk_video"
    cp -r "${KOSMICKRISP_DIR}/include/vk_video/"* "${INSTALL_DIR}/include/vulkan/vk_video/"
fi

# Create framework (both platforms)
# Fix duplicate symbols in libvulkan_kosmickrisp.a (KosmicKrisp includes duplicate protocol files)
if [ -f "${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a" ]; then
    echo "Fixing duplicate symbols in libvulkan_kosmickrisp.a..."
    TMP_DIR=$(mktemp -d)
    cd "${TMP_DIR}"
    ar -x "${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a"
    # Remove duplicate presentation-time-protocol object file (loader version)
    if [ -f "meson-generated_.._.._.._loader_presentation-time-protocol.c.o" ]; then
        rm -f "meson-generated_.._.._.._loader_presentation-time-protocol.c.o"
        rm -f "${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a"
        ar rcs "${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a" *.o
        echo "Removed duplicate presentation-time-protocol object file"
    fi
    cd - > /dev/null
    rm -rf "${TMP_DIR}"
fi

if [ ! -f "${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a" ]; then
    echo "Creating static libvulkan_kosmickrisp.a from build objects..."
    TMP_AR_DIR=$(mktemp -d)
    find "${BUILD_DIR}/src/kosmickrisp/vulkan" -type f -name "*.o" -print0 | xargs -0 -I{} cp {} "${TMP_AR_DIR}" 2>/dev/null || true
    if ls "${TMP_AR_DIR}"/*.o >/dev/null 2>&1; then
        rm -f "${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a"
        ar rcs "${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a" "${TMP_AR_DIR}"/*.o || true
        echo "Created ${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a"
    else
        echo "Warning: No build objects found for KosmicKrisp Vulkan; static archive not created"
    fi
    rm -rf "${TMP_AR_DIR}"
fi

if [ -f "${INSTALL_DIR}/lib/libvulkan_kosmickrisp.a" ]; then
    echo "Packaging KosmicKrisp as framework..."
    "${ROOT_DIR}/scripts/create-kosmickrisp-framework.sh" --platform "${PLATFORM}"
fi

# Create EGL framework
if [ -f "${INSTALL_DIR}/lib/libEGL.a" ]; then
    echo "Creating EGL framework..."
    "${ROOT_DIR}/scripts/create-static-framework.sh" --platform "${PLATFORM}" --name "EGL" --libs "libEGL.a" --include-subdir "" --recursive-headers
fi

# Create GLESv2 framework
:

echo "Success! KosmicKrisp installed to ${INSTALL_DIR}"
