{
  description = "Wawona";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    # HIAHKernel - Virtual kernel for iOS ONLY (not macOS/Android)
    # Enables multi-process execution on jailed iOS devices
    # TODO: Integrate as iOS-only dependency when flake is ready
    # hiahkernel.url = "github:aspauldingcode/HIAHKernel";
    # hiahkernel.url = "github:aspauldingcode/HIAHKernel";
    hiahkernel.url = "path:/Users/alex/HIAHKernel";
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
      hiahkernel,
    }:
    let
      system = "aarch64-darwin";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ (import rust-overlay) ];
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };

      androidSDK = pkgs.androidenv.composeAndroidPackages {
        cmdLineToolsVersion = "latest";
        platformToolsVersion = "latest";
        buildToolsVersions = [ "36.0.0" ];
        platformVersions = [ "36" ];
        abiVersions = [ "arm64-v8a" ];
        includeEmulator = true;
        emulatorVersion = "36.4.2";
        includeSystemImages = true;
        systemImageTypes = [ "google_apis_playstore" ];
      };

      buildModule = import ./dependencies/build.nix {
        lib = pkgs.lib;
        inherit pkgs;
        stdenv = pkgs.stdenv;
        buildPackages = pkgs.buildPackages;
      };

      wawonaSrc = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter =
          path: type:
          let
            base = baseNameOf path;
          in
          !(
            base == ".git"
            || base == "build"
            || base == "result"
            || base == ".direnv"
            || pkgs.lib.hasPrefix "result" base
          );
      };

      wawonaBuildModule = import ./dependencies/wawona.nix {
        lib = pkgs.lib;
        inherit
          pkgs
          buildModule
          wawonaSrc
          androidSDK
          hiahkernel
          ;
      };

      androidToolchain = import ./dependencies/common/android-toolchain.nix {
        inherit (pkgs) lib;
        inherit pkgs;
      };

      updateAndroidDeps = pkgs.writeShellScriptBin "update-android-deps" ''
        export ANDROID_SDK_ROOT="${androidSDK.androidsdk}/libexec/android-sdk"
        export GRADLE_USER_HOME=$(pwd)/.gradle-home
        cd src/android
        ${pkgs.gradle}/bin/gradle dependencyUpdates
      '';

      multiplexDev = pkgs.writeShellScriptBin "wawona-multiplex" ''
        tmux="${pkgs.tmux}/bin/tmux"
        $tmux new-session -d -s wawona "nix run .#wawona-macos"
        $tmux split-window -t wawona "nix run .#wawona-ios"
        $tmux split-window -t wawona "nix run .#wawona-android"
        $tmux select-layout -t wawona tiled
        $tmux attach -t wawona
      '';

      # Individual dependency packages for each platform
      iosDeps = buildModule.ios;
      macosDeps = buildModule.macos;
      androidDeps = buildModule.android;

      waypipeMacosWrapper = pkgs.writeShellScriptBin "waypipe-macos" ''
        # Force XDG_RUNTIME_DIR to match Wawona's predictable path
        # We override any existing value to ensure connection with Wawona compositor
        export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
        
        # Default to wayland-0 if not set
        if [ -z "$WAYLAND_DISPLAY" ]; then
          export WAYLAND_DISPLAY="wayland-0"
        fi

        exec "${macosDeps.waypipe}/bin/waypipe" "$@"
      '';

      wawonaMacosWrapper = pkgs.writeShellScriptBin "wawona-macos" ''
        # Force XDG_RUNTIME_DIR to match Wawona's predictable path
        # We override any existing value to ensure predictable socket location
        export XDG_RUNTIME_DIR="/tmp/wawona-$(id -u)"
        
        exec "${wawonaBuildModule.macos}/bin/Wawona" "$@"
      '';
      
      wawonaKernelIosWrapper = pkgs.writeShellScriptBin "wawona-kernel-ios" ''
        # Set environment variables for the iOS Simulator app
        # simctl launch passes variables prefixed with SIMCTL_CHILD_ to the app
        export SIMCTL_CHILD_WAWONA_KERNEL_TEST=1
        export SIMCTL_CHILD_WAWONA_EXIT_ON_TEST_COMPLETE=1
        
        # Enable log following and debug level for kernel testing
        export WAWONA_IOS_FOLLOW_LOGS=1
        export WAWONA_IOS_LOG_LEVEL=debug
        export WAWONA_IOS_LOG_FILE=output.log
        
        echo "🚀 Launching Wawona iOS Kernel Tests 🚀"
        echo "   Testing: hello_world, ssh, waypipe"
        exec "${wawonaBuildModule.ios}/bin/wawona-ios-simulator" "$@"
      '';
      
      opensshTestIosWrapper = pkgs.writeShellScriptBin "openssh-test-ios" ''
        # Find the openssh_test_ios binary in the app bundle
        APP_BUNDLE="${wawonaBuildModule.ios}/Applications/Wawona.app"
        TEST_BIN="$APP_BUNDLE/bin/openssh_test_ios"
        
        if [ ! -f "$TEST_BIN" ]; then
          echo "❌ Error: openssh_test_ios not found at $TEST_BIN"
          echo "   Make sure you've built wawona-ios first: nix build .#wawona-ios"
          exit 1
        fi
        
        # Get device ID (use first available simulator)
        DEVICE_ID=$(xcrun simctl list devices available | grep -i "iphone" | head -1 | grep -oE '[A-F0-9-]{36}' | head -1)
        
        if [ -z "$DEVICE_ID" ]; then
          echo "❌ Error: No iOS simulator found"
          exit 1
        fi
        
        echo "🔐 OpenSSH Test for iOS"
        echo "======================"
        echo "Device: $DEVICE_ID"
        echo "Binary: $TEST_BIN"
        echo ""
        echo "This will test SSH connection using Wawona's settings"
        echo "Make sure you've configured SSH host/user in Wawona preferences"
        echo ""
        
        # Boot simulator if needed
        xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
        
        # Install app if needed
        xcrun simctl install "$DEVICE_ID" "$APP_BUNDLE" 2>/dev/null || true
        
        # Run the test binary via simctl spawn
        xcrun simctl spawn "$DEVICE_ID" "$TEST_BIN"
      '';

      # Waypipe SSH Test for iOS - tests full SSH connection with hardcoded test server
      waypipeTestIosWrapper = pkgs.writeShellScriptBin "waypipe-test-ios" ''
        set -e
        
        echo "🚀 Waypipe SSH Connection Test for iOS 🚀"
        echo "=========================================="
        echo ""
        echo "Test Server: alex@10.0.0.87"
        echo "Password: (hardcoded for testing)"
        echo ""
        
        # Get the app bundle path
        APP_BUNDLE="${wawonaBuildModule.ios}/Applications/Wawona.app"
        
        if [ ! -d "$APP_BUNDLE" ]; then
          echo "❌ Error: Wawona app bundle not found"
          echo "   Run: nix build .#wawona-ios"
          exit 1
        fi
        
        # Get device ID (use first available iPhone simulator)
        DEVICE_ID=$(xcrun simctl list devices available | grep -i "iphone" | head -1 | grep -oE '[A-F0-9-]{36}' | head -1)
        
        if [ -z "$DEVICE_ID" ]; then
          echo "❌ Error: No iOS simulator found"
          echo "   Please install Xcode and create an iPhone simulator"
          exit 1
        fi
        
        echo "📱 Device ID: $DEVICE_ID"
        
        # Boot simulator if needed
        echo "Booting simulator..."
        xcrun simctl boot "$DEVICE_ID" 2>/dev/null || true
        sleep 2
        
        # Get the device data directory for simctl spawn
        DATA_DIR=$(xcrun simctl get_app_container "$DEVICE_ID" com.aspauldingcode.Wawona data 2>/dev/null || true)
        
        # Install the app
        echo "Installing Wawona.app..."
        xcrun simctl install "$DEVICE_ID" "$APP_BUNDLE"
        
        # Get container path after install
        BUNDLE_PATH=$(xcrun simctl get_app_container "$DEVICE_ID" com.aspauldingcode.Wawona app 2>/dev/null || true)
        echo "📦 Bundle installed at: $BUNDLE_PATH"
        
        # Check if ssh.dylib exists
        if [ -n "$BUNDLE_PATH" ]; then
          echo ""
          echo "Checking SSH binary..."
          if [ -f "$BUNDLE_PATH/bin/ssh.dylib" ]; then
            echo "✓ ssh.dylib found"
            ls -la "$BUNDLE_PATH/bin/ssh.dylib"
          fi
          if [ -f "$BUNDLE_PATH/bin/ssh" ]; then
            echo "✓ ssh executable found"
            ls -la "$BUNDLE_PATH/bin/ssh"
          fi
        fi
        
        # Set environment variables for test
        # SSH_ASKPASS_PASSWORD is used by our patched readpassphrase
        export SIMCTL_CHILD_SSH_ASKPASS_PASSWORD="787866"
        export SIMCTL_CHILD_SSHPASS="787866"
        export SIMCTL_CHILD_WAWONA_SSH_TEST=1
        export SIMCTL_CHILD_WAWONA_SSH_HOST="10.0.0.87"
        export SIMCTL_CHILD_WAWONA_SSH_USER="alex"
        export SIMCTL_CHILD_WAWONA_SSH_PASSWORD="787866"
        export SIMCTL_CHILD_WAWONA_EXIT_ON_TEST_COMPLETE=1
        export SIMCTL_CHILD_WAWONA_WAYPIPE_TEST=1
        
        # Enable log following
        export WAWONA_IOS_FOLLOW_LOGS=1
        export WAWONA_IOS_LOG_LEVEL=debug
        export WAWONA_IOS_LOG_FILE=output.log
        
        echo ""
        echo "📝 Logs will be written to: output.log"
        echo ""
        
        # Clear previous log
        > output.log
        
        # Start log stream in background
        echo "Starting log stream..."
        xcrun simctl spawn "$DEVICE_ID" log stream \
          --level debug \
          --predicate 'subsystem == "com.aspauldingcode.Wawona" OR process == "Wawona" OR process == "WawonaSSHRunner" OR processImagePath CONTAINS "ssh" OR processImagePath CONTAINS "waypipe"' \
          >> output.log 2>&1 &
        LOG_PID=$!
        echo "Log stream started (PID: $LOG_PID)"
        
        # Function to cleanup
        cleanup() {
          echo ""
          echo "Cleaning up..."
          kill $LOG_PID 2>/dev/null || true
          xcrun simctl terminate "$DEVICE_ID" com.aspauldingcode.Wawona 2>/dev/null || true
        }
        trap cleanup EXIT
        
        echo ""
        echo "🔍 Launching with LLDB for debugging..."
        echo "   You can attach to the SSH process for debugging"
        echo ""
        
        # Launch the app with test environment
        echo "Launching Wawona with SSH test configuration..."
        xcrun simctl launch --console-pty "$DEVICE_ID" com.aspauldingcode.Wawona &
        APP_PID=$!
        
        # Give the app time to start
        sleep 3
        
        # Show LLDB instructions
        echo ""
        echo "📎 LLDB Debugging Instructions:"
        echo "   In another terminal, run:"
        echo "     xcrun simctl spawn booted lldb"
        echo "     (lldb) process attach -n WawonaSSHRunner"
        echo "     (lldb) breakpoint set -n ssh_main"
        echo "     (lldb) continue"
        echo ""
        
        # Wait for test to complete (timeout after 60 seconds)
        echo "Waiting for SSH connection test (timeout: 60s)..."
        TIMEOUT=60
        ELAPSED=0
        TEST_RESULT=""
        while [ $ELAPSED -lt $TIMEOUT ]; do
          # Check if test completed successfully (look for actual success message from SSH exiting with code 0)
          # Note: "SSH connection test completed successfully" is an echo command in our test, not the actual result
          if strings output.log 2>/dev/null | grep -q "ssh_main.*SSH exited with code 0"; then
            echo "✅ SSH connection test completed successfully!"
            TEST_RESULT="success"
            break
          fi
          # Check for explicit failure messages
          if strings output.log 2>/dev/null | grep -q "\[WawonaKernel\] SSH connection failed"; then
            echo "❌ SSH connection test failed!"
            TEST_RESULT="failed"
            break
          fi
          if strings output.log 2>/dev/null | grep -q "ssh_main.*exited with code 0"; then
            echo "✅ SSH process exited successfully"
            TEST_RESULT="success"
            break
          fi
          if strings output.log 2>/dev/null | grep -q "ssh_main.*exited with code"; then
            echo "⚠️  SSH process exited with non-zero code"
            TEST_RESULT="failed"
            break
          fi
          if strings output.log 2>/dev/null | grep -q "Failed to load extension"; then
            echo "❌ Extension loading failed - check app extension configuration"
            TEST_RESULT="failed"
            break
          fi
          if strings output.log 2>/dev/null | grep -q "Failed to chdir to app group"; then
            echo "❌ App group container not accessible - this is a simulator limitation"
            TEST_RESULT="failed"
            break
          fi
          sleep 1
          ELAPSED=$((ELAPSED + 1))
          if [ $((ELAPSED % 10)) -eq 0 ]; then
            echo "  ... waiting ($ELAPSED/$TIMEOUT seconds)"
          fi
        done
        
        if [ $ELAPSED -ge $TIMEOUT ]; then
          echo "⚠️  Test timed out after $TIMEOUT seconds"
          TEST_RESULT="timeout"
        fi
        
        echo ""
        echo "📋 Test Results Summary:"
        echo "========================"
        
        # Show relevant log entries
        echo ""
        echo "SSH-related log entries:"
        strings output.log 2>/dev/null | grep -iE "ssh|password|connect|kernel|extension" | tail -50 || echo "  (no SSH logs found)"
        
        echo ""
        echo "Full log available in: output.log"
        
        # Terminate the app
        xcrun simctl terminate "$DEVICE_ID" com.aspauldingcode.Wawona 2>/dev/null || true
        
        echo ""
        echo "✅ Waypipe SSH test finished."
      '';

    in
    {
      packages.${system} = {
        default = wawonaMacosWrapper;
        wawona-ios = wawonaBuildModule.ios;
        wawona-kernel-ios = wawonaKernelIosWrapper;
        openssh-test-ios = opensshTestIosWrapper;
        waypipe-test-ios = waypipeTestIosWrapper;
        wawona-macos = wawonaMacosWrapper;
        wawona-android = wawonaBuildModule.android;

        # iOS dependencies
        waypipe-ios = iosDeps.waypipe;
        ffmpeg-ios = iosDeps.ffmpeg;
        "libwayland-ios" = iosDeps.libwayland;
        "kosmickrisp-ios" = iosDeps.kosmickrisp;
        "lz4-ios" = iosDeps.lz4;
        "zstd-ios" = iosDeps.zstd;
        "expat-ios" = iosDeps.expat;
        "libffi-ios" = iosDeps.libffi;
        "libxml2-ios" = iosDeps.libxml2;
        "epoll-shim-ios" = iosDeps."epoll-shim";
        "mbedtls-ios" = iosDeps.mbedtls;
        # Note: libssh2 removed - using OpenSSH binary instead
        "openssh-ios" = iosDeps.openssh;

        # macOS dependencies
        waypipe-macos = macosDeps.waypipe;
        ffmpeg-macos = macosDeps.ffmpeg;
        "libwayland-macos" = macosDeps.libwayland;
        "kosmickrisp-macos" = macosDeps.kosmickrisp;
        "lz4-macos" = macosDeps.lz4;
        "zstd-macos" = macosDeps.zstd;
        "expat-macos" = macosDeps.expat;
        "libffi-macos" = macosDeps.libffi;
        "libxml2-macos" = macosDeps.libxml2;
        "epoll-shim-macos" = macosDeps."epoll-shim";
        "sshpass-macos" = macosDeps.sshpass;
        # Font stack for foot terminal
        "tllist-macos" = macosDeps.tllist;
        "freetype-macos" = macosDeps.freetype;
        "fontconfig-macos" = macosDeps.fontconfig;
        "utf8proc-macos" = macosDeps.utf8proc;
        "fcft-macos" = macosDeps.fcft;
        # Applications
        "foot-macos" = macosDeps.foot;

        # Android dependencies
        waypipe-android = androidDeps.waypipe;
        ffmpeg-android = androidDeps.ffmpeg;
        "libwayland-android" = androidDeps.libwayland;
        "swiftshader-android" = androidDeps.swiftshader;
        "lz4-android" = androidDeps.lz4;
        "zstd-android" = androidDeps.zstd;
        "expat-android" = androidDeps.expat;
        "libffi-android" = androidDeps.libffi;
        "libxml2-android" = androidDeps.libxml2;
      };

      apps.${system} = {
        default = {
          type = "app";
          program = "${multiplexDev}/bin/wawona-multiplex";
        };
        wawona-ios = {
          type = "app";
          program = "${wawonaBuildModule.ios}/bin/wawona-ios-simulator";
        };
        wawona-kernel-ios = {
          type = "app";
          program = "${wawonaKernelIosWrapper}/bin/wawona-kernel-ios";
        };
        openssh-test-ios = {
          type = "app";
          program = "${opensshTestIosWrapper}/bin/openssh-test-ios";
        };
        waypipe-test-ios = {
          type = "app";
          program = "${waypipeTestIosWrapper}/bin/waypipe-test-ios";
        };
        wawona-android = {
          type = "app";
          program = "${wawonaBuildModule.android}/bin/wawona-android-run";
        };
        wawona-macos = {
          type = "app";
          program = "${wawonaMacosWrapper}/bin/wawona-macos";
        };
        update-android-deps = {
          type = "app";
          program = "${updateAndroidDeps}/bin/update-android-deps";
        };
        waypipe-macos = {
          type = "app";
          program = "${waypipeMacosWrapper}/bin/waypipe-macos";
        };
      };

      formatter.${system} = pkgs.nixfmt;

      devShells.${system}.default = pkgs.mkShell {
        buildInputs = [
          pkgs.gradle
          pkgs.jdk17
          androidSDK.androidsdk
        ];
        ANDROID_SDK_ROOT = "${androidSDK.androidsdk}/libexec/android-sdk";
        ANDROID_NDK_ROOT = "${androidToolchain.androidndkRoot}";
      };
    };
}
