{ lib, pkgs, TEAM_ID ? null }:

let
  # Script to find Xcode
  findXcodeScript = pkgs.writeShellScriptBin "find-xcode" ''
    #!/usr/bin/env bash
    set -euo pipefail

    # Method 1: Use xcode-select to find the active developer directory
    if command -v xcode-select >/dev/null 2>&1; then
        XCODE_DEVELOPER_DIR=$(xcode-select -p 2>/dev/null || true)
        if [ -n "$XCODE_DEVELOPER_DIR" ]; then
            # Extract Xcode.app path from developer directory
            # /Applications/Xcode.app/Contents/Developer -> /Applications/Xcode.app
            XCODE_APP="''${XCODE_DEVELOPER_DIR%/Contents/Developer}"
            if [ -d "$XCODE_APP" ] && [[ "$XCODE_APP" == *.app ]]; then
                echo "$XCODE_APP"
                exit 0
            fi
        fi
    fi

    # Method 2: Check common locations
    for XCODE_APP in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [ -d "$XCODE_APP" ]; then
            echo "$XCODE_APP"
            exit 0
        fi
    done

    # Method 3: Search /Applications for Xcode*.app
    if [ -d /Applications ]; then
        XCODE_APP=$(find /Applications -maxdepth 1 -name "Xcode*.app" -type d 2>/dev/null | head -1)
        if [ -n "$XCODE_APP" ]; then
            echo "$XCODE_APP"
            exit 0
        fi
    fi

    # Not found
    echo "ERROR: Xcode not found. Please install Xcode from the App Store or set XCODE_APP environment variable." >&2
    exit 1
  '';

  # Get Xcode path (evaluated at build time)
  getXcodePath = pkgs.writeShellScriptBin "get-xcode-path" ''
    if [ -n "''${XCODE_APP:-}" ]; then
        echo "$XCODE_APP"
    else
        ''${findXcodeScript}/bin/find-xcode
    fi
  '';

  # ---------------------------------------------------------------------------
  # ensureIosSimSDK
  # ---------------------------------------------------------------------------
  # Ensures the iOS Simulator SDK is available under the active Xcode install.
  # Invokes `xcodebuild -downloadPlatform iOS` which is the Apple-supported
  # mechanism to fetch the iPhoneSimulator platform package on demand.
  #
  # Usage (in build scripts / preConfigure hooks):
  #   ${ensureIosSimSDK}/bin/ensure-ios-sim-sdk
  # ---------------------------------------------------------------------------
  ensureIosSimSDK = pkgs.writeShellScriptBin "ensure-ios-sim-sdk" ''
    #!/usr/bin/env bash
    set -euo pipefail

    XCODE_APP=$(${findXcodeScript}/bin/find-xcode)
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
    XCODEBUILD="$DEVELOPER_DIR/usr/bin/xcodebuild"

    # Accept the Xcode license non-interactively so CI/headless machines
    # don't stall on the EULA prompt.  May require sudo the first time.
    if ! "$XCODEBUILD" -license check 2>/dev/null; then
      echo "[ensure-ios-sim-sdk] Accepting Xcode license (may need sudo)..."
      sudo "$XCODEBUILD" -license accept 2>/dev/null || \
        "$XCODEBUILD" -license accept 2>/dev/null || true
    fi

    # Check whether the iPhoneSimulator SDK is already present.
    SIM_PLATFORM="$DEVELOPER_DIR/Platforms/iPhoneSimulator.platform"
    SIM_SDK_DIR="$SIM_PLATFORM/Developer/SDKs"

    has_sim_sdk() {
      ls "$SIM_SDK_DIR"/iPhoneSimulator*.sdk 2>/dev/null | grep -q sdk
    }

    if has_sim_sdk; then
      echo "[ensure-ios-sim-sdk] iOS Simulator SDK already installed: $(ls "$SIM_SDK_DIR" 2>/dev/null | head -1)"
      exit 0
    fi

    echo "[ensure-ios-sim-sdk] iOS Simulator SDK not found at $SIM_SDK_DIR"
    echo "[ensure-ios-sim-sdk] Downloading iOS platform via xcodebuild -downloadPlatform iOS ..."
    echo "[ensure-ios-sim-sdk] This may take several minutes on the first run."

    # -downloadPlatform iOS fetches the iPhoneSimulator platform & SDK.
    # We run it from a writable temp home to avoid permission issues.
    HOME="$(mktemp -d)" "$XCODEBUILD" -downloadPlatform iOS || {
      echo ""
      echo "[ensure-ios-sim-sdk] ERROR: xcodebuild -downloadPlatform iOS failed."
      echo ""
      echo "  Manual fix options:"
      echo "    1.  sudo xcodebuild -downloadPlatform iOS"
      echo "    2.  Open Xcode → Settings → Platforms → iOS → Download"
      echo ""
      exit 1
    }

    # Verify the SDK landed.
    if ! has_sim_sdk; then
      echo "[ensure-ios-sim-sdk] ERROR: download reported success but SDK not found."
      echo "  Expected location: $SIM_SDK_DIR/iPhoneSimulator*.sdk"
      exit 1
    fi

    echo "[ensure-ios-sim-sdk] Installed: $(ls "$SIM_SDK_DIR" | head -1)"
  '';
in
{
  inherit findXcodeScript getXcodePath ensureIosSimSDK;

  # Wrapper that sets up Xcode environment
  xcodeWrapper = pkgs.writeShellScriptBin "xcode-wrapper" ''
    #!/usr/bin/env bash
    set -euo pipefail
    NIX_TEAM_ID="${if TEAM_ID == null then "" else TEAM_ID}"

    XCODE_APP=$(${findXcodeScript}/bin/find-xcode)
    export XCODE_APP

    # Set developer directory
    export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"

    # Prefer runtime TEAM_ID from shell; only fall back to Nix TEAM_ID input.
    if [ -z "''${DEVELOPMENT_TEAM:-}" ]; then
      if [ -n "''${TEAM_ID:-}" ]; then
        export DEVELOPMENT_TEAM="''${TEAM_ID}"
      elif [ -n "$NIX_TEAM_ID" ]; then
        export DEVELOPMENT_TEAM="$NIX_TEAM_ID"
      fi
    fi

    # Add Xcode tools to PATH
    export PATH="$DEVELOPER_DIR/usr/bin:$PATH"

    # Set SDK paths
    export SDKROOT="$DEVELOPER_DIR/Platforms/iPhoneOS.platform/Developer/SDKs/iPhoneOS.sdk"

    # Execute the command passed as arguments
    exec "$@"
  '';
}
