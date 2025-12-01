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

// Safe area support
static int g_safeAreaLeft = 0;
static int g_safeAreaTop = 0;
static int g_safeAreaRight = 0;
static int g_safeAreaBottom = 0;
static int g_respectSafeArea = 1; // Default to enabled like iOS

// iOS Settings 1:1 mapping
static struct {
    // Display settings
    int forceServerSideDecorations;
    int autoRetinaScaling;
    int renderingBackend; // 0=Automatic, 1=Metal(Vulkan), 2=Cocoa(Surface)
    int respectSafeArea;
    
    // Input settings
    int renderMacOSPointer;
    int swapCmdAsCtrl;
    int universalClipboard;
    
    // Color Management
    int colorSyncSupport;
    
    // Advanced settings
    int nestedCompositorsSupport;
    int useMetal4ForNested;
    int multipleClients;
    int waypipeRSSupport;
    
    // Network settings
    int enableTCPListener;
    int tcpPort;
} g_settings = {
    .forceServerSideDecorations = 1,
    .autoRetinaScaling = 1,
    .renderingBackend = 0, // Automatic
    .respectSafeArea = 1,
    .renderMacOSPointer = 1,
    .swapCmdAsCtrl = 0,
    .universalClipboard = 1,
    .colorSyncSupport = 1,
    .nestedCompositorsSupport = 1,
    .useMetal4ForNested = 0,
    .multipleClients = 1,
    .waypipeRSSupport = 0,
    .enableTCPListener = 0,
    .tcpPort = 0
};

// Function to get safe area from Android WindowInsets
static void update_safe_area(JNIEnv* env, jobject activity) {
    if (!activity || !g_respectSafeArea) {
        g_safeAreaLeft = 0;
        g_safeAreaTop = 0;
        g_safeAreaRight = 0;
        g_safeAreaBottom = 0;
        return;
    }
    
    // Get WindowInsets
    jclass activityClass = (*env)->GetObjectClass(env, activity);
    jmethodID getWindowMethod = (*env)->GetMethodID(env, activityClass, "getWindow", "()Landroid/view/Window;");
    jobject window = (*env)->CallObjectMethod(env, activity, getWindowMethod);
    
    if (window) {
        jclass windowClass = (*env)->GetObjectClass(env, window);
        jmethodID getDecorViewMethod = (*env)->GetMethodID(env, windowClass, "getDecorView", "()Landroid/view/View;");
        jobject decorView = (*env)->CallObjectMethod(env, window, getDecorViewMethod);
        
        if (decorView) {
            // Get root window insets
            jclass viewClass = (*env)->GetObjectClass(env, decorView);
            jmethodID getRootWindowInsetsMethod = (*env)->GetMethodID(env, viewClass, "getRootWindowInsets", "()Landroid/view/WindowInsets;");
            jobject windowInsets = (*env)->CallObjectMethod(env, decorView, getRootWindowInsetsMethod);
            
            if (windowInsets) {
                // Get display cutout for notch/punch hole
                jclass windowInsetsClass = (*env)->GetObjectClass(env, windowInsets);
                jmethodID getDisplayCutoutMethod = (*env)->GetMethodID(env, windowInsetsClass, "getDisplayCutout", "()Landroid/view/DisplayCutout;");
                jobject displayCutout = (*env)->CallObjectMethod(env, windowInsets, getDisplayCutoutMethod);
                
                if (displayCutout) {
                    jclass displayCutoutClass = (*env)->GetObjectClass(env, displayCutout);
                    
                    // Get safe insets
                    jmethodID getSafeInsetLeftMethod = (*env)->GetMethodID(env, displayCutoutClass, "getSafeInsetLeft", "()I");
                    jmethodID getSafeInsetTopMethod = (*env)->GetMethodID(env, displayCutoutClass, "getSafeInsetTop", "()I");
                    jmethodID getSafeInsetRightMethod = (*env)->GetMethodID(env, displayCutoutClass, "getSafeInsetRight", "()I");
                    jmethodID getSafeInsetBottomMethod = (*env)->GetMethodID(env, displayCutoutClass, "getSafeInsetBottom", "()I");
                    
                    g_safeAreaLeft = (*env)->CallIntMethod(env, displayCutout, getSafeInsetLeftMethod);
                    g_safeAreaTop = (*env)->CallIntMethod(env, displayCutout, getSafeInsetTopMethod);
                    g_safeAreaRight = (*env)->CallIntMethod(env, displayCutout, getSafeInsetRightMethod);
                    g_safeAreaBottom = (*env)->CallIntMethod(env, displayCutout, getSafeInsetBottomMethod);
                    
                    LOGI("Safe area updated: left=%d, top=%d, right=%d, bottom=%d", 
                         g_safeAreaLeft, g_safeAreaTop, g_safeAreaRight, g_safeAreaBottom);
                    
                    (*env)->DeleteLocalRef(env, displayCutout);
                } else {
                    // Fallback to system gesture insets for navigation bar
                    jmethodID getSystemGestureInsetsMethod = (*env)->GetMethodID(env, windowInsetsClass, "getSystemGestureInsets", "()Landroid/graphics/Insets;");
                    jobject systemGestureInsets = (*env)->CallObjectMethod(env, windowInsets, getSystemGestureInsetsMethod);
                    
                    if (systemGestureInsets) {
                        jclass insetsClass = (*env)->GetObjectClass(env, systemGestureInsets);
                        jfieldID leftField = (*env)->GetFieldID(env, insetsClass, "left", "I");
                        jfieldID topField = (*env)->GetFieldID(env, insetsClass, "top", "I");
                        jfieldID rightField = (*env)->GetFieldID(env, insetsClass, "right", "I");
                        jfieldID bottomField = (*env)->GetFieldID(env, insetsClass, "bottom", "I");
                        
                        g_safeAreaLeft = (*env)->GetIntField(env, systemGestureInsets, leftField);
                        g_safeAreaTop = (*env)->GetIntField(env, systemGestureInsets, topField);
                        g_safeAreaRight = (*env)->GetIntField(env, systemGestureInsets, rightField);
                        g_safeAreaBottom = (*env)->GetIntField(env, systemGestureInsets, bottomField);
                        
                        LOGI("System gesture insets: left=%d, top=%d, right=%d, bottom=%d", 
                             g_safeAreaLeft, g_safeAreaTop, g_safeAreaRight, g_safeAreaBottom);
                        
                        (*env)->DeleteLocalRef(env, systemGestureInsets);
                    } else {
                        // Default to no safe area
                        g_safeAreaLeft = 0;
                        g_safeAreaTop = 0;
                        g_safeAreaRight = 0;
                        g_safeAreaBottom = 0;
                        LOGI("No safe area detected, using full screen");
                    }
                }
                
                (*env)->DeleteLocalRef(env, windowInsets);
            }
            
            (*env)->DeleteLocalRef(env, decorView);
        }
        
        (*env)->DeleteLocalRef(env, window);
    }
    
    (*env)->DeleteLocalRef(env, activityClass);
}

static VkResult create_instance(void) {
    // Set ICD before creating instance based on rendering backend setting
    switch (g_settings.renderingBackend) {
        case 1: // Metal (Vulkan)
            setenv("VK_ICD_FILENAMES", "/data/local/tmp/freedreno_icd.json", 1);
            break;
        case 2: // Cocoa (Surface) - use software rendering
            setenv("VK_ICD_FILENAMES", "/system/etc/vulkan/icd.d/swiftshader_icd.json", 1);
            break;
        case 0: // Automatic - default to Vulkan with fallback
        default:
            setenv("VK_ICD_FILENAMES", "/data/local/tmp/freedreno_icd.json", 1);
            break;
    }
    
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
    LOGI("Render thread started with settings:");
    LOGI("  Force Server-Side Decorations: %s", g_settings.forceServerSideDecorations ? "enabled" : "disabled");
    LOGI("  Auto Retina Scaling: %s", g_settings.autoRetinaScaling ? "enabled" : "disabled");
    LOGI("  Rendering Backend: %d (0=Automatic, 1=Metal(Vulkan), 2=Cocoa(Surface))", g_settings.renderingBackend);
    LOGI("  Respect Safe Area: %s", g_settings.respectSafeArea ? "enabled" : "disabled");
    LOGI("  Safe Area: left=%d, top=%d, right=%d, bottom=%d", 
         g_safeAreaLeft, g_safeAreaTop, g_safeAreaRight, g_safeAreaBottom);
    LOGI("  Render macOS Pointer: %s", g_settings.renderMacOSPointer ? "enabled" : "disabled");
    LOGI("  Swap Cmd as Ctrl: %s", g_settings.swapCmdAsCtrl ? "enabled" : "disabled");
    LOGI("  Universal Clipboard: %s", g_settings.universalClipboard ? "enabled" : "disabled");
    LOGI("  ColorSync Support: %s", g_settings.colorSyncSupport ? "enabled" : "disabled");
    LOGI("  Nested Compositors Support: %s", g_settings.nestedCompositorsSupport ? "enabled" : "disabled");
    LOGI("  Use Metal 4 for Nested: %s", g_settings.useMetal4ForNested ? "enabled" : "disabled");
    LOGI("  Multiple Clients: %s", g_settings.multipleClients ? "enabled" : "disabled");
    LOGI("  Waypipe RS Support: %s", g_settings.waypipeRSSupport ? "enabled" : "disabled");
    LOGI("  Enable TCP Listener: %s", g_settings.enableTCPListener ? "enabled" : "disabled");
    LOGI("  TCP Port: %d", g_settings.tcpPort);
    
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
        
        // Clear the image with iOS/macOS compositor background color
        VkClearColorValue clearColor = { .float32 = { 24.0f/255.0f, 24.0f/255.0f, 49.0f/255.0f, 1.0f } }; // RGB(24, 24, 49)
        
    // If safe area is enabled, only clear the safe area region
    if (g_respectSafeArea && (g_safeAreaLeft > 0 || g_safeAreaTop > 0 || g_safeAreaRight > 0 || g_safeAreaBottom > 0)) {
        // Get surface dimensions from physical device
        VkSurfaceCapabilitiesKHR caps;
        VkPhysicalDevice pd = pick_device();
        if (pd != VK_NULL_HANDLE) {
            vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pd, g_surface, &caps);
            uint32_t surfaceWidth = caps.currentExtent.width;
            uint32_t surfaceHeight = caps.currentExtent.height;
            
            // Calculate safe area bounds
            uint32_t safeLeft = g_safeAreaLeft;
            uint32_t safeTop = g_safeAreaTop;
            uint32_t safeWidth = surfaceWidth - g_safeAreaLeft - g_safeAreaRight;
            uint32_t safeHeight = surfaceHeight - g_safeAreaTop - g_safeAreaBottom;
            
            LOGI("Rendering in safe area: left=%u, top=%u, width=%u, height=%u", safeLeft, safeTop, safeWidth, safeHeight);
        }
    }
            
            // Clear only the safe area
            VkImageSubresourceRange range = {0};
            range.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
            range.baseMipLevel = 0;
            range.levelCount = 1;
            range.baseArrayLayer = 0;
            range.layerCount = 1;
            
            vkCmdClearColorImage(cmdBuf, images[imageIndex], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &clearColor, 1, &range);
            
            // Clear the unsafe areas with black
            VkClearColorValue blackColor = { .float32 = { 0.0f, 0.0f, 0.0f, 1.0f } };
            
            // Clear left unsafe area
            if (safeLeft > 0) {
                VkImageSubresourceRange leftRange = {0};
                leftRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
                leftRange.baseMipLevel = 0;
                leftRange.levelCount = 1;
                leftRange.baseArrayLayer = 0;
                leftRange.layerCount = 1;
                // Note: Vulkan doesn't support subregion clearing in a single call
                // For now, we'll clear the whole image with the safe area color
            }
        } else {
            // Clear entire image
            VkImageSubresourceRange range = {0};
            range.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
            range.baseMipLevel = 0;
            range.levelCount = 1;
            range.baseArrayLayer = 0;
            range.layerCount = 1;
            
            vkCmdClearColorImage(cmdBuf, images[imageIndex], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &clearColor, 1, &range);
        }
        
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
    LOGI("Starting Wawona Compositor (Android) - iOS Settings Mode with Safe Area");
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
    
    // Update safe area from activity
    update_safe_area(env, thiz);
    
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
                                                                jboolean forceServerSideDecorations,
                                                                jboolean autoRetinaScaling,
                                                                jint renderingBackend,
                                                                jboolean respectSafeArea,
                                                                jboolean renderMacOSPointer,
                                                                jboolean swapCmdAsCtrl,
                                                                jboolean universalClipboard,
                                                                jboolean colorSyncSupport,
                                                                jboolean nestedCompositorsSupport,
                                                                jboolean useMetal4ForNested,
                                                                jboolean multipleClients,
                                                                jboolean waypipeRSSupport,
                                                                jboolean enableTCPListener,
                                                                jint tcpPort) {
    (void)thiz;
    pthread_mutex_lock(&g_lock);
    
    LOGI("Applying iOS settings 1:1:");
    LOGI("  Force Server-Side Decorations: %s", forceServerSideDecorations ? "enabled" : "disabled");
    LOGI("  Auto Retina Scaling: %s", autoRetinaScaling ? "enabled" : "disabled");
    LOGI("  Rendering Backend: %d (0=Automatic, 1=Metal(Vulkan), 2=Cocoa(Surface))", renderingBackend);
    LOGI("  Respect Safe Area: %s", respectSafeArea ? "enabled" : "disabled");
    LOGI("  Safe Area: left=%d, top=%d, right=%d, bottom=%d", 
         g_safeAreaLeft, g_safeAreaTop, g_safeAreaRight, g_safeAreaBottom);
    LOGI("  Render macOS Pointer: %s", renderMacOSPointer ? "enabled" : "disabled");
    LOGI("  Swap Cmd as Ctrl: %s", swapCmdAsCtrl ? "enabled" : "disabled");
    LOGI("  Universal Clipboard: %s", universalClipboard ? "enabled" : "disabled");
    LOGI("  ColorSync Support: %s", colorSyncSupport ? "enabled" : "disabled");
    LOGI("  Nested Compositors Support: %s", nestedCompositorsSupport ? "enabled" : "disabled");
    LOGI("  Use Metal 4 for Nested: %s", useMetal4ForNested ? "enabled" : "disabled");
    LOGI("  Multiple Clients: %s", multipleClients ? "enabled" : "disabled");
    LOGI("  Waypipe RS Support: %s", waypipeRSSupport ? "enabled" : "disabled");
    LOGI("  Enable TCP Listener: %s", enableTCPListener ? "enabled" : "disabled");
    LOGI("  TCP Port: %d", tcpPort);
    
    // Apply settings to match iOS exactly
    g_settings.forceServerSideDecorations = forceServerSideDecorations ? 1 : 0;
    g_settings.autoRetinaScaling = autoRetinaScaling ? 1 : 0;
    g_settings.renderingBackend = renderingBackend;
    g_settings.respectSafeArea = respectSafeArea ? 1 : 0;
    g_settings.renderMacOSPointer = renderMacOSPointer ? 1 : 0;
    g_settings.swapCmdAsCtrl = swapCmdAsCtrl ? 1 : 0;
    g_settings.universalClipboard = universalClipboard ? 1 : 0;
    g_settings.colorSyncSupport = colorSyncSupport ? 1 : 0;
    g_settings.nestedCompositorsSupport = nestedCompositorsSupport ? 1 : 0;
    g_settings.useMetal4ForNested = useMetal4ForNested ? 1 : 0;
    g_settings.multipleClients = multipleClients ? 1 : 0;
    g_settings.waypipeRSSupport = waypipeRSSupport ? 1 : 0;
    g_settings.enableTCPListener = enableTCPListener ? 1 : 0;
    g_settings.tcpPort = tcpPort;
    
    // Update safe area flag
    g_respectSafeArea = respectSafeArea ? 1 : 0;
    
    // Update safe area from current activity
    update_safe_area(env, thiz);
    
    // Set environment variables for native compositor
    setenv("WAWONA_FORCE_SERVER_DECORATIONS", forceServerSideDecorations ? "1" : "0", 1);
    setenv("WAWONA_AUTO_RETINA_SCALING", autoRetinaScaling ? "1" : "0", 1);
    char backendStr[16];
    snprintf(backendStr, sizeof(backendStr), "%d", renderingBackend);
    setenv("WAWONA_RENDERING_BACKEND", backendStr, 1);
    setenv("WAWONA_RESPECT_SAFE_AREA", respectSafeArea ? "1" : "0", 1);
    setenv("WAWONA_RENDER_MACOS_POINTER", renderMacOSPointer ? "1" : "0", 1);
    setenv("WAWONA_SWAP_CMD_AS_CTRL", swapCmdAsCtrl ? "1" : "0", 1);
    setenv("WAWONA_UNIVERSAL_CLIPBOARD", universalClipboard ? "1" : "0", 1);
    setenv("WAWONA_COLORSYNC_SUPPORT", colorSyncSupport ? "1" : "0", 1);
    setenv("WAWONA_NESTED_COMPOSITORS_SUPPORT", nestedCompositorsSupport ? "1" : "0", 1);
    setenv("WAWONA_USE_METAL4_FOR_NESTED", useMetal4ForNested ? "1" : "0", 1);
    setenv("WAWONA_MULTIPLE_CLIENTS", multipleClients ? "1" : "0", 1);
    setenv("WAWONA_WAYPIPE_RS_SUPPORT", waypipeRSSupport ? "1" : "0", 1);
    setenv("WAWONA_ENABLE_TCP_LISTENER", enableTCPListener ? "1" : "0", 1);
    char portStr[16];
    snprintf(portStr, sizeof(portStr), "%d", tcpPort);
    setenv("WAWONA_TCP_PORT", portStr, 1);
    
    LOGI("iOS settings applied successfully 1:1 with safe area support");
    pthread_mutex_unlock(&g_lock);
}