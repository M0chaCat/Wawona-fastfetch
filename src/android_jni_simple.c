#include <jni.h>
#include <android/native_window_jni.h>
#include <android/log.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <unistd.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "WawonaJNI", __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "WawonaJNI", __VA_ARGS__)

static VkInstance g_instance = VK_NULL_HANDLE;
static VkSurfaceKHR g_surface = VK_NULL_HANDLE;
static VkDevice g_device = VK_NULL_HANDLE;
static VkQueue g_queue = VK_NULL_HANDLE;
static VkSwapchainKHR g_swapchain = VK_NULL_HANDLE;
static uint32_t g_queue_family = 0;
static int g_running = 0;
static pthread_t g_render_thread = 0;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

static VkResult create_instance(void) {
    // Set ICD before creating instance
    setenv("VK_ICD_FILENAMES", "/data/local/tmp/freedreno_icd.json", 1);
    
    const char* exts[] = {
        VK_KHR_SURFACE_EXTENSION_NAME,
        VK_KHR_ANDROID_SURFACE_EXTENSION_NAME
    };
    VkApplicationInfo app = { .sType = VK_STRUCTURE_TYPE_APPLICATION_INFO };
    app.pApplicationName = "Wawona";
    app.applicationVersion = VK_MAKE_VERSION(0,0,1);
    app.pEngineName = "Wawona";
    app.engineVersion = VK_MAKE_VERSION(0,0,1);
    app.apiVersion = VK_API_VERSION_1_0;

    VkInstanceCreateInfo ci = { .sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
    ci.pApplicationInfo = &app;
    ci.enabledExtensionCount = (uint32_t)(sizeof(exts)/sizeof(exts[0]));
    ci.ppEnabledExtensionNames = exts;
    
    VkResult res = vkCreateInstance(&ci, NULL, &g_instance);
    if (res != VK_SUCCESS) {
        LOGE("vkCreateInstance failed: %d", res);
        // Try SwiftShader fallback
        setenv("VK_ICD_FILENAMES", "/system/etc/vulkan/icd.d/swiftshader_icd.json", 1);
        res = vkCreateInstance(&ci, NULL, &g_instance);
    }
    if (res != VK_SUCCESS) LOGE("vkCreateInstance failed: %d", res);
    return res;
}

static VkPhysicalDevice pick_device(void) {
    uint32_t count = 0; 
    VkResult res = vkEnumeratePhysicalDevices(g_instance, &count, NULL);
    if (res != VK_SUCCESS || count == 0) {
        LOGE("vkEnumeratePhysicalDevices failed: %d, count=%u", res, count);
        return VK_NULL_HANDLE;
    }
    VkPhysicalDevice devs[4]; 
    if (count > 4) count = 4; 
    res = vkEnumeratePhysicalDevices(g_instance, &count, devs);
    if (res != VK_SUCCESS) {
        LOGE("vkEnumeratePhysicalDevices failed: %d", res);
        return VK_NULL_HANDLE;
    }
    LOGI("Found %u Vulkan devices", count);
    return devs[0];
}

static int pick_queue_family(VkPhysicalDevice pd) {
    uint32_t count = 0; 
    vkGetPhysicalDeviceQueueFamilyProperties(pd, &count, NULL);
    if (count == 0) return -1;
    
    VkQueueFamilyProperties props[8]; 
    if (count > 8) count = 8; 
    vkGetPhysicalDeviceQueueFamilyProperties(pd, &count, props);
    
    for (uint32_t i = 0; i < count; i++) {
        VkBool32 sup = VK_FALSE; 
        vkGetPhysicalDeviceSurfaceSupportKHR(pd, i, g_surface, &sup);
        if ((props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && sup) {
            LOGI("Found graphics queue family %u", i);
            return (int)i;
        }
    }
    LOGE("No graphics queue family found");
    return -1;
}

static int create_device(VkPhysicalDevice pd) {
    int q = pick_queue_family(pd); 
    if (q < 0) return -1; 
    g_queue_family = (uint32_t)q;
    
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
    qci.queueFamilyIndex = g_queue_family; 
    qci.queueCount = 1; 
    qci.pQueuePriorities = &prio;
    
    const char* dev_exts[] = { VK_KHR_SWAPCHAIN_EXTENSION_NAME };
    VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
    dci.queueCreateInfoCount = 1; 
    dci.pQueueCreateInfos = &qci;
    dci.enabledExtensionCount = (uint32_t)(sizeof(dev_exts)/sizeof(dev_exts[0]));
    dci.ppEnabledExtensionNames = dev_exts;
    
    if (vkCreateDevice(pd, &dci, NULL, &g_device) != VK_SUCCESS) {
        LOGE("vkCreateDevice failed");
        return -1;
    }
    vkGetDeviceQueue(g_device, g_queue_family, 0, &g_queue);
    LOGI("Device created successfully");
    return 0;
}

static int create_swapchain(VkPhysicalDevice pd) {
    VkSurfaceCapabilitiesKHR caps; 
    VkResult res = vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pd, g_surface, &caps);
    if (res != VK_SUCCESS) {
        LOGE("vkGetPhysicalDeviceSurfaceCapabilitiesKHR failed: %d", res);
        return -1;
    }
    
    VkExtent2D ext = caps.currentExtent; 
    if (ext.width == 0 || ext.height == 0) ext = (VkExtent2D){ 640, 480 };
    LOGI("Swapchain extent: %ux%u", ext.width, ext.height);
    
    VkSwapchainCreateInfoKHR sci = { .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR };
    sci.surface = g_surface; 
    sci.minImageCount = caps.minImageCount > 2 ? caps.minImageCount : 2;
    sci.imageFormat = VK_FORMAT_R8G8B8A8_UNORM; 
    sci.imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
    sci.imageExtent = ext; 
    sci.imageArrayLayers = 1; 
    sci.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    sci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE; 
    sci.preTransform = caps.currentTransform;
    sci.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR; 
    sci.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    sci.clipped = VK_TRUE;
    
    if (vkCreateSwapchainKHR(g_device, &sci, NULL, &g_swapchain) != VK_SUCCESS) {
        LOGE("vkCreateSwapchainKHR failed");
        return -1;
    }
    LOGI("Swapchain created successfully");
    return 0;
}

static void* render_thread(void* arg) {
    (void)arg;
    LOGI("Render thread started");
    
    // Simple test - just clear the screen once
    uint32_t imageCount = 0;
    VkResult res = vkGetSwapchainImagesKHR(g_device, g_swapchain, &imageCount, NULL);
    if (res != VK_SUCCESS || imageCount == 0) {
        LOGE("Failed to get swapchain images: %d, count=%u", res, imageCount);
        return NULL;
    }
    
    VkImage* images = malloc(imageCount * sizeof(VkImage));
    res = vkGetSwapchainImagesKHR(g_device, g_swapchain, &imageCount, images);
    if (res != VK_SUCCESS) {
        LOGE("Failed to get swapchain images: %d", res);
        free(images);
        return NULL;
    }
    
    LOGI("Got %u swapchain images", imageCount);
    
    // Create command pool
    VkCommandPool cmdPool;
    VkCommandPoolCreateInfo cpci = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
    cpci.queueFamilyIndex = g_queue_family; 
    cpci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    res = vkCreateCommandPool(g_device, &cpci, NULL, &cmdPool);
    if (res != VK_SUCCESS) {
        LOGE("Failed to create command pool: %d", res);
        free(images);
        return NULL;
    }
    
    // Create command buffer
    VkCommandBuffer cmdBuf;
    VkCommandBufferAllocateInfo cbai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
    cbai.commandPool = cmdPool; 
    cbai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; 
    cbai.commandBufferCount = 1;
    res = vkAllocateCommandBuffers(g_device, &cbai, &cmdBuf);
    if (res != VK_SUCCESS) {
        LOGE("Failed to allocate command buffer: %d", res);
        vkDestroyCommandPool(g_device, cmdPool, NULL);
        free(images);
        return NULL;
    }
    
    // Render a few frames
    int frame_count = 0;
    while (g_running && frame_count < 10) {
        uint32_t imageIndex;
        res = vkAcquireNextImageKHR(g_device, g_swapchain, UINT64_MAX, VK_NULL_HANDLE, VK_NULL_HANDLE, &imageIndex);
        if (res != VK_SUCCESS && res != VK_SUBOPTIMAL_KHR) {
            LOGE("vkAcquireNextImageKHR failed: %d", res);
            break;
        }
        
        // Record command buffer
        VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
        bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        res = vkBeginCommandBuffer(cmdBuf, &bi);
        if (res != VK_SUCCESS) {
            LOGE("vkBeginCommandBuffer failed: %d", res);
            break;
        }
        
        // Transition image to transfer dst optimal
        VkImageMemoryBarrier barrier = {0};
        barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
        barrier.oldLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
        barrier.image = images[imageIndex];
        barrier.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        barrier.subresourceRange.baseMipLevel = 0;
        barrier.subresourceRange.levelCount = 1;
        barrier.subresourceRange.baseArrayLayer = 0;
        barrier.subresourceRange.layerCount = 1;
        barrier.srcAccessMask = 0;
        barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        
        vkCmdPipelineBarrier(cmdBuf, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
                             0, NULL, 0, NULL, 1, &barrier);
        
        // Clear the image
        VkClearColorValue clearColor = { .float32 = { 0.1f, 0.2f, 0.3f, 1.0f } };
        VkImageSubresourceRange range = {0};
        range.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
        range.baseMipLevel = 0;
        range.levelCount = 1;
        range.baseArrayLayer = 0;
        range.layerCount = 1;
        
        vkCmdClearColorImage(cmdBuf, images[imageIndex], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &clearColor, 1, &range);
        
        // Transition to present src
        barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
        barrier.newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
        barrier.dstAccessMask = 0;
        
        vkCmdPipelineBarrier(cmdBuf, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0,
                             0, NULL, 0, NULL, 1, &barrier);
        
        res = vkEndCommandBuffer(cmdBuf);
        if (res != VK_SUCCESS) {
            LOGE("vkEndCommandBuffer failed: %d", res);
            break;
        }
        
        // Submit command buffer
        VkSubmitInfo submit = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO };
        submit.commandBufferCount = 1;
        submit.pCommandBuffers = &cmdBuf;
        
        VkFence fence;
        VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
        vkCreateFence(g_device, &fci, NULL, &fence);
        
        res = vkQueueSubmit(g_queue, 1, &submit, fence);
        if (res != VK_SUCCESS) {
            LOGE("vkQueueSubmit failed: %d", res);
            vkDestroyFence(g_device, fence, NULL);
            break;
        }
        
        vkWaitForFences(g_device, 1, &fence, VK_TRUE, UINT64_MAX);
        vkDestroyFence(g_device, fence, NULL);
        
        // Present
        VkPresentInfoKHR present = { .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR };
        present.swapchainCount = 1;
        present.pSwapchains = &g_swapchain;
        present.pImageIndices = &imageIndex;
        
        res = vkQueuePresentKHR(g_queue, &present);
        if (res != VK_SUCCESS && res != VK_SUBOPTIMAL_KHR) {
            LOGE("vkQueuePresentKHR failed: %d", res);
            break;
        }
        
        frame_count++;
        LOGI("Rendered frame %d", frame_count);
        usleep(166666); // ~60 FPS
    }
    
    vkDeviceWaitIdle(g_device);
    vkFreeCommandBuffers(g_device, cmdPool, 1, &cmdBuf);
    vkDestroyCommandPool(g_device, cmdPool, NULL);
    free(images);
    
    LOGI("Render thread stopped, rendered %d frames", frame_count);
    return NULL;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_MainActivity_nativeInit(JNIEnv* env, jobject thiz) {
    (void)env; (void)thiz;
    pthread_mutex_lock(&g_lock);
    if (g_instance != VK_NULL_HANDLE) {
        pthread_mutex_unlock(&g_lock);
        return;
    }
    LOGI("Starting Wawona Compositor (Android)");
    VkResult r = create_instance();
    if (r != VK_SUCCESS) {
        pthread_mutex_unlock(&g_lock);
        return;
    }
    uint32_t count = 0; 
    VkResult res = vkEnumeratePhysicalDevices(g_instance, &count, NULL);
    LOGI("vkEnumeratePhysicalDevices count=%u, res=%d", count, res);
    pthread_mutex_unlock(&g_lock);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_MainActivity_nativeSetSurface(JNIEnv* env, jobject thiz, jobject surface) {
    (void)thiz;
    pthread_mutex_lock(&g_lock);
    
    ANativeWindow* win = ANativeWindow_fromSurface(env, surface);
    if (!win) { 
        LOGE("ANativeWindow_fromSurface returned NULL"); 
        pthread_mutex_unlock(&g_lock);
        return; 
    }
    LOGI("Received ANativeWindow %p", (void*)win);
    
    if (g_instance == VK_NULL_HANDLE) {
        if (create_instance() != VK_SUCCESS) {
            ANativeWindow_release(win);
            pthread_mutex_unlock(&g_lock);
            return;
        }
    }
    
    VkAndroidSurfaceCreateInfoKHR sci = { .sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR };
    sci.window = win;
    VkResult res = vkCreateAndroidSurfaceKHR(g_instance, &sci, NULL, &g_surface);
    if (res != VK_SUCCESS) { 
        LOGE("vkCreateAndroidSurfaceKHR failed: %d", res); 
        ANativeWindow_release(win);
        pthread_mutex_unlock(&g_lock);
        return; 
    }
    LOGI("Android VkSurfaceKHR created: %p", (void*)g_surface);
    
    VkPhysicalDevice pd = pick_device();
    if (pd == VK_NULL_HANDLE) {
        LOGE("No Vulkan devices found");
        ANativeWindow_release(win);
        pthread_mutex_unlock(&g_lock);
        return;
    }
    
    if (create_device(pd) != 0) {
        LOGE("Failed to create device");
        ANativeWindow_release(win);
        pthread_mutex_unlock(&g_lock);
        return;
    }
    
    if (create_swapchain(pd) != 0) {
        LOGE("Failed to create swapchain");
        ANativeWindow_release(win);
        pthread_mutex_unlock(&g_lock);
        return;
    }
    
    // Start render thread with delay to ensure surface is ready
    g_running = 1; 
    usleep(500000); // 500ms delay to let surface stabilize
    if (pthread_create(&g_render_thread, NULL, render_thread, NULL) != 0) {
        LOGE("Failed to create render thread");
        g_running = 0;
        ANativeWindow_release(win);
        pthread_mutex_unlock(&g_lock);
        return;
    }
    
    LOGI("Wawona Compositor initialized successfully");
    pthread_mutex_unlock(&g_lock);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_MainActivity_nativeDestroySurface(JNIEnv* env, jobject thiz) {
    (void)env; (void)thiz;
    pthread_mutex_lock(&g_lock);
    
    LOGI("Destroying surface");
    g_running = 0;
    
    // Wait for render thread to finish
    if (g_render_thread) {
        pthread_join(g_render_thread, NULL);
        g_render_thread = 0;
    }
    
    // Clean up Vulkan resources
    if (g_device != VK_NULL_HANDLE) {
        vkDeviceWaitIdle(g_device);
    }
    
    if (g_swapchain && g_device) {
        vkDestroySwapchainKHR(g_device, g_swapchain, NULL);
        g_swapchain = VK_NULL_HANDLE;
    }
    
    if (g_surface && g_instance) {
        vkDestroySurfaceKHR(g_instance, g_surface, NULL);
        g_surface = VK_NULL_HANDLE;
    }
    
    if (g_device) {
        vkDestroyDevice(g_device, NULL);
        g_device = VK_NULL_HANDLE;
    }
    
    if (g_instance) {
        vkDestroyInstance(g_instance, NULL);
        g_instance = VK_NULL_HANDLE;
    }
    
    LOGI("Surface destroyed");
    pthread_mutex_unlock(&g_lock);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_MainActivity_nativeApplySettings(JNIEnv* env, jobject thiz,
                                                                jboolean vsync, jboolean debugOverlay,
                                                                jboolean gpuAcceleration, jint fpsLimit,
                                                                jstring renderer) {
    (void)thiz;
    pthread_mutex_lock(&g_lock);
    
    LOGI("Applying settings:");
    LOGI("  VSync: %s", vsync ? "enabled" : "disabled");
    LOGI("  Debug Overlay: %s", debugOverlay ? "enabled" : "disabled");
    LOGI("  GPU Acceleration: %s", gpuAcceleration ? "enabled" : "disabled");
    LOGI("  FPS Limit: %d", fpsLimit);
    
    const char* rendererStr = (*env)->GetStringUTFChars(env, renderer, NULL);
    LOGI("  Renderer: %s", rendererStr);
    
    // Apply settings to native compositor
    if (vsync) {
        setenv("WAWONA_VSYNC", "1", 1);
    } else {
        setenv("WAWONA_VSYNC", "0", 1);
    }
    
    if (debugOverlay) {
        setenv("WAWONA_DEBUG_OVERLAY", "1", 1);
    } else {
        setenv("WAWONA_DEBUG_OVERLAY", "0", 1);
    }
    
    if (gpuAcceleration) {
        setenv("WAWONA_GPU_ACCELERATION", "1", 1);
    } else {
        setenv("WAWONA_GPU_ACCELERATION", "0", 1);
    }
    
    char fpsStr[16];
    snprintf(fpsStr, sizeof(fpsStr), "%d", fpsLimit);
    setenv("WAWONA_FPS_LIMIT", fpsStr, 1);
    
    if (rendererStr) {
        if (strcmp(rendererStr, "vulkan") == 0) {
            setenv("WAWONA_RENDERER", "vulkan", 1);
        } else if (strcmp(rendererStr, "opengl") == 0) {
            setenv("WAWONA_RENDERER", "opengl", 1);
        }
        (*env)->ReleaseStringUTFChars(env, renderer, rendererStr);
    }
    
    LOGI("Settings applied successfully");
    pthread_mutex_unlock(&g_lock);
}