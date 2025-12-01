# Wawona Compositor Makefile
# Simplified targets for common operations

.PHONY: help compositor stop-compositor clean-compositor \
        deps-macos ios-compositor ios-compositor-fast clean-ios-compositor \
        clean clean-deps macos-compositor android-compositor Wawona

# Default target
.DEFAULT_GOAL := help

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[0;33m
BLUE := \033[0;34m
RED := \033[0;31m
NC := \033[0m # No Color

# Directories
BUILD_DIR := build
ROOT_DIR := $(shell pwd)

# Binaries
COMPOSITOR_BIN := $(BUILD_DIR)/Wawona
IOS_COMPOSITOR_BIN := $(BUILD_DIR)/build-ios/Wawona.app/Wawona
MACOS_COMPOSITOR_BIN := $(BUILD_DIR)/Wawona.app/Contents/MacOS/Wawona

help:
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo "$(BLUE)🔨 Wawona Compositor Makefile$(NC)"
	@echo "$(BLUE)━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━$(NC)"
	@echo ""
	@echo "$(GREEN)Available targets:$(NC)"
	@echo ""
	@echo "  $(YELLOW)make macos-compositor$(NC)  - Build and run Wawona for macOS (includes deps)"
	@echo "  $(YELLOW)make ios-compositor$(NC)    - Build and run Wawona for iOS Simulator (includes deps)"
	@echo "  $(YELLOW)make ios-compositor-fast$(NC) - Rebuild iOS compositor only (skips deps if already built)"
	@echo "  $(YELLOW)make clean$(NC)             - Clean all build artifacts"
	@echo "  $(YELLOW)make android-compositor$(NC) - Build and run Wawona for Android (uses emulator)"
	@echo "  $(YELLOW)make Wawona$(NC)             - Build iOS, macOS, and Android in parallel with combined logs"
	@echo ""

# --- Shared Dependency Logic ---

# Build all dependencies for a specific platform
# Usage: make build-deps PLATFORM=macos
build-deps:
	@echo "$(BLUE)▶$(NC) Building dependencies for $(PLATFORM)"
	@./scripts/install-epoll-shim.sh --platform $(PLATFORM)
	@./scripts/install-libffi.sh --platform $(PLATFORM)
	@./scripts/install-expat.sh --platform $(PLATFORM)
	@./scripts/install-libxml2.sh --platform $(PLATFORM)
	@./scripts/install-wayland.sh --platform $(PLATFORM)
	@./scripts/install-wayland-protocols.sh --platform $(PLATFORM)
	@./scripts/install-pixman.sh --platform $(PLATFORM)
	@./scripts/install-xkbcommon.sh --platform $(PLATFORM)
	@if [ "$(PLATFORM)" = "macos" ] || [ "$(PLATFORM)" = "ios" ]; then \
		./scripts/install-kosmickrisp.sh --platform $(PLATFORM); \
		./scripts/install-angle.sh --platform $(PLATFORM); \
	fi
	@# Build Waypipe
	@./scripts/install-ffmpeg.sh --platform $(PLATFORM)
	@./scripts/install-lz4.sh --platform $(PLATFORM)
	@./scripts/install-zstd.sh --platform $(PLATFORM)
	@./scripts/install-waypipe.sh --platform $(PLATFORM)
	@echo "$(GREEN)✓$(NC) $(PLATFORM) dependencies built"

# --- macOS Targets ---

# Build and run macOS compositor (full stack)
macos-compositor:
	@$(MAKE) build-deps PLATFORM=macos
	@echo "$(BLUE)▶$(NC) Building macOS Compositor"
	@mkdir -p $(BUILD_DIR)
	@cd $(BUILD_DIR) && cmake .. && make -j$(shell sysctl -n hw.ncpu)
	@echo "$(GREEN)✓$(NC) Build complete"
	@echo "$(BLUE)▶$(NC) Running Compositor"
	@if [ -f "$(MACOS_COMPOSITOR_BIN)" ]; then \
	  $(MACOS_COMPOSITOR_BIN) 2>&1 | tee $(BUILD_DIR)/macos-run.log; \
	else \
	  echo "$(RED)✗$(NC) macOS app bundle binary not found at $(MACOS_COMPOSITOR_BIN)"; \
	  exit 1; \
	fi

# Alias for backward compatibility
compositor: macos-compositor

# Build iOS and macOS in parallel with tagged, combined stdout
Wawona:
	@echo "$(BLUE)▶$(NC) Building iOS, macOS, and Android in parallel..."
	@mkdir -p $(BUILD_DIR)/parallel-logs
	@IOS_LOG=$(BUILD_DIR)/parallel-logs/ios.log; MAC_LOG=$(BUILD_DIR)/parallel-logs/macos.log; AND_LOG=$(BUILD_DIR)/parallel-logs/android.log; \
	 echo "$(BLUE)▶$(NC) Starting iOS build..."; \
	 $(MAKE) ios-compositor > $$IOS_LOG 2>&1 & IOS_PID=$$!; \
	 echo "$(BLUE)▶$(NC) Starting macOS build..."; \
	 $(MAKE) macos-compositor > $$MAC_LOG 2>&1 & MAC_PID=$$!; \
	 echo "$(BLUE)▶$(NC) Starting Android build..."; \
	 $(MAKE) android-compositor > $$AND_LOG 2>&1 & AND_PID=$$!; \
	 ( tail -f -n +1 $$IOS_LOG | sed -e 's/^/[iOS] /' ) & IOS_TAIL=$$!; \
	 ( tail -f -n +1 $$MAC_LOG | sed -e 's/^/[macOS] /' ) & MAC_TAIL=$$!; \
	 ( tail -f -n +1 $$AND_LOG | sed -e 's/^/[Android] /' ) & AND_TAIL=$$!; \
	 wait $$IOS_PID; IOS_STATUS=$$?; \
	 wait $$MAC_PID; MAC_STATUS=$$?; \
	 wait $$AND_PID; AND_STATUS=$$?; \
	 kill $$IOS_TAIL $$MAC_TAIL $$AND_TAIL >/dev/null 2>&1 || true; \
	 echo "$(BLUE)▶$(NC) iOS build exit code: $$IOS_STATUS"; \
	 echo "$(BLUE)▶$(NC) macOS build exit code: $$MAC_STATUS"; \
	 echo "$(BLUE)▶$(NC) Android build exit code: $$AND_STATUS"; \
	 if [ $$IOS_STATUS -ne 0 ] || [ $$MAC_STATUS -ne 0 ] || [ $$AND_STATUS -ne 0 ]; then \
	   echo "$(RED)✗$(NC) One or more builds failed. See logs in $(BUILD_DIR)/parallel-logs"; \
	   exit 2; \
	 else \
	   echo "$(GREEN)✓$(NC) All builds completed successfully"; \
	 fi

# --- iOS Targets ---

# Check if iOS dependencies are already built
# Returns 0 if deps exist, 1 if they need to be built
check-ios-deps:
	@if [ -d "ios-dependencies/lib" ] && [ -f "ios-dependencies/lib/libwayland-server.a" ] && [ -f "ios-dependencies/lib/libvulkan_kosmickrisp.a" ]; then \
		 echo "$(GREEN)✓$(NC) iOS dependencies already built"; \
		 exit 0; \
	 else \
		 echo "$(YELLOW)ℹ$(NC) iOS dependencies not found, will build them"; \
		 exit 1; \
	 fi

# Build iOS dependencies (if not already built)
build-ios-deps:
	@echo "$(BLUE)▶$(NC) Building iOS Dependencies"
	@# Ensure build tools are available (cmake, pkg-config)
	@./scripts/install-host-cmake.sh
	@./scripts/install-host-pkg-config.sh
	@# Build all dependencies for iOS platform
	@echo "$(BLUE)▶$(NC) Building dependencies for ios"
	@./scripts/install-epoll-shim.sh --platform ios
	@./scripts/install-libffi.sh --platform ios
	@./scripts/install-expat.sh --platform ios
	@./scripts/install-libxml2.sh --platform ios
	@./scripts/install-wayland.sh --platform ios
	@./scripts/install-wayland-protocols.sh --platform ios
	@./scripts/install-pixman.sh --platform ios
	@./scripts/install-xkbcommon.sh --platform ios
	@# Build KosmicKrisp (Vulkan)
	@./scripts/install-kosmickrisp.sh --platform ios
	@# Build Waypipe dependencies
	@./scripts/install-ffmpeg.sh --platform ios
	@./scripts/install-lz4.sh --platform ios
	@./scripts/install-zstd.sh --platform ios
	@./scripts/install-waypipe.sh --platform ios
	@echo "$(GREEN)✓$(NC) ios dependencies built"

# Build and launch iOS compositor (shared logic)
build-launch-ios:
	@# Build Wawona iOS
	@./scripts/generate-cross-ios.sh # Ensure cross file is up to date
	@mkdir -p $(BUILD_DIR)/build-ios
	@cd $(BUILD_DIR)/build-ios && export PATH="$(ROOT_DIR)/build/ios-bootstrap/bin:$$PATH" && cmake -DCMAKE_TOOLCHAIN_FILE=../../dependencies/wayland/toolchain-ios.cmake -DCMAKE_SYSTEM_NAME=iOS -G "Unix Makefiles" ../.. && make -j$(shell sysctl -n hw.ncpu)
	@echo "$(GREEN)✓$(NC) iOS Build Complete"
	@echo "$(BLUE)▶$(NC) Launching in Simulator..."
	@# Simple launch logic - use xcrun simctl
	@DEVICE_ID=$$(xcrun simctl list devices available | grep "Booted" | grep -v "Watch" | head -1 | grep -oE "[0-9A-F-]{36}"); \
	if [ -z "$$DEVICE_ID" ]; then \
		DEVICE_ID=$$(xcrun simctl list devices available | grep "iPhone" | head -1 | grep -oE "[0-9A-F-]{36}"); \
		xcrun simctl boot $$DEVICE_ID || true; \
	fi; \
	open -a Simulator; \
	xcrun simctl install $$DEVICE_ID $(BUILD_DIR)/build-ios/Wawona.app; \
	xcrun simctl launch --console-pty $$DEVICE_ID com.aspauldingcode.Wawona 2>&1 | tee $(BUILD_DIR)/ios-run.log

# Build all iOS dependencies and the compositor
ios-compositor:
	@echo "$(BLUE)▶$(NC) Building iOS Compositor and Dependencies"
	@$(MAKE) build-ios-deps || true
	@$(MAKE) build-launch-ios

# Fast rebuild: skip dependencies if already built
ios-compositor-fast:
	@echo "$(BLUE)▶$(NC) Fast rebuild iOS Compositor (skipping deps if already built)"
	@$(MAKE) check-ios-deps || $(MAKE) build-ios-deps
	@$(MAKE) build-launch-ios

# Helper to test connection information
test-ios-connection:
	@./scripts/test-ios-connection.sh

# Run Weston in Colima connected to iOS
ios-colima-client:
	@./scripts/ios-colima-client.sh || true

# Run Weston in Colima connected to macOS compositor
colima-client:
	@./scripts/colima-client.sh || true

# --- Clean ---

clean:
	@echo "$(YELLOW)ℹ$(NC) Cleaning build directory..."
	@rm -rf $(BUILD_DIR)
	@echo "$(GREEN)✓$(NC) Cleaned"

# Remove all dependency build and install artifacts for a from-scratch build
clean-deps:
	@echo "$(YELLOW)ℹ$(NC) Cleaning dependency build artifacts..."
	@rm -rf \
		ios-dependencies \
		macos-dependencies \
		android-dependencies \
		$(BUILD_DIR)/ios-bootstrap \
		$(BUILD_DIR)/macos-bootstrap
	@rm -rf dependencies/*/build-* dependencies/*/build \
		dependencies/*/meson-* dependencies/*/target \
		dependencies/*/out \
		dependencies/kosmickrisp/build-* \
		dependencies/waypipe/target
	@echo "$(GREEN)✓$(NC) Dependency artifacts cleaned"

# Alias: full clean removes both project build and dependencies
clean-all: clean clean-deps
# Android build and run via the android_make subproject
android-compositor:
	@echo "$(BLUE)▶$(NC) Building and running Android compositor..."
	@mkdir -p $(BUILD_DIR)
	@bash -c 'set -o pipefail; ./scripts/android-compositor.sh | tee $(BUILD_DIR)/android-run.log'
	@echo "$(GREEN)✓$(NC) Android build complete"
