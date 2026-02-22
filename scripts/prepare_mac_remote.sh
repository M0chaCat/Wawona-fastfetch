#!/bin/bash

# Wawona Remote Preparation Script
# This script verifies that your macOS host is ready to serve applications
# to the Wawona iOS/Android app via Waypipe.

echo "--- Wawona Mac Readiness Check ---"

# 1. Check SSH
if systemsetup -getremotelogin | grep -q "On"; then
    echo "✅ Remote Login (SSH) is ENABLED."
else
    echo "❌ Remote Login (SSH) is DISABLED."
    echo "   Action: Enable 'Remote Login' in System Settings > General > Sharing."
fi

# 2. Check Waypipe (System or Nix)
WAYPIPE_PATH=$(command -v waypipe)
if [ -n "$WAYPIPE_PATH" ]; then
    echo "✅ System waypipe found: $WAYPIPE_PATH"
else
    # Check if Nix waypipe is available in the repo
    if [ -f "$HOME/Wawona/flake.nix" ]; then
        echo "🟡 System waypipe not found, but Wawona repo detected."
        echo "   Checking if Nix waypipe works..."
        if nix build "$HOME/Wawona#waypipe" --no-link >/dev/null 2>&1; then
            echo "✅ Nix waypipe is buildable."
            # Find the store path
            NIX_WAYPIPE=$(nix build "$HOME/Wawona#waypipe" --print-out-paths --no-link)
            echo "   Store path: $NIX_WAYPIPE"
            echo "   Action: Ensure '$NIX_WAYPIPE/bin' is in your SSH non-interactive PATH."
            echo "           Or add 'export PATH=\$PATH:$NIX_WAYPIPE/bin' to your ~/.zshenv"
        else
            echo "❌ Nix waypipe failed to build."
        fi
    else
        echo "❌ waypipe NOT found and ~/Wawona/flake.nix missing."
        echo "   Action: Install waypipe or ensure the Wawona repo is at ~/Wawona."
    fi
fi

# 4. Check Weston Terminal
if [ -f "$HOME/Wawona/flake.nix" ]; then
    echo "✅ Wawona repo found at ~/Wawona."
    echo "   Checking weston-terminal..."
    if nix build "$HOME/Wawona#weston-terminal" --no-link >/dev/null 2>&1; then
        echo "✅ weston-terminal is ready to run via Nix."
    else
        echo "❌ weston-terminal build failed."
    fi
else
    echo "❌ Wawona repo NOT found at ~/Wawona."
    echo "   Action: Clone the repo to ~/Wawona for the default nix command to work."
fi

echo "--- Summary ---"
echo "To run weston-terminal on your iOS/Android device:"
echo "1. Set 'SSH Host' to this Mac's IP ($(ifconfig | grep "inet " | grep -v 127.0.0.1 | awk '{print $2}' | head -n 1))."
echo "2. Set 'Remote Command' to: nix run ~/Wawona#weston-terminal"
echo "3. Tap 'Start Waypipe' in the app."
