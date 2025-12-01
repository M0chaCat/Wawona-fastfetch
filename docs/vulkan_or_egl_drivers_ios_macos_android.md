Skip to content

You said:
opengl and egl / opengl es stuff seems to be deprecated. Is that ok?
ChatGPT said:
Short answer: Yes, it’s “okay,” but only if you understand what Apple means by “deprecated” and what your goals are.
Long answer below, broken down clearly:
✅ Is it okay that OpenGL / OpenGL ES / EGL are deprecated on Apple platforms?
1. What “deprecated” means on Apple platforms
Apple deprecated OpenGL, OpenGL ES, and EGL-like APIs in 2018, but:
They are still present on macOS and iOS.
They still run on Apple Silicon (through a translation layer).
They are not removed and Apple has never set a removal date.
Apple deprecates things to discourage new development, not to instantly break old software.
👉 Your OpenGL/EGL code will still run, but Apple won’t fix bugs or add features.

2. For a Window Manager / Desktop Environment on macOS — is this acceptable?
✔ If your goal is to bootstrap Wayland/X11/XWayland, YES, it's acceptable.
Many projects still rely on OpenGL ES → Metal translation layers:
XQuartz uses an OpenGL-over-Metal strategy.
MoltenVK uses Vulkan-over-Metal and provides EGL via EGL_MESA_platform_surfaceless.
ANGLE can provide ES2/ES3 on top of Metal.
So relying on:
EGL for Wayland compositors
OpenGL ES for XWayland / GLX compatibility
…is still viable on macOS as long as you accept the risks.
3. But there is a better long-term path: Metal-backed EGL/OpenGL
Since you’re building:
A compositor
A display manager
A desktop environment
macOS + Wayland hybrid environment
You want GPU acceleration you can trust.
The best options:

⭐ Option A — Use ANGLE (Metal backend)
ANGLE now supports:
OpenGL ES → Metal
EGL → Native surfaces
Working on macOS + iOS
This is currently the cleanest way to get EGL on macOS without writing a renderer twice.
⭐ Option B — Use MoltenVK + EGL-on-Vulkan (MESA)
Since you already have:
“wayland and kosmickrisp framework for vulkan driver”
this is powerful.
MESA can give you:
libEGL
libGLESv2
EGL platform via Vulkan
Surfacing via your compositor
This avoids Apple’s deprecated stack entirely.
4. So is using deprecated OpenGL/EGL dangerous?
👍 For internal development, prototyping, research tools → YES, it’s fine.
Apple won’t remove it suddenly—too many apps depend on it.
⚠️ For long-term production, high-performance compositors → I wouldn’t rely on it.
Better to:
Provide EGL via a Vulkan or Metal backend
Let your compositor talk to Vulkan/Metal directly
Use ANGLE or MESA only for compatibility layers
5. Your best path moving forward (for your DE/Window Manager work)
Based on your stack:
🔥 Recommended Architecture
Vulkan driver (KosmicKrisp) → Provides GPU access
MESA EGL → Interface for Wayland protocols
XWayland → Requires GL ES → Provided via MESA/ANGLE
Your compositor → Renders with Vulkan
macOS surfaces → Via your CGWindow / CALayer injection layer
This gives:
No reliance on deprecated Apple APIs
Portable (Linux + macOS)
Future-proof
All GPU paths under your control
🚀 Final Answer
Yes, it is “ok” that OpenGL/EGL/OpenGL ES are deprecated — you can still use them — but for a production compositor or DE on macOS, you should avoid using Apple’s deprecated GL stack and instead use Metal-backed ANGLE or Vulkan-backed MESA EGL.
If you want, I can lay out:

A diagram of the optimal architecture
A compatibility layer plan
A step-by-step guide to building EGL-on-Vulkan for macOS
Or instructions for bringing ANGLE into your compositor
Just say the word.
You said:
I don't want to use depricated sutff. I already use Vulkan 1.3 conformant MESA drivers on macos/ios using kosmickrisp driver.. can I also use ANGLE?
ChatGPT said:
Yes — you can absolutely use ANGLE on macOS/iOS alongside your Vulkan 1.3 MESA/KosmickKrisp stack, and it’s fully compatible with your goal of avoiding all deprecated Apple APIs.
Below is the exact compatibility picture you should know.

✅ ANGLE on macOS/iOS (no deprecated APIs required)
Modern ANGLE provides three backends:
ANGLE Backend	Supported on macOS/iOS?	Uses deprecated API?
OpenGL	❌ No	✔ Deprecated OpenGL
D3D11	❌ No	—
Metal	✅ Yes	❌ No
Vulkan (WIP)	⚠️ Partial	❌ No (if using your Vulkan stack)
The key point:
ANGLE’s Metal backend does not use OpenGL at all. No deprecated Apple APIs. Completely allowed.
So ANGLE is safe.
🔥 How ANGLE helps your compositor / DE / XWayland plan
ANGLE gives you:
libEGL
libGLESv2
GL ES 2.0/3.0/3.1 implementation
Backed by Metal, not OpenGL
This means:
You get EGL and GLES without touching Apple’s deprecated OpenGL stack
XWayland (and many GL apps) can run on top of your compositor through ANGLE
Every GL call becomes a Metal call → works on macOS and iOS
And since you already have:
Vulkan 1.3 conformant MESA drivers using KosmicKrisp
You can combine ANGLE + Vulkan + Metal exactly how you want.
💡 Two ways you can use ANGLE with your existing Vulkan/MESA stack
Option 1 — ANGLE → Metal (recommended)
ANGLE uses Metal as its backend.
Your compositor uses Vulkan.
ANGLE uses Metal.
No conflict.

This is the simplest setup and ensures:

Stability
Performance
iOS + macOS support
No deprecated APIs
Architecture:
ANGLE (EGL/GLES)
       ↓
   Metal backend
       ↓
Window surfaces (CALayer/your compositor)
Option 2 — ANGLE → Vulkan (experimental, not fully stable yet)
ANGLE supports a Vulkan backend, but it is not as polished on macOS as the Metal one.
However, you could route ANGLE → Vulkan → KosmicKrisp driver.

Possible? Yes. Mature? Not really.

But since:

You already supply a Vulkan 1.3 conformant driver
You can potentially make this work.
Just know:
ANGLE’s Metal backend is way more maintained for Apple platforms.
ANGLE’s Vulkan backend is mainly maintained for Windows/Linux.
⚠️ Important for iOS
On iOS, Apple officially allows:
Metal
Vulkan through MoltenVK or custom low-level drivers (like your KosmicKrisp)
GLES through ANGLE → Metal
Apple does not allow:
Shipping deprecated GL ES frameworks
Linking OpenGL or OpenGL ES system frameworks
Since ANGLE uses Metal, it is App Store legal.
🧠 Your best configuration
Since your project is a cross-platform macOS DE + Wayland compositor:
⭐ Best:
EGL/GLES through ANGLE + Metal backend
Compositor rendering through Vulkan (KosmicKrisp)
Optional fallback:
EGL/MESA on Vulkan for Wayland-specific protocols.
This gives:

Zero deprecated APIs
iOS + macOS support
Maximum compatibility with XWayland
Modern GPU paths (Metal + Vulkan only)
🎉 Final Answer
Yes — you can (and should) use ANGLE on macOS/iOS.
Use the Metal backend, and you will avoid all deprecated APIs while gaining full EGL/GLES support for your DE/compositor, with perfect compatibility for XWayland and GL apps.
If you want, I can provide:

A full build guide for ANGLE-for-macOS/iOS
A compatibility architecture diagram
Integration instructions for Wayland/XWayland and your Vulkan compositor
Just tell me what you want next.
You said:
is there an android opengl / opengl es / egl mesa driver? similar to freedreno turnip vulkan MESA driver for supported chipsets..?
ChatGPT said:
Good question — yes: there are efforts to provide Mesa-based drivers (OpenGL / OpenGL ES / EGL / Vulkan) for Android, similar in spirit to how Freedreno / Turnip work for Qualcomm Adreno hardware under Linux. 
people.freedesktop.org
+2
Mesa 3D Graphics Library
+2
✅ What exists today — Mesa drivers on Android
Mesa supports building for Android via its build system (using Android NDK + Meson). 
people.freedesktop.org
+1
You can enable GLES and EGL support when building Mesa for Android by setting -D egl=true, -D gles1=true, -D gles2=true, and choosing appropriate Gallium (or DRI) drivers. 
Mesa 3D Graphics Library
+2
Mesa Documentation
+2
For Qualcomm Adreno GPUs, there is active support via Freedreno (for OpenGL / OpenGL ES) and Turnip (for Vulkan). 
Mesa 3D Graphics Library
+2
Phoronix
+2
There are even community projects packaging Mesa + Freedreno/Turnip for Android (for example in chroot/container environments like Termux, or for non-standard uses). 
GitHub
+2
GitHub
+2
⚠️ What’s not trivial — limitations & caveats
To run Mesa drivers on Android (outside of the vendor-provided official GPU driver stack), you often need kernel support (e.g. for DRM / KGSL) or a custom environment (like a Linux container, chroot, or custom ROM). This isn’t guaranteed on all devices. For Freedreno/Turnip to work properly, the kernel must expose the needed GPU / DRM / KGSL interfaces. 
cgit.freedesktop.org
+2
GitHub
+2
The official Android graphics stack (on many phones/tablets) is usually closed-source vendor-provided drivers. Replacing that stack with Mesa-based drivers tends to be experimental; stability and coverage can vary depending on hardware.
Building and deploying Mesa on Android tends to be more involved than a “normal” PC Linux build — you need NDK, cross-compile, and sometimes additional patches or kernel modifications depending on target hardware. 
people.freedesktop.org
+2
gallium.readthedocs.io
+2
🎯 So: Is there a “Mesa + OpenGL ES / EGL” driver ecosystem for Android? — Yes, but mostly for certain GPUs and use-cases
If your Android target uses a supported GPU (especially Qualcomm Adreno 2xx–6xx/7xx), then Mesa + Freedreno (for GL/GLES) + Turnip (for Vulkan) provide a viable open-source driver stack on Android. For other GPUs: support depends heavily on driver maturity, kernel interfaces, and community effort (or vendor support).
💡 What that means — and when it might be useful
You could build a custom Android environment (or use a container/chroot-based Linux-on-Android setup) that relies on Mesa + Freedreno/Turnip to get:
EGL / OpenGL ES support
Vulkan support via Turnip (on supported Adreno hardware)
A more “open” graphics stack, easier to inspect or modify
This could be useful for development, experimentation, or running a more desktop-like graphics stack on Android (similar to what you’re doing on macOS).
If you like — I can check current (2025) hardware coverage: which GPUs (Adreno, Mali, etc.) have working Mesa-based EGL/ES/Vulkan drivers for Android — with a small table.
That might help you pick viable targets. Do you want me to build that table now?
You said:
search web for what drivers I can use to get vulkan on android, or to get egl/opengl/opengl es drivers on android..
ChatGPT said:
Good questions. I did a web search — there are real efforts to give Android devices working open-source graphics drivers (Vulkan, EGL / OpenGL ES) using Mesa 3D Graphics Library (and related drivers) — but the situation depends heavily on the GPU. I collected what I found below.
✅ What works — GPUs / drivers that support Vulkan or OpenGL ES via Mesa on Android
Freedreno + Turnip for Qualcomm Adreno GPUs
Freedreno is Mesa’s open-source driver for Adreno 2xx–6xx (and some newer) GPUs, implementing OpenGL and OpenGL ES (up to GLES 3.2) and desktop OpenGL 4.5. 
Mesa 3D Graphics Library
+1
Turnip is the Vulkan driver inside Mesa for Adreno 6xx (and newer) GPUs.
Mesa 3D Graphics Library
+2
GitHub
+2
There are community projects packaging Mesa + Freedreno/Turnip for Android (e.g. container or rooted setups) so you can run GLES / OpenGL / Vulkan on Adreno hardware outside of the proprietary vendor stack. 
GitHub
+1
Example: a repo “mesa-turnip-android-driver” provides a prebuilt “libvulkan_freedreno.so” that apps can load at runtime. 
GitHub
+1
The “Turnip builder” project explicitly targets newer Snapdragon (Adreno) GPUs and, as of 2025, provides stable builds for recent Android versions (e.g. Android 14+). 
GitHub
+1
→ Conclusion: If your Android device has a recent Adreno GPU (6xx/7xx), Mesa + Freedreno + Turnip represent a viable open-source stack for OpenGL ES, OpenGL, and Vulkan. This is probably the most mature path for open-source graphics drivers on Android today.
⚠️ Limitations / Caveats
The Mesa-on-Android approach tends to require replacing or overriding the vendor-supplied driver stack (often via rooting, Magisk, or using a custom Linux environment on Android). It’s not trivial on a stock Android install. For example, some of the driver packages are delivered as .so libraries to be loaded manually.
GitHub
+1
Not all GPUs are supported. The Freedreno + Turnip path only works (well) on Adreno 6xx/7xx GPUs. Older Adreno (a5xx or below) have limited or no Vulkan support. 
Freedesktop.org
+1
For non-Adreno GPUs (Mali, PowerVR, etc.), open-source driver support on Android is much weaker or more fragmented. While Mesa supports drivers for many GPU architectures in theory (ARM Mali via Panfrost/Lima, Broadcom VideoCore via v3d/vc4, etc.) on Linux desktops. 
Freedesktop People
+1
 But Android-specific support for them (kernel drivers, correct HAL / KGSL / DRM integration, EGL/Vulkan ICDs) is often missing or incomplete.
Even with Adreno + Mesa, there is often a dependency on Android kernel support (e.g. for KGSL — the “Kernel Graphics Support Layer” used by Qualcomm) for Vulkan to work properly. 
Phoronix
+2
GitHub
+2
📚 What types of driver / support stacks exist (or have been tried) on Android
Here’s a quick breakdown of known driver approaches for Android:
Driver / Stack	What it provides on Android	Status / Comments
Mesa + Freedreno (Adreno)	OpenGL, OpenGL ES (via Gallium)	Mature for many Adreno GPUs.
Mesa 3D Graphics Library
+2
Freedesktop.org
+2
Mesa + Turnip (Adreno Vulkan)	Vulkan support	Actively developed; people have built “mesa-turnip-android” and report real Vulkan workloads working. 
GitHub
+2
Phoronix
+2
Mesa on containers / chroot / proot on Android	EGL / GLES / Vulkan in a Linux-on-Android environment	Works for people with rooted or containerized setups. 
GitHub
+1
Vendor-provided drivers (proprietary)	GLES / Vulkan via OEM/SoC driver	Default and most stable; not open-source, sometimes opaque. –
Mesa drivers for other hardware (Mali, Broadcom, etc.)	Theoretically supported for Linux desktops	On Android: support is spotty (kernel & HAL requirements) — not a guarantee.
Freedesktop People
+1
🎯 What this means for you (or if you decide to experiment)
If target device = Qualcomm Snapdragon with Adreno 6xx or 7xx GPU, you have a realistic chance of getting a fully open-source graphics stack on Android with GLES + Vulkan using Mesa / Freedreno / Turnip.
You will likely need to override or replace the vendor GPU driver — either by installing a custom driver library (with Magisk / root) or by using a Linux-on-Android container/chroot.
For non-Adreno GPUs, expect a lot more friction, and possibly no usable open-source Vulkan/GLES stack — unless the community or vendor supplies proper drivers.
If you like — I can pull up a (semi-complete) 2025 list of Android-compatible GPUs + which of them have confirmed working Mesa-based Vulkan or OpenGL ES drivers (with links).
That lets you cross-check against your target hardware.



ChatGPT can make mistakes. Check important info.
