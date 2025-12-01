#!/bin/bash

# generate-cross-ios.sh
# Generates the Meson cross-compilation file for iOS

set -e

# Directories
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WAYLAND_DIR="${ROOT_DIR}/dependencies/wayland"
CROSS_FILE="${WAYLAND_DIR}/cross-ios.txt"
INSTALL_DIR="${ROOT_DIR}/ios-dependencies"
MACOS_INSTALL_DIR="${ROOT_DIR}/macos-dependencies"
HOST_TOOLS_DIR="${ROOT_DIR}/build/ios-bootstrap"

# SDK Path
SDK_PATH=$(xcrun --sdk iphonesimulator --show-sdk-path)

# Create Meson cross file
# Note: We expand INSTALL_DIR here since it's used in the cross file
EPOLL_SHIM_INCLUDE="${INSTALL_DIR}/include/libepoll-shim"
CMAKE_BIN="${HOST_TOOLS_DIR}/bin/cmake"
PKG_CONFIG_BIN="${HOST_TOOLS_DIR}/bin/pkg-config"

# Find toolchain tools
CLANG_BIN=$(xcrun -f clang)
CLANGXX_BIN=$(xcrun -f clang++)
AR_BIN=$(xcrun -f ar)
STRIP_BIN=$(xcrun -f strip)

# Fallback to system tools if host tools not present
if [ ! -x "${CMAKE_BIN}" ]; then CMAKE_BIN="cmake"; fi
# if [ ! -x "${PKG_CONFIG_BIN}" ]; then PKG_CONFIG_BIN="pkg-config"; fi
# Force use of PATH lookup for pkg-config to avoid Meson issues
PKG_CONFIG_BIN="pkg-config"
WAYLAND_SCANNER_BIN="${HOST_TOOLS_DIR}/bin/wayland-scanner"

cat > "${CROSS_FILE}" <<EOF
[binaries]
c = ['${CLANG_BIN}']
cpp = ['${CLANGXX_BIN}']
objc = ['${CLANG_BIN}']
objcpp = ['${CLANGXX_BIN}']
ar = ['${AR_BIN}']
strip = ['${STRIP_BIN}']
pkg-config = ['${PKG_CONFIG_BIN}']
cmake = ['${CMAKE_BIN}']
wayland-scanner = ['${WAYLAND_SCANNER_BIN}']

[properties]
needs_exe_wrapper = true
# sys_root = '${SDK_PATH}'
pkg_config_libdir = ['${INSTALL_DIR}/lib/pkgconfig', '${INSTALL_DIR}/libdata/pkgconfig', '${INSTALL_DIR}/share/pkgconfig']


[built-in options]
# Note: -Werror not included here for third-party dependencies which may have warnings
# Wawona code uses -Werror via CMakeLists.txt
c_args = ['-arch', 'arm64', '-isysroot', '${SDK_PATH}', '-mios-simulator-version-min=15.0', '-I${EPOLL_SHIM_INCLUDE}', '-Wall', '-Wextra', '-Wpedantic', '-Wno-error', '-Wstrict-prototypes', '-Wmissing-prototypes', '-Wold-style-definition', '-Wmissing-declarations', '-Wuninitialized', '-Winit-self', '-Wpointer-arith', '-Wno-cast-qual', '-Wwrite-strings', '-Wno-conversion', '-Wno-sign-conversion', '-Wformat=2', '-Wformat-security', '-Wundef', '-Wshadow', '-Wstrict-overflow=5', '-Wno-switch-default', '-Wno-switch-enum', '-Wunreachable-code', '-Wfloat-equal', '-Wstack-protector', '-fstack-protector-strong', '-Wno-shorten-64-to-32', '-Wno-incompatible-pointer-types-discards-qualifiers', '-Wno-format-nonliteral', '-fPIC', '-std=gnu17']
cpp_args = ['-arch', 'arm64', '-isysroot', '${SDK_PATH}', '-mios-simulator-version-min=15.0', '-Wall', '-Wextra', '-Wpedantic', '-Wno-error', '-Wuninitialized', '-Winit-self', '-Wpointer-arith', '-Wcast-qual', '-Wformat=2', '-Wformat-security', '-Wundef', '-Wshadow', '-Wstack-protector', '-fstack-protector-strong', '-fPIC', '-std=gnu++17']
c_link_args = ['-arch', 'arm64', '-isysroot', '${SDK_PATH}', '-mios-simulator-version-min=15.0']
cpp_link_args = ['-arch', 'arm64', '-isysroot', '${SDK_PATH}', '-mios-simulator-version-min=15.0']

[host_machine]
system = 'darwin'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

echo "Generated cross-file at ${CROSS_FILE}"

# Create CMake toolchain file
CMAKE_TOOLCHAIN_FILE="${WAYLAND_DIR}/toolchain-ios.cmake"

cat > "${CMAKE_TOOLCHAIN_FILE}" <<EOF
set(CMAKE_SYSTEM_NAME iOS)
set(CMAKE_OSX_SYSROOT "${SDK_PATH}")
set(CMAKE_OSX_ARCHITECTURES "arm64")
set(CMAKE_OSX_DEPLOYMENT_TARGET "15.0")

# Compilers
set(CMAKE_C_COMPILER "${CLANG_BIN}")
set(CMAKE_CXX_COMPILER "${CLANGXX_BIN}")
set(CMAKE_AR "${AR_BIN}")
set(CMAKE_STRIP "${STRIP_BIN}")

# Pkg-config
set(PKG_CONFIG_EXECUTABLE "${PKG_CONFIG_BIN}")

# Flags
set(COMMON_FLAGS "-arch arm64 -isysroot ${SDK_PATH} -mios-simulator-version-min=15.0")
set(CMAKE_C_FLAGS "\${COMMON_FLAGS} -I${EPOLL_SHIM_INCLUDE} -Wall -Wextra -Wpedantic -Wno-error -fPIC")
set(CMAKE_CXX_FLAGS "\${COMMON_FLAGS} -Wall -Wextra -Wpedantic -Wno-error -fPIC")

# Search paths
set(CMAKE_FIND_ROOT_PATH "${INSTALL_DIR}")
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF

echo "Generated CMake toolchain file at ${CMAKE_TOOLCHAIN_FILE}"
