#pragma once

#include <wayland-server.h>
#include <stdint.h>

#ifdef __OBJC__
#import <Metal/Metal.h>
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <IOSurface/IOSurfaceRef.h>
#else
#import <IOSurface/IOSurface.h>
#endif
#import <CoreVideo/CoreVideo.h>
#else
// Forward declarations for C code
typedef struct objc_object* id;
// Forward declare IOSurfaceRef - actual definition comes from system headers
// This avoids typedef conflicts when system headers are included
struct __IOSurface;
typedef struct __IOSurface* IOSurfaceRef;
#endif

#ifdef __ANDROID__
#include <vulkan/vulkan.h>
#endif

// DMA-BUF emulation for macOS using IOSurface
// Allows efficient buffer sharing between processes via Metal textures

struct metal_dmabuf_buffer {
#ifdef __ANDROID__
    VkImage image;
    VkDeviceMemory memory;
#else
    IOSurfaceRef iosurface;
    id texture;  // id<MTLTexture> in Objective-C
#endif
    uint32_t width;
    uint32_t height;
    uint32_t format;
    uint32_t stride;
    void *data;
    size_t size;
};

// Create a DMA-BUF compatible buffer using IOSurface
struct metal_dmabuf_buffer *metal_dmabuf_create_buffer(uint32_t width, uint32_t height, uint32_t format);

// Get Metal texture from DMA-BUF buffer (returns id in Objective-C, void* in C)
id metal_dmabuf_get_texture(struct metal_dmabuf_buffer *buffer, id device);

// Release DMA-BUF buffer
void metal_dmabuf_destroy_buffer(struct metal_dmabuf_buffer *buffer);

// Create IOSurface from Wayland buffer data
IOSurfaceRef metal_dmabuf_create_iosurface_from_data(void *data, uint32_t width, uint32_t height, uint32_t stride, uint32_t format);

// Get file descriptor for sharing IOSurface (for waypipe)
int metal_dmabuf_get_fd(struct metal_dmabuf_buffer *buffer);

// Import DMA-BUF buffer from file descriptor (socket with IOSurface ID)
struct metal_dmabuf_buffer *metal_dmabuf_import(int fd, uint32_t width, uint32_t height, uint32_t format, uint32_t stride);

