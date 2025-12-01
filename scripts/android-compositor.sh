#!/bin/bash

set -e
set -o pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK_ROOT="$HOME/Library/Android/sdk"
ANDROID_API=35
BUILD_TOOLS=35.0.0

# Force arm64-v8a architecture for Apple Silicon compatibility
ABI="arm64-v8a"

SYSTEM_IMAGE="system-images;android-${ANDROID_API};google_apis;${ABI}"
AVD_NAME="pixel3_adreno845"
DEPS_DIR="${ROOT_DIR}/android-dependencies"
MESA_DIR="${DEPS_DIR}/mesa"
TURNIP_DIR="${DEPS_DIR}/turnip"
BUILD_DIR="${ROOT_DIR}/build"

mkdir -p "${DEPS_DIR}" "${TURNIP_DIR}" "${BUILD_DIR}"

echo "Setting up Android SDK (root: ${SDK_ROOT}, ABI: ${ABI})"

# Install command line tools if missing
if ! command -v sdkmanager >/dev/null 2>&1 && [ ! -x "${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "Installing Android command line tools..."
  brew install --cask android-commandlinetools || true
fi

# Download and setup command line tools if not present
if [ ! -x "${SDK_ROOT}/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "Setting up Android command line tools..."
  mkdir -p "${SDK_ROOT}/cmdline-tools"
  curl -Lo commandlinetools-mac_latest.zip https://dl.google.com/android/repository/commandlinetools-mac_latest.zip
  unzip -q commandlinetools-mac_latest.zip -d "${SDK_ROOT}/cmdline-tools"
  mv "${SDK_ROOT}/cmdline-tools/cmdline-tools" "${SDK_ROOT}/cmdline-tools/latest"
  rm -f commandlinetools-mac_latest.zip
fi

export ANDROID_HOME="${SDK_ROOT}"
export ANDROID_SDK_ROOT="${SDK_ROOT}"
export PATH="${SDK_ROOT}/cmdline-tools/latest/bin:${SDK_ROOT}/platform-tools:${SDK_ROOT}/emulator:${PATH}"

# Accept licenses and install required packages
echo "Installing Android SDK packages..."
yes | sdkmanager --licenses || true
echo y | sdkmanager "platform-tools" "platforms;android-${ANDROID_API}" "build-tools;${BUILD_TOOLS}" "emulator" "cmdline-tools;latest" "cmake;3.22.1" "ndk;27.2.12479018"

# Install only arm64-v8a system image
echo "Installing arm64-v8a system image..."
echo y | sdkmanager "system-images;android-${ANDROID_API};google_apis;arm64-v8a"

# Install build dependencies
echo "Installing build dependencies..."
if ! command -v meson >/dev/null 2>&1; then
  brew install meson ninja pkg-config python3 glslang cmake vulkan-headers bison flex || true
fi

# Setup NDK
NDK_HOME=$(ls -d "${SDK_ROOT}/ndk"/* 2>/dev/null | tail -n 1)
if [ -z "${NDK_HOME}" ]; then 
  echo "NDK not installed"
  exit 2
fi

HOST_TAG=$( [ -d "${NDK_HOME}/toolchains/llvm/prebuilt/darwin-arm64" ] && echo darwin-arm64 || echo darwin-x86_64 )
TOOLCHAIN_DIR="${NDK_HOME}/toolchains/llvm/prebuilt/${HOST_TAG}"
SYSROOT_DIR="${TOOLCHAIN_DIR}/sysroot"

# Create cross-compilation configuration
echo "Setting up cross-compilation..."
mkdir -p "${DEPS_DIR}/cross"
cat > "${DEPS_DIR}/cross/aarch64-android.ini" <<EOF
[binaries]
c = '${TOOLCHAIN_DIR}/bin/clang'
cpp = '${TOOLCHAIN_DIR}/bin/clang++'
ar = '${TOOLCHAIN_DIR}/bin/llvm-ar'
strip = '${TOOLCHAIN_DIR}/bin/llvm-strip'
pkg-config = 'pkg-config'
[built-in options]
c_args = ['--target=aarch64-linux-android${ANDROID_API}','--sysroot=${SYSROOT_DIR}','-D__ANDROID_API__=${ANDROID_API}','-fPIC']
cpp_args = ['--target=aarch64-linux-android${ANDROID_API}','--sysroot=${SYSROOT_DIR}','-D__ANDROID_API__=${ANDROID_API}','-fPIC']
c_link_args = ['--target=aarch64-linux-android${ANDROID_API}','--sysroot=${SYSROOT_DIR}']
cpp_link_args = ['--target=aarch64-linux-android${ANDROID_API}','--sysroot=${SYSROOT_DIR}']
[properties]
needs_exe_wrapper = true
[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

# Clone and build Mesa (Turnip/Freedreno)
echo "Cloning Mesa (Turnip/Freedreno)..."
if [ ! -d "${MESA_DIR}" ]; then
  git clone --depth=1 https://gitlab.freedesktop.org/mesa/mesa.git "${MESA_DIR}"
else
  cd "${MESA_DIR}"
  git fetch origin
  git reset --hard origin/main
fi

# Build Mesa with Turnip Vulkan driver
echo "Building Turnip (Vulkan) + Freedreno (EGL)..."
BREW_PREFIX=$(brew --prefix 2>/dev/null || true)
PATH="${BREW_PREFIX}/opt/bison/bin:${BREW_PREFIX}/bin:${PATH}"
export CFLAGS="${CFLAGS} -DETIME=62"
export CXXFLAGS="${CXXFLAGS} -DETIME=62"

# Build Mesa
cd "${MESA_DIR}"
meson setup build-android --wrap-mode=nofallback --cross-file "${DEPS_DIR}/cross/aarch64-android.ini" \
  -Dplatforms=android -Dplatform-sdk-version="${ANDROID_API}" -Dvulkan-drivers=freedreno -Dandroid-stub=true \
  -Dandroid-libbacktrace=disabled -Degl=disabled -Dgallium-drivers= -Dfreedreno-kmds=kgsl \
  -Dzstd=disabled -Dspirv-tools=disabled -Ddefault_library=shared -Dbuildtype=release \
  --prefix="${TURNIP_DIR}" || true

ninja -C build-android install || true

# Check if build succeeded
FILES=$(find "${TURNIP_DIR}" -name 'libvulkan_freedreno*.so' | wc -l)
if [ "${FILES}" -eq 0 ]; then
  echo "Turnip build failed: libvulkan_freedreno not found"
  exit 2
fi

echo "Turnip build successful! Found ${FILES} Vulkan driver files."

# Prepare Vulkan drivers
mkdir -p "${TURNIP_DIR}/dist"
if ! command -v patchelf >/dev/null 2>&1; then 
  brew install patchelf || true
fi

cp "${TURNIP_DIR}/lib/libvulkan_freedreno.so" "${TURNIP_DIR}/dist/vulkan.adreno.so"
${BREW_PREFIX}/bin/patchelf --set-soname vulkan.adreno.so "${TURNIP_DIR}/dist/vulkan.adreno.so" || true

cp "${TURNIP_DIR}/lib/libvulkan_freedreno.so" "${TURNIP_DIR}/dist/vulkan.ranchu.so"
${BREW_PREFIX}/bin/patchelf --set-soname vulkan.ranchu.so "${TURNIP_DIR}/dist/vulkan.ranchu.so" || true

# Create Android app
echo "Creating and building Android app..."
bash "${ROOT_DIR}/scripts/create-android-app.sh"

# Build the app
cd "${ROOT_DIR}/build/android-app"
if [ ! -x "./gradlew" ]; then
  if ! command -v gradle >/dev/null 2>&1; then
    brew install gradle || true
  fi
  gradle wrapper
fi

./gradlew assembleDebug

# Clean up existing emulators and create fresh AVD
echo "Setting up Android emulator..."
# Kill any running emulators
adb devices | awk 'NR>1 && /emulator-/{print $1}' | xargs -I{} adb -s {} emu kill || true

# Clean up any x86_64 AVDs to avoid architecture conflicts
echo "Cleaning up x86_64 AVDs..."
avdmanager list avd | grep -A5 "x86_64" | grep "Name:" | awk '{print $2}' | while read avd; do
  echo "Deleting x86_64 AVD: $avd"
  avdmanager delete avd -n "$avd" || true
done || true

# Delete old AVD if it exists
avdmanager delete avd -n "${AVD_NAME}" >/dev/null 2>&1 || true

# Create new AVD with arm64-v8a architecture only
echo "Creating arm64-v8a AVD..."
echo no | avdmanager create avd -n "${AVD_NAME}" -k "${SYSTEM_IMAGE}" --device "pixel_3" || {
  echo "Failed to create AVD. Checking available system images..."
  sdkmanager --list_installed | grep system-images
  exit 1
}

# Start emulator
echo "Starting Android emulator..."
emulator -avd "${AVD_NAME}" -no-snapshot-load -gpu host -no-boot-anim &
EMULATOR_PID=$!

# Wait for emulator to boot
adb -e wait-for-device
until adb -e shell getprop sys.boot_completed | grep -m 1 "1"; do sleep 1; done

# Install and launch app
echo "Installing and launching Wawona Compositor..."
adb -e install -r "${ROOT_DIR}/build/android-app/app/build/outputs/apk/debug/app-debug.apk"
adb -e shell am start -n com.aspauldingcode.wawona/.MainActivity

echo "Android compositor build and launch complete!"
echo "Emulator PID: ${EMULATOR_PID}"
echo "App should be running on the emulator."