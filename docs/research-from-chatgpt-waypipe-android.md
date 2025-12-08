# Waypipe-Rust and Cross-Platform Graphics - Research from ChatGPT

Waypipe is a Wayland proxy that forwards rendering from a remote client to a local compositor. In its default (GPU) mode, the remote side renders with GPU acceleration and sends the frame as a Linux DMABUF buffer or video bitstream. On the local side, Waypipe reconstructs the image from DMABUF buffers or by decoding the video stream and feeds it into the compositor[1][2]. The Rust reimplementation of Waypipe ("waypipe-rs") uses Vulkan and FFmpeg for DMABUF handling and video encoding[2][3]. Porting waypipe-rs to non-Linux platforms (macOS, iOS, Android) requires dealing with differences in event loops, buffer sharing, and video codecs:

- **Event loop (epoll)**: Wayland and Waypipe expect Linux's epoll. On Darwin (macOS/iOS), use an epoll shim (e.g. [jiixyj/epoll-shim]) that implements epoll via kqueue[4]. This is a known approach for porting Wayland itself to macOS. On Android (Linux kernel), native epoll is available.
- **Wayland libraries**: You must build or port the Wayland (libwayland) stack for each platform. For macOS/iOS, projects like Owl or Wawona provide ports of Wayland/mesa. Once libwayland is available, waypipe-rs can be built against it (for example via Meson/Cargo). On Android, you can compile with NDK or in a Linux container (e.g. Waydroid environment).
- **Desktop compositor**: The local machine needs a Wayland compositor. On macOS/iOS, this means running a custom compositor (like Owl/Wawona) that uses Cocoa/Metal backends. Waypipe-rs simply acts as a Wayland client to that compositor, so the compositor must support the protocols needed. On Android, a Wayland compositor can run as an app or service (e.g. Weston via Waydroid).

## macOS and iOS: DMABUF & Video

On macOS (and similarly iOS), the Linux DMABUF mechanism and libgbm (for buffer allocation) do not exist. In practice this means GPU mode is not directly supported. The common workaround is to disable GPU/DMABUF and fall back to shared-memory (wl_shm) rendering. The Waypipe manpage explicitly notes that you can turn off DMABUF support (or use --no-gpu) to avoid relying on Linux graphics libraries[5]. In fact, others have ported Waypipe to Linux-based phones by disabling DMABUF entirely – one SailfishOS packaging disables both DMABUF and VAAPI due to missing libraries[6]. By analogy, on macOS/iOS you would compile or invoke waypipe-rs without DMABUF; the Rust code will then send raw pixel diffs over the network instead of GPU buffers.

If GPU acceleration is still desired, the Rust code's Vulkan path could run on Apple hardware using MoltenVK (Vulkan-on-Metal). Waypipe-rs's DMABUF handling is implemented with Vulkan and Ash (a Rust Vulkan binding)[2], so in theory MoltenVK allows that code to run. However, the local compositor must accept the buffers. Since macOS does not support Linux DMABUF at all, one would still need to convert incoming images into something the compositor accepts (e.g. upload to a Metal texture or use wl_shm). In short, real DMABUF buffer sharing isn't natively possible on macOS/iOS, so most deployments simply use software mode (or video streaming) for remote apps.

For video encoding, Waypipe-rs uses FFmpeg's hardware encoders (e.g. Vulkan extensions) by default[2]. On Apple platforms you can compile FFmpeg with VideoToolbox support, enabling the H.264/HEVC encoders on Apple Silicon or Intel[2]. In practice, you could build waypipe-rs with FFmpeg and then use --video=hw or --video=sw. If GPU encoding isn't available, software encoding (x264) still works. The result is fed via the same Wayland protocol.

Summary for macOS/iOS: Build waypipe-rs against a Mac port of Wayland (e.g. Owl), using epoll-shim for event loops[4]. Disable or avoid DMABUF (--no-gpu) since macOS has no Linux buffer sharing[5][6]. Use the WL_SHM path (CPU copy) to send frames. The Vulkan/FFmpeg code in waypipe-rs can run via MoltenVK and VideoToolbox for acceleration, but this is optional and the compositor must support the final pixel format. Notably, the Rust DMABUF/video implementation is very FFI-heavy and specific to Linux graphics (it's ~4000 lines of code beyond the C version)[3][7], so expect to disable or adapt those parts on Apple systems.

## Android: Vulkan, AHardwareBuffer and Video

Android is Linux-based, so it inherently supports epoll and (in principle) DMABUF. Recent Android versions provide the AHardwareBuffer API for GPU buffers, which is essentially Android's equivalent of DMABUF. AHardwareBuffers are zero-copy shared memory that can be passed between processes[8]. They can be imported into Vulkan via the VK_ANDROID_external_memory_android_hardware_buffer extension[9]. In practice, a Wayland compositor on Android (such as Wayland support in Waydroid or other stacks) can use AHardwareBuffer under the hood. Thus, waypipe-rs's Vulkan/DMABUF path can work: you send buffers via Linux DMABUF, and the local compositor (if it supports linux-dmabuf protocol) could import them as AHardwareBuffers.

Key points for Android:

- **Event loop**: native epoll (no shim needed).
- **DMABUF**: likely available via AHardwareBuffer/Vulkan. The NDK docs state that passing an AHardwareBuffer between processes creates a "shared view of the same region of memory"[8], and Vulkan can access it as external memory[9]. This means the zero-copy pipeline is possible.
- **Graphics**: Vulkan and OpenGL ES are supported on Android. Waypipe-rs's Vulkan code can use the Android Vulkan loader. If DMABUF fails or isn't supported by the compositor, you can fall back to WL_SHM (software).
- **Video**: FFmpeg can be built with Android support. You could use software codecs or possibly Android's MediaCodec through FFmpeg's mediacodec (not built-in to waypipe, but would be a separate integration). At worst, purely software H.264 encoding works.

In summary for Android, the path is similar to Linux desktop. You compile waypipe-rs in an Android-friendly way (maybe via Termux or as part of a Wayland APK). Because the kernel is Linux, you can use GPU/DMA mode or --video mode just like on PC. The Android AHardwareBuffer mechanism[8][9] means buffers can be shared across processes efficiently, so Waypipe-rs's Vulkan+DMABUF logic has an analog on Android. The main effort is ensuring the Wayland compositor on Android advertises the linux-dmabuf protocol (or wl_shm fallback otherwise).

## Practical Steps and Caveats

- **Building Waypipe-rs**: On macOS/iOS, first port Wayland core (e.g. via Owl's repos or homebrew), then build and link epoll-shim[4]. Use Cargo/meson to compile waypipe. On Android, cross-compile or use an NDK build for the Linux/Bionic environment.
- **Running mode**: The local side (mac/iOS/Android) runs waypipe in client mode (as the compositor is local). The Linux side runs it in server mode. Use SSH or sockets to connect them as usual.
- **Buffer mode**: If the local compositor does not support linux-dmabuf, use waypipe --no-gpu (SW mode). This is effectively what the SailfishOS package does[6]. On Linux or Android where DMABUF works, you can use GPU mode or --video.
- **Video options**: If you need better performance, try --video=hw (hardware encode on remote) and make sure the receiving side has decode support. On macOS/iOS, hardware encode via VideoToolbox is supported by FFmpeg, but the local compositor just receives the final image pixels.
- **Testing**: Start with simple clients (terminal, glxgears) to verify basic pipeline. Watch for errors about missing protocols (zwp_linux_dmabuf_v1, etc.). Adjust Waypipe options based on failures.

In essence, using waypipe-rs on non-Linux targets is feasible but requires careful handling of the Linux-specific parts. Epoll-shim solves event loop portability[4]. The lack of DMABUF on Darwin means generally using software fallbacks[5]. Android's AHardwareBuffer and Vulkan support cover the zero-copy path[8][9]. The Rust code's use of Vulkan and FFmpeg suggests that with those libraries available (e.g. MoltenVK and VideoToolbox on Apple, Vulkan and NDK on Android), the full feature set (diffs, encoding) can be retained[2][3]. Expect, however, that the DMABUF/video components are low-level (unsafe FFI) and platform-conditional, so testing and conditional compilation may be needed[7].

## Sources

Official Waypipe docs and manpage, porting notes from the Waypipe-Rust rewrite, and platform documentation. For example, the Waypipe manpage notes disabling DMABUF/--no-gpu for compatibility[5], the SailfishOS forum confirms DMABUF is often disabled on mobile[6], and the Android NDK docs describe AHardwareBuffer zero-copy sharing[8][9]. The Rust rewrite blog explains the Vulkan/DMABUF approach in detail[2][3]. Epoll-shim documentation shows how Wayland has been ported using kqueue on macOS[4]. Together, these highlight the major technical adjustments needed.

[1] Waypipe fixes  
https://trofi.github.io/posts/265-waypipe-fixes.html

[2] [3] [7] On rewriting Waypipe in Rust  
https://mstoeckl.com/notes/code/waypipe_to_rust.html

[4] GitHub - jiixyj/epoll-shim: small epoll implementation using kqueue; includes all features needed for libinput/libevdev  
https://github.com/jiixyj/epoll-shim

[5] waypipe(1) — waypipe — Debian unstable — Debian Manpages  
https://manpages.debian.org/unstable/waypipe/waypipe.1.en.html

[6] Fun with remote Wayland: WayPipe - Applications - Sailfish OS Forum  
https://forum.sailfishos.org/t/fun-with-remote-wayland-waypipe/16997

[8] [9] Native Hardware Buffer | Android NDK | Android Developers  
https://developer.android.com/ndk/reference/group/a-hardware-buffer
