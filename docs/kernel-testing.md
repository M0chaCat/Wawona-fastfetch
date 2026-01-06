# Wawona iOS Kernel Testing

## Overview

The Wawona iOS Kernel test suite validates process spawning capabilities on jailed iOS devices using the app extension architecture.

## Running Tests

### Command

```bash
nix run .#wawona-kernel-ios
```

This command:
1. Builds the iOS app with kernel test mode enabled
2. Launches iOS Simulator
3. Installs and runs the app
4. Automatically runs comprehensive kernel tests

### What Gets Tested

The kernel test suite validates three critical components:

1. **hello_world** - Basic binary spawning
   - Tests: Process spawning via extension
   - Validates: Basic posix_spawn functionality

2. **ssh** - OpenSSH binary spawning
   - Tests: SSH binary execution
   - Validates: Complex binary spawning with dependencies

3. **waypipe** - Waypipe binary spawning
   - Tests: Waypipe execution
   - Validates: Full process spawning with environment setup

## Test Implementation

### Test Flow

```
Main App (Wawona)
  ↓ WAWONA_KERNEL_TEST=1
  ↓ [WawonaKernel runKernelTests]
  ↓ Test 1: hello_world
  ↓ Test 2: ssh  
  ↓ Test 3: waypipe
  ↓ Results logged
```

### Test Code Location

- **Test Implementation**: `src/core/WawonaKernelTests.m`
- **Test Header**: `src/core/WawonaKernelTests.h`
- **Test Trigger**: `src/core/main.m` (checks `WAWONA_KERNEL_TEST` env var)

### Environment Variables

The test is controlled by environment variables:

- `WAWONA_KERNEL_TEST=1` - Enables kernel test mode
- `WAWONA_IOS_FOLLOW_LOGS=1` - Follows logs in real-time
- `WAWONA_IOS_LOG_LEVEL=debug` - Sets log level to debug

## Expected Output

When tests run successfully, you should see:

```
[WawonaKernel] ========================================
[WawonaKernel] Starting Comprehensive Kernel Tests
[WawonaKernel] ========================================
[WawonaKernel] Test 1: Spawning hello_world
[WawonaKernel] ✅ hello_world spawned successfully with PID: <pid>
[WawonaKernel] Test 2: Spawning ssh
[WawonaKernel] ✅ ssh spawned successfully with PID: <pid>
[WawonaKernel] Test 3: Spawning waypipe
[WawonaKernel] ✅ waypipe spawned successfully with PID: <pid>
[WawonaKernel] ========================================
[WawonaKernel] Kernel Tests Completed
[WawonaKernel] ========================================
```

## Troubleshooting

### Tests Don't Run

1. **Check environment variable**: Ensure `WAWONA_KERNEL_TEST=1` is set
2. **Check extension**: Verify `WawonaSSHRunner.appex` is built and bundled
3. **Check binaries**: Ensure `hello_world`, `ssh`, and `waypipe` are in `bin/` directory

### Spawn Failures

1. **Check logs**: Look for error messages in simulator logs
2. **Check code signing**: Ensure extension and binaries are properly signed
3. **Check App Group**: Verify `group.com.aspauldingcode.Wawona` is configured

### Extension Not Found

1. **Check bundle**: Verify extension is in `PlugIns/WawonaSSHRunner.appex/`
2. **Check Info.plist**: Verify extension identifier matches
3. **Check entitlements**: Ensure App Group is configured

## Architecture

The kernel tests use the same architecture as production:

- **Main App**: Initiates spawn requests via `WawonaKernel`
- **Extension**: Receives requests and executes `posix_spawn`
- **Process**: Spawned with proper environment and arguments

This validates that the entire process spawning pipeline works correctly.
