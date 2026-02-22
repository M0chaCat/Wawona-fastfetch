#!/usr/bin/env bash
set -e

# Run cargo-udeps check inside a nix shell with nightly rust
# This script is intended to be run via `nix develop` or `nix-shell`

if ! command -v cargo &> /dev/null; then
    echo "Error: cargo not found. Please run this script inside a nix dev shell."
    exit 1
fi

# Check if we have nightly toolchain or udeps available
if ! cargo --list | grep -q udeps; then
    echo "Error: cargo-udeps not found. Please ensure it is installed in your environment."
    echo "You can enter a dev shell with: nix develop"
    exit 1
fi

echo "Running cargo-udeps check..."
# We use --all-targets --all-features as recommended
# Note: cargo-udeps requires nightly. If the current cargo is not nightly, 
# we might need +nightly if installed via rustup, but in Nix we usually provide
# a overridden cargo that is nightly or includes it.

# Try running directly first (assuming nix provided cargo is sufficient)
if cargo udeps --version &> /dev/null; then
    cargo udeps --all-targets --all-features
else
    # Fallback to +nightly if using rustup-managed setup alongside nix
    cargo +nightly udeps --all-targets --all-features
fi
