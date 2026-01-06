#pragma once

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif
#import <Metal/Metal.h>

#ifdef HAVE_VULKAN
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
#define VK_USE_PLATFORM_IOS_MVK
#else
#define VK_USE_PLATFORM_MACOS_MVK
#endif
#define VK_USE_PLATFORM_METAL_EXT
#include <vulkan/vulkan.h>
#endif

// Vulkan renderer using KosmicKrisp for EGL/OpenGL ES rendering
// Converts Vulkan output to Metal textures for display in Metal view

@class VulkanSurface;

@interface VulkanRenderer : NSObject

@property (nonatomic, strong) id<MTLDevice> metalDevice; // Metal device for texture conversion
@property (nonatomic, strong) id<MTLCommandQueue> metalCommandQueue;
@property (nonatomic, assign) void *vkInstance;
@property (nonatomic, assign) void *vkPhysicalDevice;
@property (nonatomic, assign) void *vkDevice;
@property (nonatomic, assign) void *vkQueue;
@property (nonatomic, assign) uint32_t vkQueueFamilyIndex;
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, VulkanSurface *> *vulkanSurfaces;

- (instancetype)initWithMetalDevice:(id<MTLDevice>)metalDevice;
- (BOOL)initializeVulkan; // Initialize Vulkan using KosmicKrisp ICD
- (void)cleanupVulkan;
- (id<MTLTexture>)renderSurface:(struct wl_surface_impl *)surface; // Render Wayland surface using Vulkan ICD
- (void)removeSurface:(struct wl_surface_impl *)surface;

@end

