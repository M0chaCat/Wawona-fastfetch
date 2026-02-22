{
  lib,
  pkgs,
  buildModule,
  wawonaSrc,
  wawonaVersion ? null,
  androidSDK ? null,
  rustBackend ? null,
  glslang ? pkgs.glslang,
}:

let
  common = import ./common.nix { inherit lib pkgs wawonaSrc; };

  androidToolchain = import ../toolchains/android.nix { inherit lib pkgs; };
  
  gradleDeps = pkgs.callPackage ../gradle-deps.nix {
    inherit wawonaSrc androidSDK;
    inherit (pkgs) gradle jdk17;
    inherit gradlegen;
  };

  gradlegen = pkgs.callPackage ../generators/gradlegen.nix { };

  westonSimpleShmSrc = pkgs.callPackage ../libs/weston-simple-shm/patched-src.nix {};

  projectVersion =
    if (wawonaVersion != null && wawonaVersion != "") then wawonaVersion
    else
      let v = lib.removeSuffix "\n" (lib.fileContents (wawonaSrc + "/VERSION"));
      in if v == "" then "0.0.1" else v;

  opensshBin = buildModule.buildForAndroid "openssh" { };
  sshpassBin = buildModule.buildForAndroid "sshpass" { };

  androidDeps = common.commonDeps ++ [
    "swiftshader"
    "pixman"
    "libwayland"
    "expat"
    "libffi"
    "libxml2"
    "xkbcommon"
    "openssl"
  ];

  getDeps =
    platform: depNames:
    map (
      name:
      if name == "pixman" then
        if platform == "android" then
          buildModule.android.pixman
        else
          pkgs.pixman
      else if name == "vulkan-headers" then
        pkgs.vulkan-headers
      else if name == "vulkan-loader" then
        pkgs.vulkan-loader
      else if name == "xkbcommon" then
        buildModule.${platform}.${name}
      else if name == "openssl" then
        buildModule.${platform}.${name}
      else if name == "libssh2" then
        buildModule.${platform}.${name}
      else
        buildModule.${platform}.${name}
    ) depNames;

  # Filter commonSources for Android: remove .m files and Apple-only headers
  androidCommonSources =
    lib.filter (
      f:
      !(lib.hasSuffix ".m" f)
      && f != "src/compositor_implementations/wayland_color_management.c"
      && f != "src/compositor_implementations/wayland_color_management.h"
      && f != "src/stubs/egl_buffer_handler.h"
      && f != "src/core/main.m"
    ) common.commonSources;

  # Android-specific sources (not filtered by pathExists since some are
  # generated at build time by postPatch)
  androidExtraSources = [
    "src/stubs/egl_buffer_handler.c"
    "src/platform/android/android_jni.c"
    "src/platform/android/input_android.c"
    "src/rendering/renderer_android.c"
    "src/rendering/renderer_android.h"
  ];

  androidSourcesFiltered = (common.filterSources androidCommonSources) ++ androidExtraSources;

  nixSdkPath = lib.makeBinPath [
    androidSDK.platform-tools
    androidSDK.emulator
    androidSDK.androidsdk
    pkgs.util-linux
  ];

  nixSdkRoot = "${androidSDK.androidsdk}/libexec/android-sdk";

  runnerScript = pkgs.writeShellScript "wawona-android-run" ''
    set +e

    NIX_SDK_PATH="${nixSdkPath}"
    export PATH="$NIX_SDK_PATH:$PATH"
    export ANDROID_SDK_ROOT="${nixSdkRoot}"
    export ANDROID_HOME="$ANDROID_SDK_ROOT"

    USE_SYSTEM_SDK=false
    if [ "$(uname -m)" = "arm64" ] && [ "$(uname -s)" = "Darwin" ]; then
      echo "[Wawona] Detected Apple Silicon (arm64) macOS"
      SYSTEM_SDK="$HOME/Library/Android/sdk"
      if [ -d "$SYSTEM_SDK/emulator" ] && [ -f "$SYSTEM_SDK/emulator/emulator" ]; then
        echo "[Wawona] Using system Android SDK emulator (arm64 native)"
        export PATH="$SYSTEM_SDK/emulator:$SYSTEM_SDK/platform-tools:$SYSTEM_SDK/cmdline-tools/latest/bin:$NIX_SDK_PATH:$PATH"
        export ANDROID_SDK_ROOT="$SYSTEM_SDK"
        export ANDROID_HOME="$SYSTEM_SDK"
        USE_SYSTEM_SDK=true
      else
        echo "[Wawona] WARNING: No arm64 Android emulator found."
        echo "[Wawona] Install Android Studio or Android command-line tools for arm64."
        echo "[Wawona] The Nix-provided emulator is x86_64 and requires Rosetta 2."
      fi
    fi

    APK_PATH="$1"
    if [ -z "$APK_PATH" ]; then
      APK_PATH="$(dirname "$0")/Wawona.apk"
    fi

    if [ ! -f "$APK_PATH" ]; then
      echo "[Wawona] ERROR: APK not found at $APK_PATH"
      exit 1
    fi
    echo "[Wawona] APK: $APK_PATH"

    if ! command -v adb >/dev/null 2>&1; then
      echo "[Wawona] ERROR: adb not found in PATH"
      exit 1
    fi

    if ! command -v emulator >/dev/null 2>&1; then
      echo "[Wawona] ERROR: emulator not found in PATH"
      exit 1
    fi

    echo "[Wawona] Using emulator: $(which emulator)"
    echo "[Wawona] Using adb: $(which adb)"

    export ANDROID_USER_HOME="$(pwd)/.android_home"
    export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"
    mkdir -p "$ANDROID_AVD_HOME"

    AVD_NAME="WawonaEmulator"

    SYSTEM_IMAGE=""
    if [ "$USE_SYSTEM_SDK" = "true" ]; then
      SYS_IMG_DIR="$ANDROID_SDK_ROOT/system-images"
      for api_dir in android-36.1 android-36 android-35; do
        if [ -d "$SYS_IMG_DIR/$api_dir/google_apis_playstore/arm64-v8a" ]; then
          SYSTEM_IMAGE="system-images;$api_dir;google_apis_playstore;arm64-v8a"
          AVD_NAME="WawonaEmulator_$(echo $api_dir | tr '.' '_' | tr '-' '_')"
          echo "[Wawona] Found system image: $SYSTEM_IMAGE"
          break
        elif [ -d "$SYS_IMG_DIR/$api_dir/google_apis/arm64-v8a" ]; then
          SYSTEM_IMAGE="system-images;$api_dir;google_apis;arm64-v8a"
          AVD_NAME="WawonaEmulator_$(echo $api_dir | tr '.' '_' | tr '-' '_')"
          echo "[Wawona] Found system image: $SYSTEM_IMAGE"
          break
        fi
      done
      if [ -z "$SYSTEM_IMAGE" ]; then
        echo "[Wawona] ERROR: No compatible system image found in $SYS_IMG_DIR"
        echo "[Wawona] Please install a system image via Android Studio."
        exit 1
      fi
    else
      SYSTEM_IMAGE="system-images;android-36;google_apis_playstore;arm64-v8a"
      AVD_NAME="WawonaEmulator_API36"
    fi

    echo "[Wawona] AVD: $AVD_NAME"

    if ! emulator -list-avds 2>/dev/null | grep -q "^$AVD_NAME$"; then
      if [ "$USE_SYSTEM_SDK" = "true" ]; then
        echo "[Wawona] Creating AVD '$AVD_NAME' manually for system SDK..."
        AVD_DIR="$ANDROID_AVD_HOME/$AVD_NAME.avd"
        mkdir -p "$AVD_DIR"

        IFS=';' read -r _ SYS_API SYS_TYPE SYS_ABI <<< "$SYSTEM_IMAGE"
        SYS_IMG_REL="system-images/$SYS_API/$SYS_TYPE/$SYS_ABI/"

        printf '%s\n' \
          "avd.ini.encoding=UTF-8" \
          "path=$AVD_DIR" \
          "path.rel=avd/$AVD_NAME.avd" \
          "target=$SYS_API" \
          > "$ANDROID_AVD_HOME/$AVD_NAME.ini"

        printf '%s\n' \
          "AvdId=$AVD_NAME" \
          "PlayStore.enabled=true" \
          "abi.type=$SYS_ABI" \
          "avd.ini.displayname=Wawona Emulator" \
          "avd.ini.encoding=UTF-8" \
          "disk.dataPartition.size=6442450944" \
          "hw.accelerometer=yes" \
          "hw.arc=false" \
          "hw.audioInput=yes" \
          "hw.battery=yes" \
          "hw.camera.back=virtualscene" \
          "hw.camera.front=emulated" \
          "hw.cpu.arch=arm64" \
          "hw.cpu.ncore=4" \
          "hw.dPad=no" \
          "hw.device.manufacturer=Google" \
          "hw.device.name=pixel_9" \
          "hw.gps=yes" \
          "hw.gpu.enabled=yes" \
          "hw.gpu.mode=auto" \
          "hw.keyboard=yes" \
          "hw.lcd.density=420" \
          "hw.lcd.height=2424" \
          "hw.lcd.width=1080" \
          "hw.mainKeys=no" \
          "hw.ramSize=4096" \
          "hw.sdCard=yes" \
          "hw.sensors.orientation=yes" \
          "hw.sensors.proximity=yes" \
          "hw.trackBall=no" \
          "image.sysdir.1=$SYS_IMG_REL" \
          "tag.display=Google Play" \
          "tag.id=$SYS_TYPE" \
          > "$AVD_DIR/config.ini"

        echo "[Wawona] AVD created at $AVD_DIR"
      elif command -v avdmanager >/dev/null 2>&1; then
        echo "[Wawona] Creating AVD '$AVD_NAME' with avdmanager..."
        echo "no" | avdmanager create avd -n "$AVD_NAME" -k "$SYSTEM_IMAGE" --device "pixel_9" --force
      else
        echo "[Wawona] ERROR: Cannot create AVD."
        exit 1
      fi
    fi

    for old_avd in "$ANDROID_AVD_HOME"/WawonaEmulator_API36.avd "$ANDROID_AVD_HOME"/WawonaEmulator_API36.ini; do
      [ -e "$old_avd" ] && rm -rf "$old_avd"
    done

    adb start-server 2>/dev/null

    EMULATOR_PROCESS=$(pgrep -f "qemu.*$AVD_NAME" 2>/dev/null | head -n 1)

    if [ -n "$EMULATOR_PROCESS" ]; then
      sleep 2
      RUNNING_EMULATORS=$(adb devices | grep -E "emulator-[0-9]+" | grep "device$" | wc -l | tr -d ' ')
      if [ "$RUNNING_EMULATORS" -eq 0 ]; then
        if kill -0 "$EMULATOR_PROCESS" 2>/dev/null; then
          sleep 3
          RUNNING_EMULATORS=$(adb devices | grep -E "emulator-[0-9]+" | grep "device$" | wc -l | tr -d ' ')
        else
          EMULATOR_PROCESS=""
        fi
      fi
    else
      RUNNING_EMULATORS=$(adb devices | grep -E "emulator-[0-9]+" | grep "device$" | wc -l | tr -d ' ')
    fi

    if [ "$RUNNING_EMULATORS" -gt 0 ]; then
      EMULATOR_SERIAL=$(adb devices | grep -E "emulator-[0-9]+" | grep "device$" | head -n 1 | awk '{print $1}')
      echo "[Wawona] Reusing running emulator: $EMULATOR_SERIAL"
    else
      echo "[Wawona] Starting emulator '$AVD_NAME'..."
      setsid nohup emulator -avd "$AVD_NAME" -no-snapshot-load -gpu auto < /dev/null >>/tmp/emulator.log 2>&1 &

      sleep 3

      EMULATOR_PID=""
      for i in 1 2 3 4 5; do
        EMULATOR_PID=$(pgrep -f "qemu.*$AVD_NAME" 2>/dev/null | head -n 1)
        if [ -n "$EMULATOR_PID" ]; then
          break
        fi
        sleep 1
      done

      if [ -z "$EMULATOR_PID" ]; then
        echo "[Wawona] Warning: Could not find emulator PID"
      fi

      cleanup() {
        exit 0
      }
      trap cleanup SIGTERM SIGINT

      TIMEOUT=300
      ELAPSED=0
      BOOTED=false

      while [ $ELAPSED -lt $TIMEOUT ]; do
        if [ -n "$EMULATOR_PID" ] && ! kill -0 $EMULATOR_PID 2>/dev/null; then
           if ! adb devices | grep -E "emulator-[0-9]+" | grep -q "device$"; then
             cat /tmp/emulator.log 2>/dev/null
             exit 1
           fi
        fi

        if adb devices | grep -E "emulator-[0-9]+" | grep -q "device$"; then
          sleep 2
          BOOT_COMPLETE=$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || echo "0")
          if [ "$BOOT_COMPLETE" = "1" ]; then
            BOOTED=true
            break
          fi
        fi

        sleep 2
        ELAPSED=$((ELAPSED + 2))
      done

      if [ "$BOOTED" = "true" ]; then
        sleep 5
      else
        if adb devices | grep -E "emulator-[0-9]+" | grep -q "device$"; then
          BOOTED=true
        else
          cat /tmp/emulator.log 2>/dev/null
          exit 1
        fi
      fi

      trap - SIGTERM SIGINT
    fi

    graceful_exit() {
      echo ""
      echo "[Wawona] Script terminated. Emulator continues running in background."
      exit 0
    }
    trap graceful_exit SIGTERM SIGINT

    adb logcat -c 2>/dev/null || true

    echo "[Wawona] Installing APK (preserving app data)..."
    if ! adb install -r "$APK_PATH" 2>/dev/null; then
      echo "[Wawona] Upgrade install failed (signature mismatch?). Performing clean install..."
      adb uninstall com.aspauldingcode.wawona 2>/dev/null || true
      adb install "$APK_PATH"
    fi

    echo "[Wawona] Launching Wawona..."
    adb shell am start -n com.aspauldingcode.wawona/.MainActivity

    sleep 5

    echo "=== Recent crash logs ==="
    adb logcat -d -v time | grep -i -E "(wawona|androidruntime|fatal|exception|error)" | tail -200

    echo ""
    echo "=== Starting live logcat stream ==="
    adb logcat -v time -s Wawona:D WawonaJNI:D WawonaNative:D AndroidRuntime:E
  '';

in
  pkgs.stdenv.mkDerivation rec {
    name = "wawona-android";
    version = projectVersion;
    src = wawonaSrc;

    outputs = [ "out" "project" ];

    # Skip fixup phase - Android binaries can't execute on macOS
    dontFixup = true;

    nativeBuildInputs = with pkgs; [
      clang
      pkg-config
      jdk17 # Full JDK needed for Gradle
      gradle
      unzip
      zip
      patchelf
      file
      util-linux # Provides setsid for creating new process groups
      glslang # For compiling Vulkan shaders to SPIR-V
    ];

    buildInputs = (getDeps "android" androidDeps) ++ [
      pkgs.mesa
    ];

    # Ensure input_android, shaders exist (untracked or filtered by flake)
    prePatch = ''
      mkdir -p src/platform/android
      mkdir -p src/rendering/shaders
      if [ ! -f src/platform/android/input_android.h ]; then
        cat > src/platform/android/input_android.h <<'INPUT_H'
#pragma once

#include <stdint.h>

uint32_t android_keycode_to_linux(uint32_t android_keycode);
INPUT_H
      fi
      if [ ! -f src/platform/android/input_android.c ]; then
        cat > src/platform/android/input_android.c <<'INPUT_C'
/**
 * Android input helpers - keycode mapping and modifier tracking
 *
 * Maps Android KeyEvent keycodes to Linux evdev/XKB keycodes.
 * Android keycodes are similar but not identical to Linux.
 */

#include "input_android.h"
#include <stdint.h>

/* Linux evdev key codes (from input-event-codes.h) */
#define KEY_RESERVED        0
#define KEY_ESC             1
#define KEY_1               2
#define KEY_2               3
#define KEY_3               4
#define KEY_4               5
#define KEY_5               6
#define KEY_6               7
#define KEY_7               8
#define KEY_8               9
#define KEY_9               10
#define KEY_0               11
#define KEY_MINUS           12
#define KEY_EQUAL           13
#define KEY_BACKSPACE       14
#define KEY_TAB             15
#define KEY_Q               16
#define KEY_W               17
#define KEY_E               18
#define KEY_R               19
#define KEY_T               20
#define KEY_Y               21
#define KEY_U               22
#define KEY_I               23
#define KEY_O               24
#define KEY_P               25
#define KEY_LEFTBRACE       26
#define KEY_RIGHTBRACE      27
#define KEY_ENTER           28
#define KEY_LEFTCTRL        29
#define KEY_A               30
#define KEY_S               31
#define KEY_D               32
#define KEY_F               33
#define KEY_G               34
#define KEY_H               35
#define KEY_J               36
#define KEY_K               37
#define KEY_L               38
#define KEY_SEMICOLON       39
#define KEY_APOSTROPHE      40
#define KEY_GRAVE           41
#define KEY_LEFTSHIFT       42
#define KEY_BACKSLASH       43
#define KEY_Z               44
#define KEY_X               45
#define KEY_C               46
#define KEY_V               47
#define KEY_B               48
#define KEY_N               49
#define KEY_M               50
#define KEY_COMMA           51
#define KEY_DOT             52
#define KEY_SLASH           53
#define KEY_RIGHTSHIFT      54
#define KEY_LEFTALT         56
#define KEY_SPACE           57
#define KEY_RIGHTALT        100
#define KEY_RIGHTCTRL       97
#define KEY_LEFTMETA        125
#define KEY_RIGHTMETA       126
#define KEY_DELETE          111
#define KEY_FORWARD_DEL     119
#define KEY_HOME            102
#define KEY_END             107
#define KEY_INSERT          110
#define KEY_PAGEUP          104
#define KEY_PAGEDOWN        109
#define KEY_UP              103
#define KEY_DOWN            108
#define KEY_LEFT            105
#define KEY_RIGHT           106

/* Android KeyEvent keycodes - same values as in android/view/KeyEvent.java */
#define AKEYCODE_SOFT_LEFT       1
#define AKEYCODE_SOFT_RIGHT     2
#define AKEYCODE_HOME           3
#define AKEYCODE_BACK           4
#define AKEYCODE_CALL           5
#define AKEYCODE_ENDCALL        6
#define AKEYCODE_0              7
#define AKEYCODE_1              8
#define AKEYCODE_2              9
#define AKEYCODE_3              10
#define AKEYCODE_4              11
#define AKEYCODE_5              12
#define AKEYCODE_6              13
#define AKEYCODE_7              14
#define AKEYCODE_8              15
#define AKEYCODE_9              16
#define AKEYCODE_STAR           17
#define AKEYCODE_POUND          18
#define AKEYCODE_DPAD_UP        19
#define AKEYCODE_DPAD_DOWN      20
#define AKEYCODE_DPAD_LEFT      21
#define AKEYCODE_DPAD_RIGHT     22
#define AKEYCODE_DPAD_CENTER    23
#define AKEYCODE_VOLUME_UP      24
#define AKEYCODE_VOLUME_DOWN    25
#define AKEYCODE_POWER          26
#define AKEYCODE_CAMERA         27
#define AKEYCODE_CLEAR          28
#define AKEYCODE_A              29
#define AKEYCODE_B              30
#define AKEYCODE_C              31
#define AKEYCODE_D              32
#define AKEYCODE_E              33
#define AKEYCODE_F              34
#define AKEYCODE_G              35
#define AKEYCODE_H              36
#define AKEYCODE_I              37
#define AKEYCODE_J              38
#define AKEYCODE_K              39
#define AKEYCODE_L              40
#define AKEYCODE_M              41
#define AKEYCODE_N              42
#define AKEYCODE_O              43
#define AKEYCODE_P              44
#define AKEYCODE_Q              45
#define AKEYCODE_R              46
#define AKEYCODE_S              47
#define AKEYCODE_T              48
#define AKEYCODE_U              49
#define AKEYCODE_V              50
#define AKEYCODE_W              51
#define AKEYCODE_X              52
#define AKEYCODE_Y              53
#define AKEYCODE_Z              54
#define AKEYCODE_COMMA          55
#define AKEYCODE_PERIOD         56
#define AKEYCODE_ALT_LEFT       57
#define AKEYCODE_ALT_RIGHT      58
#define AKEYCODE_SHIFT_LEFT     59
#define AKEYCODE_SHIFT_RIGHT    60
#define AKEYCODE_TAB            61
#define AKEYCODE_SPACE          62
#define AKEYCODE_SYMBOL         63
#define AKEYCODE_EXPLORER       64
#define AKEYCODE_ENVELOPE       65
#define AKEYCODE_ENTER          66
#define AKEYCODE_DEL            67
#define AKEYCODE_GRAVE          68
#define AKEYCODE_MINUS          69
#define AKEYCODE_EQUALS         70
#define AKEYCODE_LEFT_BRACKET   71
#define AKEYCODE_RIGHT_BRACKET  72
#define AKEYCODE_BACKSLASH      73
#define AKEYCODE_SEMICOLON      74
#define AKEYCODE_APOSTROPHE     75
#define AKEYCODE_SLASH          76
#define AKEYCODE_AT             77
#define AKEYCODE_NUM            78
#define AKEYCODE_HEADPHONEHOOK  79
#define AKEYCODE_FOCUS          80
#define AKEYCODE_PLUS           81
#define AKEYCODE_MENU           82
#define AKEYCODE_NOTIFICATION   83
#define AKEYCODE_SEARCH         84
#define AKEYCODE_DPAD_UP_2      85
#define AKEYCODE_DPAD_DOWN_2    86
#define AKEYCODE_DPAD_LEFT_2    87
#define AKEYCODE_DPAD_RIGHT_2   88
#define AKEYCODE_DPAD_CENTER_2  89
#define AKEYCODE_CTRL_LEFT      113
#define AKEYCODE_CTRL_RIGHT     114
#define AKEYCODE_ESCAPE         111
#define AKEYCODE_FORWARD_DEL    112
#define AKEYCODE_META_LEFT      117
#define AKEYCODE_META_RIGHT     118

uint32_t android_keycode_to_linux(uint32_t android_keycode) {
    switch (android_keycode) {
    case AKEYCODE_A: return KEY_A;
    case AKEYCODE_B: return KEY_B;
    case AKEYCODE_C: return KEY_C;
    case AKEYCODE_D: return KEY_D;
    case AKEYCODE_E: return KEY_E;
    case AKEYCODE_F: return KEY_F;
    case AKEYCODE_G: return KEY_G;
    case AKEYCODE_H: return KEY_H;
    case AKEYCODE_I: return KEY_I;
    case AKEYCODE_J: return KEY_J;
    case AKEYCODE_K: return KEY_K;
    case AKEYCODE_L: return KEY_L;
    case AKEYCODE_M: return KEY_M;
    case AKEYCODE_N: return KEY_N;
    case AKEYCODE_O: return KEY_O;
    case AKEYCODE_P: return KEY_P;
    case AKEYCODE_Q: return KEY_Q;
    case AKEYCODE_R: return KEY_R;
    case AKEYCODE_S: return KEY_S;
    case AKEYCODE_T: return KEY_T;
    case AKEYCODE_U: return KEY_U;
    case AKEYCODE_V: return KEY_V;
    case AKEYCODE_W: return KEY_W;
    case AKEYCODE_X: return KEY_X;
    case AKEYCODE_Y: return KEY_Y;
    case AKEYCODE_Z: return KEY_Z;
    case AKEYCODE_0: return KEY_0;
    case AKEYCODE_1: return KEY_1;
    case AKEYCODE_2: return KEY_2;
    case AKEYCODE_3: return KEY_3;
    case AKEYCODE_4: return KEY_4;
    case AKEYCODE_5: return KEY_5;
    case AKEYCODE_6: return KEY_6;
    case AKEYCODE_7: return KEY_7;
    case AKEYCODE_8: return KEY_8;
    case AKEYCODE_9: return KEY_9;
    case AKEYCODE_CTRL_LEFT:  return KEY_LEFTCTRL;
    case AKEYCODE_CTRL_RIGHT: return KEY_RIGHTCTRL;
    case AKEYCODE_SHIFT_LEFT: return KEY_LEFTSHIFT;
    case AKEYCODE_SHIFT_RIGHT: return KEY_RIGHTSHIFT;
    case AKEYCODE_ALT_LEFT:   return KEY_LEFTALT;
    case AKEYCODE_ALT_RIGHT:  return KEY_RIGHTALT;
    case AKEYCODE_META_LEFT:  return KEY_LEFTMETA;
    case AKEYCODE_META_RIGHT: return KEY_RIGHTMETA;
    case AKEYCODE_DPAD_UP:
    case AKEYCODE_DPAD_UP_2:  return KEY_UP;
    case AKEYCODE_DPAD_DOWN:
    case AKEYCODE_DPAD_DOWN_2: return KEY_DOWN;
    case AKEYCODE_DPAD_LEFT:
    case AKEYCODE_DPAD_LEFT_2: return KEY_LEFT;
    case AKEYCODE_DPAD_RIGHT:
    case AKEYCODE_DPAD_RIGHT_2: return KEY_RIGHT;
    case AKEYCODE_ENTER:
    case AKEYCODE_DPAD_CENTER:
    case AKEYCODE_DPAD_CENTER_2: return KEY_ENTER;
    case AKEYCODE_TAB:  return KEY_TAB;
    case AKEYCODE_SPACE: return KEY_SPACE;
    case AKEYCODE_ESCAPE: return KEY_ESC;
    case AKEYCODE_DEL: return KEY_BACKSPACE;
    case AKEYCODE_FORWARD_DEL: return KEY_DELETE;
    case AKEYCODE_HOME: return KEY_HOME;
    case AKEYCODE_ENDCALL: return KEY_END;
    case AKEYCODE_COMMA: return KEY_COMMA;
    case AKEYCODE_PERIOD: return KEY_DOT;
    case AKEYCODE_SLASH: return KEY_SLASH;
    case AKEYCODE_MINUS: return KEY_MINUS;
    case AKEYCODE_EQUALS: return KEY_EQUAL;
    case AKEYCODE_LEFT_BRACKET: return KEY_LEFTBRACE;
    case AKEYCODE_RIGHT_BRACKET: return KEY_RIGHTBRACE;
    case AKEYCODE_BACKSLASH: return KEY_BACKSLASH;
    case AKEYCODE_SEMICOLON: return KEY_SEMICOLON;
    case AKEYCODE_APOSTROPHE: return KEY_APOSTROPHE;
    case AKEYCODE_GRAVE: return KEY_GRAVE;
    default:
        return android_keycode;
    }
}
INPUT_C
      fi
      if [ ! -f src/rendering/shaders/android_quad.vert ]; then
        cat > src/rendering/shaders/android_quad.vert <<'SHADER_VERT'
#version 450

layout(location = 0) in vec2 inPosition;
layout(location = 1) in vec2 inTexCoord;

layout(location = 0) out vec2 fragTexCoord;

layout(push_constant) uniform PushConstants {
    float pos_x;
    float pos_y;
    float size_x;
    float size_y;
    float extent_x;
    float extent_y;
    float opacity;
    float _pad;
} pc;

void main() {
    float ndc_x = (pc.pos_x + inPosition.x * pc.size_x) / pc.extent_x * 2.0 - 1.0;
    float ndc_y = 1.0 - (pc.pos_y + inPosition.y * pc.size_y) / pc.extent_y * 2.0;
    gl_Position = vec4(ndc_x, ndc_y, 0.0, 1.0);
    fragTexCoord = inTexCoord;
}
SHADER_VERT
      fi
      if [ ! -f src/rendering/shaders/android_quad.frag ]; then
        cat > src/rendering/shaders/android_quad.frag <<'SHADER_FRAG'
#version 450

layout(location = 0) in vec2 fragTexCoord;

layout(location = 0) out vec4 outColor;

layout(binding = 0) uniform sampler2D texSampler;

layout(push_constant) uniform PushConstants {
    float pos_x;
    float pos_y;
    float size_x;
    float size_y;
    float extent_x;
    float extent_y;
    float opacity;
    float _pad;
} pc;

void main() {
    outColor = texture(texSampler, fragTexCoord) * pc.opacity;
}
SHADER_FRAG
      fi
      # ScreencopyHelper.kt may be untracked
      if [ ! -f src/platform/android/java/com/aspauldingcode/wawona/ScreencopyHelper.kt ]; then
        mkdir -p src/platform/android/java/com/aspauldingcode/wawona
        cat > src/platform/android/java/com/aspauldingcode/wawona/ScreencopyHelper.kt <<'SCREENCOPY'
package com.aspauldingcode.wawona

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.Window
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import java.nio.ByteBuffer

object ScreencopyHelper {
    suspend fun pollAndCapture(window: Window?) {
        if (window == null) return
        withContext(Dispatchers.Main) {
            pollOne(window, true)
            pollOne(window, false)
        }
    }
    private suspend fun pollOne(window: Window, screencopy: Boolean) {
        val whs = IntArray(3)
        val captureId = if (screencopy) {
            WawonaNative.nativeGetPendingScreencopy(whs)
        } else {
            WawonaNative.nativeGetPendingImageCopyCapture(whs)
        }
        if (captureId == 0L) return
        val width = whs[0]
        val height = whs[1]
        val dstStride = if (whs.size >= 3 && whs[2] > 0) whs[2] else width * 4
        if (width <= 0 || height <= 0) {
            if (screencopy) WawonaNative.nativeScreencopyFailed(captureId)
            else WawonaNative.nativeImageCopyCaptureFailed(captureId)
            return
        }
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        try {
            val result = suspendCancellableCoroutine<Int> { cont ->
                @Suppress("DEPRECATION")
                PixelCopy.request(window, bitmap, { r -> cont.resume(r) }, Handler(Looper.getMainLooper()))
            }
            if (result == PixelCopy.SUCCESS) {
                val srcStride = bitmap.rowBytes
                val dstSize = dstStride * height
                val buf = ByteBuffer.allocate(bitmap.rowBytes * height)
                bitmap.copyPixelsToBuffer(buf)
                buf.rewind()
                val srcArr = ByteArray(buf.remaining())
                buf.get(srcArr)
                val dstArr = if (srcStride == dstStride) srcArr else {
                    val copyW = minOf(srcStride, dstStride)
                    ByteArray(dstSize).also { out ->
                        for (row in 0 until height) {
                            srcArr.copyInto(out, row * dstStride, row * srcStride, row * srcStride + copyW)
                        }
                    }
                }
                if (screencopy) WawonaNative.nativeScreencopyComplete(captureId, dstArr)
                else WawonaNative.nativeImageCopyCaptureComplete(captureId, dstArr)
            } else {
                if (screencopy) WawonaNative.nativeScreencopyFailed(captureId)
                else WawonaNative.nativeImageCopyCaptureFailed(captureId)
            }
        } catch (e: Exception) {
            WLog.e("SCREENCOPY", "PixelCopy failed: ''${e.message}")
            if (screencopy) WawonaNative.nativeScreencopyFailed(captureId)
            else WawonaNative.nativeImageCopyCaptureFailed(captureId)
        } finally {
            bitmap.recycle()
        }
    }
}
SCREENCOPY
      fi
    '';

    # Fix egl_buffer_handler for Android (create Android-compatible stubs)
    postPatch = ''
            mkdir -p src/stubs

            # Create header
            cat > src/stubs/egl_buffer_handler.h <<'EOF'
      #pragma once
      #include <stdbool.h>
      #include <stdint.h>
      struct egl_buffer_handler;
      struct wl_display;
      struct wl_resource;
      int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display);
      void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler);
      int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler,
                                           struct wl_resource *buffer_resource,
                                           int32_t *width, int32_t *height,
                                           int *texture_format);
      void* egl_buffer_handler_create_image(struct egl_buffer_handler *handler,
                                            struct wl_resource *buffer_resource);
      bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler,
                                             struct wl_resource *buffer_resource);
      EOF

            # Create stub implementation
            cat > src/stubs/egl_buffer_handler.c <<'EOF'
      #include "egl_buffer_handler.h"
      #include <stdbool.h>
      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>

      // Android stub: EGL Wayland extensions are not available on Android
      // This provides stub implementations to avoid compilation errors

      static void egl_buffer_handler_translation_unit_silence(void) {}

      int egl_buffer_handler_init(struct egl_buffer_handler *handler, struct wl_display *display) {
          (void)handler; (void)display;
          // EGL Wayland extensions not available on Android
          return -1;
      }

      void egl_buffer_handler_cleanup(struct egl_buffer_handler *handler) {
          (void)handler;
      }

      int egl_buffer_handler_query_buffer(struct egl_buffer_handler *handler,
                                           struct wl_resource *buffer_resource,
                                           int32_t *width, int32_t *height,
                                           int *texture_format) {
          (void)handler; (void)buffer_resource; (void)width; (void)height; (void)texture_format;
          return -1;
      }

      void* egl_buffer_handler_create_image(struct egl_buffer_handler *handler,
                                            struct wl_resource *buffer_resource) {
          (void)handler; (void)buffer_resource;
          return NULL;
      }

      bool egl_buffer_handler_is_egl_buffer(struct egl_buffer_handler *handler,
                                             struct wl_resource *buffer_resource) {
          (void)handler; (void)buffer_resource;
          return false;
      }
      EOF
    '';

    buildPhase = ''
      runHook preBuild

      # Embed Vulkan shaders as C byte arrays for textured quad pipeline
      # (inlined - scripts/embed-android-shaders.sh may be untracked in flake)
      mkdir -p build/shaders
      if [ -f src/rendering/shaders/android_quad.vert ] && [ -f src/rendering/shaders/android_quad.frag ]; then
        ${glslang}/bin/glslangValidator -V src/rendering/shaders/android_quad.vert -o build/shaders/quad.vert.spv
        ${glslang}/bin/glslangValidator -V src/rendering/shaders/android_quad.frag -o build/shaders/quad.frag.spv
        echo '/* Auto-generated - do not edit */' > build/shaders/shader_spv.h
        echo '#pragma once' >> build/shaders/shader_spv.h
        echo '#include <stddef.h>' >> build/shaders/shader_spv.h
        echo '#include <stdint.h>' >> build/shaders/shader_spv.h
        echo 'static const unsigned char g_quad_vert_spv[] = {' >> build/shaders/shader_spv.h
        od -A n -t x1 -v build/shaders/quad.vert.spv | awk '{for(i=1;i<=NF;i++) printf " 0x%s,", $i}' | sed '$ s/,$//' >> build/shaders/shader_spv.h
        echo '};' >> build/shaders/shader_spv.h
        echo 'static const size_t g_quad_vert_spv_len = sizeof(g_quad_vert_spv);' >> build/shaders/shader_spv.h
        echo "" >> build/shaders/shader_spv.h
        echo 'static const unsigned char g_quad_frag_spv[] = {' >> build/shaders/shader_spv.h
        od -A n -t x1 -v build/shaders/quad.frag.spv | awk '{for(i=1;i<=NF;i++) printf " 0x%s,", $i}' | sed '$ s/,$//' >> build/shaders/shader_spv.h
        echo '};' >> build/shaders/shader_spv.h
        echo 'static const size_t g_quad_frag_spv_len = sizeof(g_quad_frag_spv);' >> build/shaders/shader_spv.h
        cp build/shaders/shader_spv.h src/rendering/
      else
        echo "ERROR: Shader sources not found. Need src/rendering/shaders/android_quad.vert and .frag"
        exit 1
      fi

      # Setup Weston Simple SHM
      mkdir -p deps/weston-simple-shm
      cp -r ${westonSimpleShmSrc}/* deps/weston-simple-shm/
      chmod -R u+w deps/weston-simple-shm

      # Setup Android toolchain
      export CC="${androidToolchain.androidCC}"
      export CXX="${androidToolchain.androidCXX}"
      export AR="${androidToolchain.androidAR}"
      export STRIP="${androidToolchain.androidSTRIP}"
      export RANLIB="${androidToolchain.androidRANLIB}"
      export CFLAGS="--target=${androidToolchain.androidTarget} -fPIC"
      export CXXFLAGS="--target=${androidToolchain.androidTarget} -fPIC"
      export LDFLAGS="--target=${androidToolchain.androidTarget}"

      # Android dependencies setup
      mkdir -p android-dependencies/include
      mkdir -p android-dependencies/lib
      mkdir -p android-dependencies/lib/pkgconfig

      for dep in $buildInputs; do
         if [ -d "$dep/include" ]; then
           cp -rn "$dep/include/"* android-dependencies/include/ 2>/dev/null || true
         fi
         if [ -d "$dep/lib" ]; then
           cp -rn "$dep/lib/"* android-dependencies/lib/ 2>/dev/null || true
         fi
         if [ -d "$dep/lib/pkgconfig" ]; then
            cp -rn "$dep/lib/pkgconfig/"* android-dependencies/lib/pkgconfig/ 2>/dev/null || true
         fi
      done

      export PKG_CONFIG_PATH="$PWD/android-dependencies/lib/pkgconfig:$PKG_CONFIG_PATH"

      # Compile C/C++ code for Android (native library)
      OBJ_FILES=""
      for src_file in ${lib.concatStringsSep " " androidSourcesFiltered}; do
        if [[ "$src_file" == *.c ]]; then
          obj_file="''${src_file//\//_}.o"
          obj_file="''${obj_file//src_/}"
          
          if $CC -c "$src_file" \
             -Isrc -Isrc/core -Isrc/compositor_implementations \
             -Isrc/rendering -Isrc/input -Isrc/ui \
             -Isrc/logging -Isrc/stubs -Isrc/protocols \
             -Isrc/platform/macos -Isrc/platform/android \
             -Iandroid-dependencies/include \
             -fPIC \
             ${lib.concatStringsSep " " common.commonCFlags} \
             ${lib.concatStringsSep " " common.debugCFlags} \
             --target=${androidToolchain.androidTarget} \
             -o "$obj_file"; then
            OBJ_FILES="$OBJ_FILES $obj_file"
          else
            exit 1
          fi
        fi
      done

      # Compile weston-simple-shm
      for src_file in deps/weston-simple-shm/clients/simple-shm.c deps/weston-simple-shm/shared/os-compatibility.c deps/weston-simple-shm/xdg-shell-protocol.c deps/weston-simple-shm/fullscreen-shell-unstable-v1-protocol.c; do
        obj_file="''${src_file//\//_}.o"
        if $CC -c "$src_file" \
           -D_GNU_SOURCE \
           -Ideps/weston-simple-shm \
           -Ideps/weston-simple-shm/shared \
           -Ideps/weston-simple-shm/include \
           -Iandroid-dependencies/include \
           -fPIC \
           --target=${androidToolchain.androidTarget} \
           -o "$obj_file"; then
          OBJ_FILES="$OBJ_FILES $obj_file"
        else
          exit 1
        fi
      done

      # Link shared library with Rust backend
      RUST_LIB_FLAGS=""
      if [ -n "${toString (if rustBackend != null then "yes" else "")}" ] && [ -f "${rustBackend}/lib/libwawona_core.so" ]; then
        echo "Linking against Rust backend shared library: libwawona_core.so"
        cp ${rustBackend}/lib/libwawona_core.so .
        RUST_LIB_FLAGS="-L. -lwawona_core"
      elif [ -n "${toString (if rustBackend != null then "yes" else "")}" ] && [ -f "${rustBackend}/lib/libwawona.a" ]; then
        echo "Linking Rust backend from ${rustBackend}/lib/libwawona.a (archive)"
        RUST_LIB_FLAGS="-Wl,--whole-archive ${rustBackend}/lib/libwawona.a -Wl,--no-whole-archive"
      else
        echo "WARNING: Rust backend not available, building without it"
      fi

      echo "=== Checking android-dependencies/lib contents ==="
      ls android-dependencies/lib/*.a 2>/dev/null || echo "No .a files found"
      echo "=== Checking for missing libs ==="
      for lib in xkbcommon ffi expat xml2 ssl crypto zstd lz4 wayland-server wayland-client pixman-1; do
        if [ -f "android-dependencies/lib/lib''${lib}.a" ]; then
          echo "  Found: lib''${lib}.a"
        else
          echo "  MISSING: lib''${lib}.a"
        fi
      done

      $CC -shared $OBJ_FILES \
         $RUST_LIB_FLAGS \
         -Landroid-dependencies/lib \
         $(pkg-config --libs wayland-server wayland-client pixman-1 2>/dev/null || echo "-lwayland-server -lwayland-client -lpixman-1") \
         -lxkbcommon -lffi -lexpat \
         -lssl -lcrypto \
         -lzstd -llz4 \
         -llog -landroid -lvulkan -lm -ldl -lz \
         -g --target=${androidToolchain.androidTarget} \
         -o libwawona.so
         
      # Setup Gradle and dependencies
      export GRADLE_USER_HOME=$(pwd)/.gradle_home
      export ANDROID_USER_HOME=$(pwd)/.android_home
      mkdir -p $ANDROID_USER_HOME

      # Copy gradleDeps to writable location
      cp -r ${gradleDeps} $GRADLE_USER_HOME
      chmod -R u+w $GRADLE_USER_HOME

      export ANDROID_SDK_ROOT="${androidSDK.androidsdk}/libexec/android-sdk"
      export ANDROID_HOME="$ANDROID_SDK_ROOT"
      
      # Prepare source directory for Gradle build (emulating project root)
      mkdir -p project-root
      cd project-root
      
      # Copy Android sources from patched build dir (includes prePatch additions)
      cp -r ../src/platform/android/java .
      cp -r ../src/platform/android/res .
      cp ../src/platform/android/AndroidManifest.xml .
      
      # Place native libs where Gradle expects them (jniLibs)
      mkdir -p jniLibs/arm64-v8a
      cp ../libwawona.so jniLibs/arm64-v8a/
      # Copy Rust core shared library if it exists
      if [ -f ../libwawona_core.so ]; then
        cp ../libwawona_core.so jniLibs/arm64-v8a/
      fi

      # Copy other shared libs (dependencies)
      if [ -d ../android-dependencies/lib ]; then
        find ../android-dependencies/lib -name "*.so*" -exec cp -L {} jniLibs/arm64-v8a/ \;
      fi

      # Also copy libc++_shared.so
      NDK_ROOT="${androidToolchain.androidndkRoot}"
      LIBCPP_SHARED=$(find "$NDK_ROOT" -name "libc++_shared.so" | grep "aarch64" | head -n 1)
      if [ -f "$LIBCPP_SHARED" ]; then
        cp "$LIBCPP_SHARED" jniLibs/arm64-v8a/
      fi

      # Bundle OpenSSH and sshpass executables (named as .so for Android extraction)
      if [ -f "${opensshBin}/bin/ssh" ]; then
        cp "${opensshBin}/bin/ssh" jniLibs/arm64-v8a/libssh_bin.so
        chmod +x jniLibs/arm64-v8a/libssh_bin.so
        echo "Bundled ssh executable as libssh_bin.so"
      else
        echo "WARNING: openssh binary not found at ${opensshBin}/bin/ssh"
      fi
      if [ -f "${sshpassBin}/bin/sshpass" ]; then
        cp "${sshpassBin}/bin/sshpass" jniLibs/arm64-v8a/libsshpass_bin.so
        chmod +x jniLibs/arm64-v8a/libsshpass_bin.so
        echo "Bundled sshpass executable as libsshpass_bin.so"
      else
        echo "WARNING: sshpass binary not found at ${sshpassBin}/bin/sshpass"
      fi

      # Fix SONAMEs in copied libs
      chmod +w -R jniLibs
      cd jniLibs/arm64-v8a

      # Remove non-ELF files (linker scripts, .a files, etc.) that may have been copied
      for f in *.so*; do
        [ -f "$f" ] || continue
        if ! file "$f" | grep -q "ELF"; then
          echo "Removing non-ELF file from jniLibs: $f"
          rm -f "$f"
        fi
      done

      for lib in *.so*; do
          [ -f "$lib" ] || continue
          if [[ "$lib" =~ \.so\.[0-9]+ ]]; then
             newname=$(echo "$lib" | sed -E 's/\.so\.[0-9.]*$/.so/')
             if [ "$lib" != "$newname" ]; then
               mv "$lib" "$newname"
               patchelf --set-soname "$newname" "$newname" || true
             fi
          fi
      done

      # Fix dependencies
      for lib in *.so; do
         [ -f "$lib" ] || continue
         needed=$(patchelf --print-needed "$lib" 2>/dev/null) || continue
         for n in $needed; do
           if [[ "$n" =~ \.so\.[0-9]+ ]]; then
             newn=$(echo "$n" | sed -E 's/\.so\.[0-9.]*$/.so/')
             if [ -f "$newn" ]; then
                patchelf --replace-needed "$n" "$newn" "$lib" || true
             fi
           fi
         done
      done
      
      # Return to project-root (from jniLibs/arm64-v8a)
      cd ../..

      # Create Gradle build files (using gradlegen)
      cp ${gradlegen.buildGradle} build.gradle.kts
      cp ${gradlegen.settingsGradle} settings.gradle.kts
      chmod u+w build.gradle.kts settings.gradle.kts

      # Create gradle.properties with AndroidX support
      cat > gradle.properties <<'EOF'
      android.useAndroidX=true
      android.enableJetifier=true
      org.gradle.jvmargs=-Xmx2048m
      kotlin.code.style=official
      EOF

      # Build APK
      gradle assembleDebug --offline --no-daemon

      runHook postBuild
    '';

    installPhase = ''
            runHook preInstall

            # Go back to source root (buildPhase ends inside project-root/)
            cd $NIX_BUILD_TOP/source
            
            mkdir -p $out/bin
            mkdir -p $out/lib
            
            # Copy APK
            APK_PATH=""
            if [ -f "project-root/build/outputs/apk/debug/Wawona-debug.apk" ]; then
              APK_PATH="project-root/build/outputs/apk/debug/Wawona-debug.apk"
            else
              echo "APK not found in expected locations, searching..."
              APK_PATH=$(find . -name "*.apk" -type f | head -1)
              if [ -z "$APK_PATH" ]; then
                echo "Error: No APK found!"
                exit 1
              fi
              echo "Found APK at: $APK_PATH"
            fi
            
            cp "$APK_PATH" $out/bin/Wawona.apk
            echo "Copied APK to $out/bin/Wawona.apk"
            
            # Copy runtime shared libraries
            if [ -d android-dependencies/lib ]; then
              find android-dependencies/lib -name "*.so*" -exec cp -L {} $out/lib/ \;
            fi
            
            # Copy the runner script (created by writeShellScript, already executable)
            cp ${runnerScript} $out/bin/wawona-android-run
            chmod +x $out/bin/wawona-android-run

            # Output project dir for gradlegen (Android Studio openable)
            mkdir -p $project
            cp -r project-root/* $project/
            
            runHook postInstall
    '';
  }
