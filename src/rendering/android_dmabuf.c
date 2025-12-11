#include "metal_dmabuf.h"
#include <stdlib.h>
#include <stdio.h>
#include <unistd.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>
#include <android/log.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "WawonaDMABUF", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "WawonaDMABUF", __VA_ARGS__)

// Global variables from android_jni.c
extern VkDevice g_device;
extern VkPhysicalDevice g_physicalDevice;
extern VkInstance g_instance;

// Helper to find memory type
static uint32_t find_memory_type(uint32_t typeFilter, VkMemoryPropertyFlags properties) {
    VkPhysicalDeviceMemoryProperties memProperties;
    vkGetPhysicalDeviceMemoryProperties(g_physicalDevice, &memProperties);

    for (uint32_t i = 0; i < memProperties.memoryTypeCount; i++) {
        if ((typeFilter & (1 << i)) && 
            (memProperties.memoryTypes[i].propertyFlags & properties) == properties) {
            return i;
        }
    }
    return -1;
}

// Map Wayland/DRM format to Vulkan format
static VkFormat map_format(uint32_t format) {
    // Basic mapping, extend as needed
    // format is FourCC
    switch (format) {
        case 0x34325241: // ARGB8888 (Little Endian) -> BGRA
        case 0x34325258: // XRGB8888 -> BGRA
            return VK_FORMAT_B8G8R8A8_UNORM;
        case 0x34324241: // ABGR8888 -> RGBA
        case 0x34324258: // XBGR8888 -> RGBA
            return VK_FORMAT_R8G8B8A8_UNORM;
        default:
            return VK_FORMAT_R8G8B8A8_UNORM; // Fallback
    }
}

struct metal_dmabuf_buffer *metal_dmabuf_create_buffer(uint32_t width, uint32_t height, uint32_t format) {
    // Not implemented for Android yet (used for local buffers)
    return NULL;
}

void metal_dmabuf_destroy_buffer(struct metal_dmabuf_buffer *buffer) {
    if (buffer) {
        if (g_device != VK_NULL_HANDLE) {
            if (buffer->image != VK_NULL_HANDLE) {
                vkDestroyImage(g_device, buffer->image, NULL);
            }
            if (buffer->memory != VK_NULL_HANDLE) {
                vkFreeMemory(g_device, buffer->memory, NULL);
            }
        }
        free(buffer);
    }
}

// Import DMA-BUF from file descriptor
struct metal_dmabuf_buffer *metal_dmabuf_import(int fd, uint32_t width, uint32_t height, uint32_t format, uint32_t stride) {
    if (g_device == VK_NULL_HANDLE) {
        LOGE("Cannot import DMABUF: Vulkan device not initialized");
        return NULL;
    }

    struct metal_dmabuf_buffer *buffer = calloc(1, sizeof(struct metal_dmabuf_buffer));
    if (!buffer) return NULL;

    buffer->width = width;
    buffer->height = height;
    buffer->format = format;
    buffer->stride = stride;

    // Create VkImage
    VkExternalMemoryImageCreateInfo ext_info = {
        .sType = VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_IMAGE_CREATE_INFO,
        .handleTypes = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT,
    };

    VkImageCreateInfo image_info = {
        .sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO,
        .pNext = &ext_info,
        .imageType = VK_IMAGE_TYPE_2D,
        .format = map_format(format),
        .extent = { width, height, 1 },
        .mipLevels = 1,
        .arrayLayers = 1,
        .samples = VK_SAMPLE_COUNT_1_BIT,
        .tiling = VK_IMAGE_TILING_OPTIMAL, // SwiftShader/Drivers usually prefer optimal for imported DMABUFs
        .usage = VK_IMAGE_USAGE_SAMPLED_BIT, // We want to sample from it
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE,
        .initialLayout = VK_IMAGE_LAYOUT_UNDEFINED,
    };

    if (vkCreateImage(g_device, &image_info, NULL, &buffer->image) != VK_SUCCESS) {
        LOGE("Failed to create Vulkan image for DMABUF import");
        free(buffer);
        return NULL;
    }

    // Get memory requirements
    VkMemoryRequirements memRequirements;
    vkGetImageMemoryRequirements(g_device, buffer->image, &memRequirements);

    // Import memory
    VkImportMemoryFdInfoKHR import_info = {
        .sType = VK_STRUCTURE_TYPE_IMPORT_MEMORY_FD_INFO_KHR,
        .handleType = VK_EXTERNAL_MEMORY_HANDLE_TYPE_DMA_BUF_BIT_EXT,
        .fd = fd,
    };

    VkMemoryAllocateInfo alloc_info = {
        .sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .pNext = &import_info,
        .allocationSize = memRequirements.size,
        .memoryTypeIndex = find_memory_type(memRequirements.memoryTypeBits, 0), // No specific properties needed for import?
    };

    // Try to find a memory type that is device local if possible, but for import we just need a valid type index
    // that supports the image.
    // Actually, usually we should check if the memory type supports the handle type, 
    // but vkGetMemoryFdPropertiesKHR is complex.
    // For now, simple search.

    if (vkAllocateMemory(g_device, &alloc_info, NULL, &buffer->memory) != VK_SUCCESS) {
        LOGE("Failed to allocate memory for DMABUF import");
        vkDestroyImage(g_device, buffer->image, NULL);
        free(buffer);
        return NULL;
    }

    if (vkBindImageMemory(g_device, buffer->image, buffer->memory, 0) != VK_SUCCESS) {
        LOGE("Failed to bind memory for DMABUF import");
        vkFreeMemory(g_device, buffer->memory, NULL);
        vkDestroyImage(g_device, buffer->image, NULL);
        free(buffer);
        return NULL;
    }

    LOGI("Successfully imported DMABUF fd=%d as Vulkan Image", fd);
    return buffer;
}

int metal_dmabuf_get_fd(struct metal_dmabuf_buffer *buffer) {
    return -1;
}

id metal_dmabuf_get_texture(struct metal_dmabuf_buffer *buffer, id device) {
    return NULL;
}

IOSurfaceRef metal_dmabuf_create_iosurface_from_data(void *data, uint32_t width, uint32_t height, uint32_t stride, uint32_t format) {
    return NULL;
}
