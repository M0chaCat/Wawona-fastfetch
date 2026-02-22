
After you've completed dmabuf support for macOS waypipe and supporting the Wayland protocol of `zwp_linux_dmabuf_v1` from `linux-dmabuf-unstable-v1`:

We can enhance waypipe by adding VideoToolBox. we can add back software fallback from ffmpeg.


Perfect — now we’re talking **production-grade video transport on macOS for Waypipe**. Let’s map this carefully and step by step.

---

## 1️⃣ Why VideoToolbox is ideal

In your Waypipe scenario:

* Linux clients send **pixel buffers** (either raw from DMA-BUF or via `video` feature)
* On macOS, you want to **decode and display these efficiently**
* **VideoToolbox** can **decode H.264/H.265 streams directly to `CVPixelBuffer`s**, which are GPU-friendly and can feed **Metal textures** → perfect for your Wawona compositor

Advantages:

* Hardware acceleration → **low CPU usage**
* Native **CVPixelBuffer** → **Metal texture mapping** (zero-copy possible)
* Supports **real-time streaming**, ideal for Waypipe

---

## 2️⃣ How it fits into Waypipe macOS

Here’s the **architecture**:

```
[Linux Wayland client]
        |
   (DMA-BUF / video encoded stream)
        |
      Waypipe
        |
[macOS Waypipe receiver]
        |
  VideoToolbox decode
        |
   CVPixelBuffer
        |
     Metal texture
        |
[Wawona compositor render]
```

---

## 3️⃣ Implementation steps

1. **Detect if incoming data is `video`-encoded**

   * If yes, use VideoToolbox for decoding
   * If no, fall back to CPU copy into IOSurface (raw pixel path)

2. **Initialize a VTDecompressionSession**

   * Configure codec type (H.264/HEVC)
   * Set output format to **CVPixelBuffer** with GPU-compatible pixel format (e.g., `kCVPixelFormatType_32BGRA`)

3. **Decode incoming packets**

   * Each Waypipe video packet → `CMSampleBuffer` → `VTDecompressionSessionDecodeFrame`
   * Receive decoded frame → `CVPixelBuffer`

4. **Map `CVPixelBuffer` to Metal texture**

   * `CVMetalTextureCacheCreateTextureFromImage` → Metal texture
   * Render in Wawona compositor

5. **Handle buffer lifecycle**

   * Waypipe signals `wl_buffer.release` → release the CVPixelBuffer / Metal texture
   * Keep a small pool of buffers for performance

---

## 4️⃣ Optional: CPU fallback

* VideoToolbox is hardware-accelerated, but some codecs may not be supported on older macOS versions
* Fallback: decompress using **CPU or FFmpeg software decoder**, then populate IOSurface → Metal

---

## 5️⃣ Integration notes

* **No GBM required on macOS**
* `video` feature of Waypipe maps **directly to VideoToolbox decoding**
* Compression libraries (zstd/lz4) may still be used for **pre-video payload compression**
* `dmabuf` feature is only relevant for **Linux client zero-copy**; macOS always maps buffers into CVPixelBuffer

---

## ✅ Recommendation

* **Remove GBM code** completely from macOS Waypipe
* Implement **VideoToolbox-based decoding path** for `video` feature
* Map decoded frames to **Metal textures via CVMetalTextureCache**
* Keep raw pixel path (from DMA-BUF copies) for debugging or non-video clients

---

If you want, I can write a **minimal macOS Waypipe patch skeleton** that implements **VideoToolbox decoding → CVPixelBuffer → Metal texture**, fully ready for your compositor.

Do you want me to do that next?
## 6️⃣ Quick Start: Remote macOS Apps

Your project is ready to run macOS apps (like `weston-terminal`) on your iOS or Android device.

### 1. Prepare the Mac
Run the preparation script on your Mac to verify everything is set up correctly:
```bash
bash scripts/prepare_mac_remote.sh
```

Ensure:
- **Remote Login (SSH)** is enabled in System Settings.
- **Python 3** is installed.
- **Waypipe** is in your PATH. If you use Nix, you may need to add `~/.nix-profile/bin` to your SSH environment (e.g., via `~/.zshenv`).

### 2. Configure the App (iOS/Android)
1. Open **Wawona**.
2. Go to **Settings > Waypipe**.
3. **SSH Host**: Enter your Mac's IP address.
4. **SSH User**: Your Mac username.
5. **SSH Password**: Your Mac login password.
6. **Remote Command**: `nix run ~/Wawona#weston-terminal`
7. Tap **Start Waypipe**.

### 3. enjoy
`weston-terminal` should appear on your mobile device as a window!
