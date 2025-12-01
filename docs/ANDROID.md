Wawona Compositor for iOS uses cmake + makefile + ios simulator and also allows to macOS app - both supports full sandbox constraints.


However - I also compile kosmickrisp vulkan driver to these platforms for speedy fast gpu rendering of wayland clients.

One last thing - my compositor uses c/objc and I want to eventually port to android.

So, I created separated android Wawona repository. it uses gradle/lew build system, and makefile sets up all dependencies such as freedreno turnip vulkan driver for supported android devices - and I'm using makefile to set up and install and run android simulator sdk with qemu and able to test the app.

Here's the problem; I want to merge the codebase in as many areas I can. 
Does it even make sense to use kotlin + gradle when I have cmake + objc?
and is it even possible to simplify the codebase sharing based on conditionals alone? 

Like, if android, it will import android gui api and frameworks, and call those for rendering instead of cocoa or uikit/appkit .. right?

Short answer: **yes, you can absolutely unify this**, but **no, Kotlin+Gradle shouldn’t be your core layer** if your compositor’s identity is *C/C/Obj-C + Vulkan/Wayland*.
Android just becomes “another platform backend” in your architecture — *exactly like macOS and iOS already are*.

Below is the cleanest model used by cross-platform engines (*Flutter, Godot, Unreal, Qt, Skia, SDL*) that matches what you're doing.

---

# ✅ Does it make sense to use Kotlin/Gradle when your core is C/ObjC + CMake?

**Yes, but only for the *Java-side shell* of the Android app.**
You don’t want Kotlin to hold any rendering logic or compositor logic.

You want:

### **Android Side (Kotlin/Gradle): Only for:**

* Activity / SurfaceView / SurfaceControl setup
* Asset loading via the Android APIs
* Lifecycle events
* Permissions
* Display configuration
* Passing the Android `ANativeWindow*` into native code

### **Native Side (C/C++/Obj-C via CMake): For EVERYTHING ELSE:**

* Vulkan device/driver setup (freedreno/turnip)
* Wayland compositor logic
* Scene graph
* Layers, surfaces
* Window rules
* Rendering loops
* GPU synchronization
* Event routing (touch, mouse, keyboard)

**This is exactly how:**

* Chrome (Skia + ANGLE)
* Firefox (WebRender)
* Unreal Engine
* Godot
* Flutter (Impeller)
  run on Android.

You keep your core in 99% native code.
Kotlin is just the bootloader and event provider.

---

# ✅ Is it possible to share code using conditionals?

Yes. This is standard practice in high-performance engines.

Your codebase becomes:

```
src/
  core/             <-- 90% of your compositor (platform-agnostic)
  platform/
    macos/
    ios/
    android/
    linux/
  vulkan/
    kosmickrisp/    <-- shared Vulkan backend
    platform/
      android/
      macos/
      ios/
      linux/
```

Then selectively compile per-platform:

### **CMake Conditionals Example**

```cmake
if(APPLE)
    add_definitions(-DWA_PLATFORM_APPLE)
    add_subdirectory(platform/macos)
elseif(ANDROID)
    add_definitions(-DWA_PLATFORM_ANDROID)
    add_subdirectory(platform/android)
endif()
```

### **C/C++ Conditional Example**

```c
#if WA_PLATFORM_ANDROID
#include <android/native_window.h>
#include <android/native_window_jni.h>
#elif WA_PLATFORM_IOS
#import <UIKit/UIKit.h>
#elif WA_PLATFORM_MACOS
#import <AppKit/AppKit.h>
#endif
```

### **ObjC bridging on iOS/macOS**

You already have this. Android simply adds a “platform glue layer”.

---

# ✅ How Android rendering replaces Cocoa/UIKit/AppKit

On Android, you don’t write UI — you attach your compositor to:

* **SurfaceView**
* **SurfaceHolder**
* **Choreographer**
* **ANativeWindow**
* **VulkanSurfaceKHR**

Equivalent mapping:

| Platform | Your API                    | Native Backend                      |
| -------- | --------------------------- | ----------------------------------- |
| macOS    | CALayer + CAMetalLayer      | Vulkan via MoltenVK or custom layer |
| iOS      | CAMetalLayer                | Vulkan reinterpretation layer       |
| Android  | SurfaceView / ANativeWindow | Vulkan via `VK_KHR_android_surface` |
| Linux    | Wayland/X11 surface         | Vulkan                              |

This keeps architecture symmetric:
**Every platform provides “a surface”**.
Your compositor renders into that surface.

---

# ✅ Why NOT write a full-Kotlin compositor?

Because:

* Kotlin/JVM/ART will throttle your compositor
* No direct Vulkan control
* Harder to share native code
* Every Android OEM behaves differently
* Your macOS/iOS C/ObjC engine would become unshareable

Keeping everything **in C/C++ and only using Kotlin as the bootstrap** ensures:

### **🚀 Zero duplication**

### **🚀 Zero divergence**

### **🚀 100% code reuse**

### **🚀 100% consistent behavior across macOS/iOS/Android/Linux**

### **🚀 Vulkan path stays unified**

This is the same architecture all big cross-platform engines use.

---

# ✅ Final Recommendation Architecture

### **1. Core Compositor**

C/C++/ObjC shared across all platforms. No Kotlin/Swift UI.

### **2. Platform Glue Layer**

Minimal platform code providing:

* window/surface
* timing
* input events

### **3. Vulkan Backend**

Kosmickrisp Driver
Shared across all platforms with small platform-specific entrypoints.

### **4. Build System Structure**

* CMake for all native code → all platforms
* Gradle only builds the Android *APK* and loads your CMake output via JNI

### **5. Conditional Compilation**

Yes — this is exactly how to unify.

---

# 🚀 Big Picture

You are essentially building:

**"A cross-platform Wayland/Vulkan compositor engine with platform stubs."**

Which is exactly what Chrome, Godot, and Flutter did.

Your idea is fully correct and absolutely doable — and Kotlin should not replace your core.

If you want, I can sketch:

* your ideal directory tree
* example JNI bridge
* CMakeLists layout
* unified platform abstraction layer
* Android boot skeleton that loads your compositor

Just say **“show the architecture template”**.
