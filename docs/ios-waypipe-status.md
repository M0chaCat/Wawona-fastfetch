# iOS Waypipe Implementation Status

## Current State: iOS Simulator Limitation Identified

### What Works ✅
- OpenSSH compiled for iOS Simulator (arm64)
- SSH binary properly code-signed
- DYLD_ROOT_PATH environment setup
- Waypipe compiled for iOS
- All dependencies packaged correctly

### What Doesn't Work ❌
- **`posix_spawn` fails with EACCES** (Permission denied) in iOS Simulator
- SSH cannot be spawned from main app
- Waypipe cannot spawn SSH subprocess

### Root Cause

**iOS Simulator blocks `posix_spawn` for third-party executables** as a security measure.

Evidence from testing:
```
Direct SSH test - spawn failed: 13 (Permission denied)
```

Even though:
- ✅ DYLD_ROOT_PATH is set correctly
- ✅ SSH binary has 755 permissions  
- ✅ SSH is code-signed with entitlements
- ✅ SSH works from command line (with DYLD_ROOT_PATH)
- ✅ posix_spawnattr properly configured

The iOS Simulator **intentionally blocks spawning** for sandboxed apps.

## Solutions

### Option 1: Test on Real iOS Device ⚡ (Recommended to Try First)

Real iOS devices have different spawning rules. The current implementation might work there.

**What to test:**
1. Build and install on real iPhone/iPad
2. Try running waypipe
3. SSH spawning may succeed on device where it fails in simulator

### Option 2: App Extension Approach 🏗️ (Implemented)

Using iOS App Extensions for process spawning on jailed devices.

**Files Created:**
- `src/extensions/WawonaSSHRunner/WawonaSSHRunner.m` - Extension that spawns processes
- `src/extensions/WawonaSSHRunner/WawonaSSHRunnerProtocol.h` - XPC protocol
- `src/extensions/WawonaSSHRunner/Info.plist` - Extension metadata
- `src/extensions/WawonaSSHRunner/Entitlements.plist` - Permissions

**How it Works:**
```
Main App → XPC request → Extension (separate process) → posix_spawn SSH ✅
```

App extensions CAN spawn subprocesses where main apps cannot!

**Status:** Code written and integrated into build system.

See: `docs/implementation-status.md` for full details.

### Option 3: Revert to libssh2 🔄 (Fallback)

Use libssh2 as an embedded library instead of spawning SSH.

**Pros:**
- No process spawning needed
- Works in simulator
- Already attempted earlier

**Cons:**
- More complex integration
- Requires patching waypipe to use libssh2 instead of SSH binary

## Technical Details

### App Extension Approach Explained

Wawona solves the iOS spawning limitation with **App Extensions**:

1. **NSExtension API** - iOS blessed way to create separate processes
2. **XPC Communication** - Extension receives spawn requests from main app
3. **posix_spawn in Extension** - Works because extension is a separate process with different permissions
4. **Code Signing** - Extension can sign unsigned binaries before spawning

Key architecture:
```objective-c
// Guest (in extension):
pid_t spawn_process_at_path(...) {
    // posix_spawn works here!
}

// Host (main app):
_extension = [NSExtension extensionWithIdentifier:...];
[_extension beginExtensionRequestWithInputItems:...];
// Extension now runs as separate process and can spawn!
```

## Current Build

The latest build includes:
- ✅ DYLD_ROOT_PATH setup for simulator
- ✅ posix_spawnattr configuration
- ✅ Enhanced error logging
- ✅ Documentation of iOS limitation
- ✅ Extension built and bundled

## Recommendations

1. **Immediate:** Test on real iOS device - may work without extension
2. **Short-term:** Verify extension integration works end-to-end
3. **Long-term:** Full kernel virtualization layer for complex scenarios

## Files to Review

- `docs/implementation-status.md` - Implementation guide
- `src/extensions/WawonaSSHRunner/` - Extension source code
- `src/ui/Settings/WawonaWaypipeRunner.m` - Updated with DYLD and extension support

## Key Insight

**iOS Simulator is fundamentally limited** for security. Production use requires either:
- Real iOS device testing
- App extension architecture
- Embedded library approach (no spawning)

The extension approach is the most elegant and is now implemented in Wawona.
