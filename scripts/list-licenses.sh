#!/usr/bin/env bash
# List Rust crate licenses for Wawona (for NOTICE / third-party attribution).
# Run from repo root, ideally inside `nix develop` so cargo is available.
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v cargo &> /dev/null; then
    echo "cargo not found. Run from a Nix dev shell: nix develop" >&2
    exit 1
fi

if ! cargo license --version &> /dev/null; then
    echo "cargo-license not installed. Install with: cargo install cargo-license" >&2
    exit 1
fi

echo "Rust crate licenses (run from $ROOT):"
echo "---"
cargo license --tsv

if [ -n "${SAVE_JSON:-}" ]; then
    cargo license --json > docs/cargo-licenses.json
    echo "Wrote docs/cargo-licenses.json"
fi
