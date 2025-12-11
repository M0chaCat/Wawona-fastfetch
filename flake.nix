{
  description = "Wawona Multiplex Runner";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs";
  inputs.rust-overlay.url = "github:oxalica/rust-overlay";
  inputs.rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  
  outputs = { self, nixpkgs, rust-overlay }: let
    systems = [ "aarch64-darwin" ];
    forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
  in {
    packages = forAllSystems (system: let
      pkgs = import nixpkgs { 
        inherit system;
        overlays = [ (import rust-overlay) ];
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };
      
      # Define androidSDK for build module
      androidSDK = if pkgs ? androidenv && pkgs.androidenv ? composeAndroidPackages then
        pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "latest";
          platformToolsVersion = "latest";
          buildToolsVersions = [ "35.0.0" ];
          platformVersions = [ "35" ];  # Android 15
          abiVersions = [ "arm64-v8a" ];  # ARM64 for our target
          includeEmulator = true;
          emulatorVersion = "35.3.11";  # Use a valid available version
          includeSystemImages = true;
          systemImageTypes = [ "google_apis_playstore" ];
        }
      else null;
      
      # Import dependencies module
      depsModule = import ./dependencies/common/common.nix {
        lib = pkgs.lib;
        inherit pkgs;
      };
      
      # Import build module
      buildModule = import ./dependencies/build.nix {
        lib = pkgs.lib;
        inherit pkgs;
        stdenv = pkgs.stdenv;
        buildPackages = pkgs.buildPackages;
      };
      
      # Import Wawona build module
      # Filter source to exclude build artifacts and other files
      wawonaSrc = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: type:
          let
            baseName = baseNameOf path;
            relPath = pkgs.lib.removePrefix (toString ./. + "/") (toString path);
          in
            !(
              baseName == ".git" ||
              baseName == "build" ||
              baseName == "result" ||
              baseName == ".direnv" ||
              pkgs.lib.hasPrefix "result" baseName ||
              pkgs.lib.hasPrefix ".git" baseName
            );
      };
      
      wawonaBuildModule = import ./dependencies/wawona.nix {
        lib = pkgs.lib;
        inherit pkgs buildModule wawonaSrc;
        inherit androidSDK;
      };
      
      # Get registry for building individual dependencies
      registry = depsModule.registry;
      
      # Build all dependencies for each platform
      iosDeps = buildModule.ios;
      macosDeps = buildModule.macos;
      androidDeps = buildModule.android;
      
      # Create individual dependency packages for each platform
      # Format: <dependency-name>-<platform>
      dependencyPackages = let
        # Helper to create packages for a platform
        createPlatformPackages = platform: deps:
          pkgs.lib.mapAttrs' (name: pkg: {
            name = "${name}-${platform}";
            value = pkg;
          }) deps;
        
        iosPkgs = createPlatformPackages "ios" iosDeps;
        macosPkgs = createPlatformPackages "macos" macosDeps;
        androidPkgs = createPlatformPackages "android" androidDeps;
        
        # libwayland is handled directly in platform dispatchers, not via registry
        directPkgs = {
          "libwayland-ios" = buildModule.buildForIOS "libwayland" {};
          "libwayland-macos" = buildModule.buildForMacOS "libwayland" {};
          "libwayland-android" = buildModule.buildForAndroid "libwayland" {};
          "expat-ios" = buildModule.buildForIOS "expat" {};
          "expat-macos" = buildModule.buildForMacOS "expat" {};
          "expat-android" = buildModule.buildForAndroid "expat" {};
          "libffi-ios" = buildModule.buildForIOS "libffi" {};
          "libffi-macos" = buildModule.buildForMacOS "libffi" {};
          "libffi-android" = buildModule.buildForAndroid "libffi" {};
          "libxml2-ios" = buildModule.buildForIOS "libxml2" {};
          "libxml2-macos" = buildModule.buildForMacOS "libxml2" {};
          "libxml2-android" = buildModule.buildForAndroid "libxml2" {};
          "waypipe-ios" = buildModule.buildForIOS "waypipe" {};
          "waypipe-macos" = buildModule.buildForMacOS "waypipe" {};
          "waypipe-android" = buildModule.buildForAndroid "waypipe" {};
          "swiftshader-android" = buildModule.buildForAndroid "swiftshader" {};
          "kosmickrisp-ios" = buildModule.buildForIOS "kosmickrisp" {};
          "kosmickrisp-macos" = buildModule.buildForMacOS "kosmickrisp" {};
          "epoll-shim-ios" = buildModule.buildForIOS "epoll-shim" {};
          "epoll-shim-macos" = buildModule.buildForMacOS "epoll-shim" {};
          "zstd-ios" = buildModule.buildForIOS "zstd" {};
          "zstd-macos" = buildModule.buildForMacOS "zstd" {};
          "zstd-android" = buildModule.buildForAndroid "zstd" {};
          "lz4-ios" = buildModule.buildForIOS "lz4" {};
          "lz4-macos" = buildModule.buildForMacOS "lz4" {};
          "lz4-android" = buildModule.buildForAndroid "lz4" {};
          "ffmpeg-ios" = buildModule.buildForIOS "ffmpeg" {};
          "ffmpeg-macos" = buildModule.buildForMacOS "ffmpeg" {};
          "ffmpeg-android" = buildModule.buildForAndroid "ffmpeg" {};
          "test-ios-toolchain" = pkgs.callPackage ./dependencies/utils/test-ios-toolchain.nix {};
          "test-ios-toolchain-cross" = pkgs.callPackage ./dependencies/utils/test-ios-toolchain-cross.nix {};
        };
      in
        iosPkgs // macosPkgs // androidPkgs // directPkgs;
      
      # Wrapper script to run Nix build and show dialog on exit
      wawonaWrapper = pkgs.writeShellScriptBin "wawona-wrapper" ''
        TARGET=$1
        LOGFILE="build/$TARGET.log"
        mkdir -p build
        
        # Map target names to Nix package names
        case "$TARGET" in
          ios-compositor)
            NIX_PKG="wawona-ios"
            ;;
          macos-compositor)
            NIX_PKG="wawona-macos"
            ;;
          android-compositor)
            NIX_PKG="wawona-android"
            ;;
          *)
            echo "Unknown target: $TARGET"
            exit 1
            ;;
        esac
        
        # Run nix build and capture output (tee to log and stdout)
        # We use a subshell to capture exit code of nix build, not tee
        set +e
        ( nix build --show-trace .#"$NIX_PKG" 2>&1; echo $? > build/"$TARGET".exitcode ) | tee "$LOGFILE"
        EXIT_CODE=$(cat build/"$TARGET".exitcode)
        rm build/"$TARGET".exitcode
        set -e
        
        if [ "$EXIT_CODE" -eq 0 ]; then
            MSG="Build '$TARGET' SUCCEEDED."
            
            # Run the application based on target
            case "$TARGET" in
              macos-compositor)
                echo "Launching Wawona for macOS..."
                # Assuming standard Nix install structure
                if [ -d "./result/Applications/Wawona.app" ]; then
                   open "./result/Applications/Wawona.app"
                elif [ -f "./result/bin/Wawona" ]; then
                   ./result/bin/Wawona &
                else
                   echo "Could not find Wawona binary/app to launch."
                fi
                ;;
              ios-compositor)
                echo "Deploying Wawona to iOS Simulator..."
                APP_PATH=$(find ./result -name "Wawona.app" | head -n 1)
                if [ -n "$APP_PATH" ]; then
                    # Get first booted simulator
                    DEVICE_ID=$(xcrun simctl list devices booted | grep "Booted" | head -n 1 | awk -F '[()]' '{print $2}')
                    if [ -z "$DEVICE_ID" ]; then
                        echo "No booted simulator found. Attempting to boot iPhone 14..."
                        DEVICE_ID=$(xcrun simctl list devices available | grep "iPhone 14" | head -n 1 | awk -F '[()]' '{print $2}')
                        if [ -n "$DEVICE_ID" ]; then
                            xcrun simctl boot "$DEVICE_ID" || true
                        else 
                            echo "Could not find a simulator to boot."
                        fi
                    fi
                    
                    if [ -n "$DEVICE_ID" ]; then
                        echo "Installing to device $DEVICE_ID..."
                        xcrun simctl install "$DEVICE_ID" "$APP_PATH"
                        echo "Launching com.aspauldingcode.Wawona..."
                        xcrun simctl launch "$DEVICE_ID" "com.aspauldingcode.Wawona"
                    fi
                else
                    echo "Could not find Wawona.app in build output."
                fi
                ;;
              android-compositor)
                echo "Deploying Wawona to Android Emulator..."
                if [ -f "./result/bin/wawona-android-run" ]; then
                    echo "Running Wawona Android launcher..."
                    ./result/bin/wawona-android-run
                elif [ -f "./result/bin/Wawona" ]; then
                    # Fallback for headless binary if APK build fails or isn't used
                    echo "Pushing binary to /data/local/tmp/..."
                    adb push "./result/bin/Wawona" /data/local/tmp/wawona
                    echo "Running..."
                    adb shell "chmod +x /data/local/tmp/wawona && /data/local/tmp/wawona" &
                else
                    echo "Could not find Wawona build output (wawona-android-run or binary)."
                fi
                ;;
            esac
            
        else
            MSG="Build '$TARGET' FAILED (Exit Code: $EXIT_CODE)."
        fi
            
            CHOICE=$(dialog --clear --title "Wawona Build: $TARGET" \
                --menu "$MSG\nSelect an action:" 16 60 5 \
                "1" "View Logs (less)" \
                "2" "Open Logs (Default App)" \
                "3" "Reveal Logs in Finder" \
                "4" "Copy Log Here" \
                "5" "Exit Pane" \
                2>&1 >/dev/tty)
            
            case $CHOICE in
                1)
                    less -R "$LOGFILE"
                    ;;
                2)
                    open "$LOGFILE"
                    ;;
                3)
                    open -R "$LOGFILE"
                    ;;
                4)
                    cp "$LOGFILE" "./$TARGET.log"
                    dialog --msgbox "Log copied to ./$TARGET.log" 6 40
                    ;;
                5)
                    break
                    ;;
                *)
                    break
                    ;;
            esac
        done
      '';

      wawonaBuildInputs = with pkgs; [
        cmake meson ninja pkg-config
        autoconf automake libtool texinfo
        git python3 direnv gnumake patch
        bison flex shaderc mesa
        tmux dialog
      ] ++ pkgs.lib.optionals pkgs.stdenv.isDarwin [
        # Xcode tools are system-provided usually
      ];
    in {
      default = pkgs.writeShellApplication {
        name = "wawona-multiplex";
        runtimeInputs = wawonaBuildInputs ++ [ wawonaWrapper ];
        text = ''
          set -euo pipefail
          session="wawona-build"
          if tmux has-session -t "$session" 2>/dev/null; then
            tmux kill-session -t "$session"
          fi
          
          # Start session (pane 0) - ios-compositor
          tmux new-session -d -s "$session" "wawona-wrapper ios-compositor"
          
          # Split horizontally (pane 1) - android-compositor
          tmux split-window -h -t "$session":0
          tmux send-keys -t "$session":0.1 "wawona-wrapper android-compositor" C-m
          
          # Split pane 1 vertically (pane 2) - macos-compositor
          tmux split-window -v -t "$session":0.1
          tmux send-keys -t "$session":0.2 "wawona-wrapper macos-compositor" C-m
          
          # Select first pane
          tmux select-pane -t "$session":0.0
          
          # Attach
          tmux attach-session -t "$session"
        '';
      };
      
      # Add Wawona build packages
      wawona-ios = wawonaBuildModule.ios;
      wawona-macos = wawonaBuildModule.macos;
      wawona-android = wawonaBuildModule.android;
      
      # Add dependency packages
      # Format: <dependency-name>-<platform> (e.g., wayland-ios, kosmickrisp-macos)
    } // dependencyPackages);
    
    apps = forAllSystems (system: let
      pkgs = import nixpkgs { 
        inherit system;
        overlays = [ (import rust-overlay) ];
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      };
      # Use androidenv.composeAndroidPackages to get Android SDK tools via Nix
      # This provides platform-tools (adb), emulator, and system images
      androidSDK = if pkgs ? androidenv && pkgs.androidenv ? composeAndroidPackages then
        pkgs.androidenv.composeAndroidPackages {
          cmdLineToolsVersion = "latest";
          platformToolsVersion = "latest";
          buildToolsVersions = [ "35.0.0" ];
          platformVersions = [ "35" ];  # Android 15
          abiVersions = [ "arm64-v8a" ];  # ARM64 for our target
          includeEmulator = true;
          emulatorVersion = "35.3.11";  # Use a valid available version
          includeSystemImages = true;
          systemImageTypes = [ "google_apis_playstore" ];
        }
      else null;
      
      # Get tools from the SDK
      androidTools = if androidSDK != null then [
        androidSDK.platform-tools  # Provides adb
        androidSDK.emulator       # Provides emulator
        androidSDK.androidsdk     # Provides avdmanager
      ] else if pkgs ? android-tools then [
        pkgs.android-tools  # Fallback
      ] else [];
    in {
      default = {
        type = "app";
        program = "${self.packages.${system}.default}/bin/wawona-multiplex";
      };
      
      # Individual platform apps
      "wawona-macos" = {
        type = "app";
        # Use bin symlink for macOS (more reliable than app bundle path)
        program = "${self.packages.${system}.wawona-macos}/bin/Wawona";
      };
      
      "wawona-ios" = {
        type = "app";
        program = "${self.packages.${system}.wawona-ios}/bin/wawona-ios-simulator";
      };
      
      "wawona-android" = let
        # Create a wrapper that uses Nix-provided Android tools
        # Tools are provided via runtimeInputs and should be in PATH
        androidWrapper = pkgs.writeShellScriptBin "wawona-android-wrapper" ''
          set -e
          # Add Android tools to PATH
          export PATH="${pkgs.lib.makeBinPath androidTools}:$PATH"
          
          # Set ANDROID_SDK_ROOT to the Nix-provided SDK
          export ANDROID_SDK_ROOT="${androidSDK.androidsdk}/libexec/android-sdk"
          export ANDROID_HOME="$ANDROID_SDK_ROOT"
          
          exec "${self.packages.${system}.wawona-android}/bin/wawona-android-run" "$@"
        '';
in {
        type = "app";
        program = "${androidWrapper}/bin/wawona-android-wrapper";
        # Provide Android tools via Nix
        runtimeInputs = androidTools;
      };
    });
    
    devShells = forAllSystems (system: let
      pkgs = import nixpkgs { inherit system; };
    in {
      default = pkgs.mkShell {
        name = "wawona-dev";
        buildInputs = with pkgs; [
          cmake
          meson
          ninja
          pkg-config
          autoconf
          automake
          libtool
          texinfo
          git
          python3
          direnv
          gnumake
          patch
          bison
          flex
          shaderc
          mesa
          dialog
        ];
        shellHook = ''
            echo "🔨 Wawona Development Environment"
            echo "Run 'nix run' to build Wawona for all platforms (iOS, macOS, Android)"
            echo ""
            echo "Available builds:"
            echo "  - nix build .#wawona-ios      (iOS)"
            echo "  - nix build .#wawona-macos   (macOS)"
            echo "  - nix build .#wawona-android (Android)"
            echo ""
            echo "Dependencies are automatically built as needed."
        '';
      };
    });
  };
}
