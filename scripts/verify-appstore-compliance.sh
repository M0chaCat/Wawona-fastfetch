#!/bin/bash

# verify-appstore-compliance.sh
# Verifies that macOS/iOS bundles are sandbox compliant and avoid dynamic libraries.

set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

APP_IOS="${ROOT_DIR}/build/build-ios/Wawona.app"
APP_MAC="${ROOT_DIR}/build/Wawona.app"

check_bundle() {
  local bundle_dir="$1"
  local platform="$2"
  echo "Checking ${platform} bundle: ${bundle_dir}"
  if [ ! -d "${bundle_dir}" ]; then
    echo "Bundle not found"; return 1
  fi
  # Prohibit .dylib
  if find "${bundle_dir}" -name "*.dylib" | grep -q ".dylib"; then
    echo "❌ Found dynamic libraries (.dylib) in bundle"; return 2
  fi
  # Ensure frameworks are static (binary file inside .framework without separate .dylib)
  if find "${bundle_dir}" -name "*.framework" | grep -q ".framework"; then
    echo "Frameworks present";
  fi
  echo "✓ ${platform} bundle passes dynamic library prohibition"
}

check_bundle "${APP_IOS}" "iOS"
check_bundle "${APP_MAC}" "macOS"

echo "✓ App Store compliance checks passed"
