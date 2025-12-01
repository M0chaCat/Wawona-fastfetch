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
static VkRenderPass g_renderPass = VK_NULL_HANDLE;
static VkCommandPool g_cmdPool = VK_NULL_HANDLE;
static VkImage g_images[8];
static VkImageView g_views[8];
static VkFramebuffer g_fbos[8];
static VkCommandBuffer g_cmds[8];
static uint32_t g_imageCount = 0;
static VkFormat g_format = VK_FORMAT_R8G8B8A8_UNORM;
static VkExtent2D g_extent = {640, 480};

static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;
static pthread_t g_render_thread = 0;

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
    app.apiVersion = VK_API_VERSION_1_0; // Use 1.0 for better compatibility

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
    uint32_t count = 0; vkEnumeratePhysicalDevices(g_instance, &count, NULL);
    if (count == 0) return VK_NULL_HANDLE;
    VkPhysicalDevice devs[4]; if (count > 4) count = 4; vkEnumeratePhysicalDevices(g_instance, &count, devs);
    return devs[0];
}

static int pick_queue_family(VkPhysicalDevice pd) {
    uint32_t count = 0; vkGetPhysicalDeviceQueueFamilyProperties(pd, &count, NULL);
    VkQueueFamilyProperties props[8]; if (count > 8) count = 8; vkGetPhysicalDeviceQueueFamilyProperties(pd, &count, props);
    for (uint32_t i = 0; i < count; i++) {
        VkBool32 sup = VK_FALSE; vkGetPhysicalDeviceSurfaceSupportKHR(pd, i, g_surface, &sup);
        if ((props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && sup) return (int)i;
    }
    return -1;
}

static int create_device(VkPhysicalDevice pd) {
    int q = pick_queue_family(pd); if (q < 0) return -1; g_queue_family = (uint32_t)q;
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci = { .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
    qci.queueFamilyIndex = g_queue_family; qci.queueCount = 1; qci.pQueuePriorities = &prio;
    const char* dev_exts[] = { VK_KHR_SWAPCHAIN_EXTENSION_NAME };
    VkDeviceCreateInfo dci = { .sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
    dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
    dci.enabledExtensionCount = (uint32_t)(sizeof(dev_exts)/sizeof(dev_exts[0]));
    dci.ppEnabledExtensionNames = dev_exts;
    if (vkCreateDevice(pd, &dci, NULL, &g_device) != VK_SUCCESS) return -1;
    vkGetDeviceQueue(g_device, g_queue_family, 0, &g_queue);
    return 0;
}

static int create_swapchain(VkPhysicalDevice pd) {
    VkSurfaceCapabilitiesKHR caps; vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pd, g_surface, &caps);
    VkExtent2D ext = caps.currentExtent; if (ext.width == 0 || ext.height == 0) ext = (VkExtent2D){ 640, 480 };
    g_extent = ext;
    VkSwapchainCreateInfoKHR sci = { .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR };
    sci.surface = g_surface; sci.minImageCount = caps.minImageCount > 0 ? caps.minImageCount : 2;
    sci.imageFormat = g_format; sci.imageColorSpace = VK_COLOR_SPACE_SRGB_NONLINEAR_KHR;
    sci.imageExtent = ext; sci.imageArrayLayers = 1; sci.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    sci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE; sci.preTransform = caps.currentTransform;
    sci.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR; sci.presentMode = VK_PRESENT_MODE_FIFO_KHR;
    sci.clipped = VK_TRUE;
    if (vkCreateSwapchainKHR(g_device, &sci, NULL, &g_swapchain) != VK_SUCCESS) return -1;
    return 0;
}

static int create_render_resources(void) {
    if (vkGetSwapchainImagesKHR(g_device, g_swapchain, &g_imageCount, NULL) != VK_SUCCESS || g_imageCount == 0) return -1;
    if (g_imageCount > 8) g_imageCount = 8;
    vkGetSwapchainImagesKHR(g_device, g_swapchain, &g_imageCount, g_images);

    // Render pass with clear on load
    VkAttachmentDescription ad = {0};
    ad.format = g_format; ad.samples = VK_SAMPLE_COUNT_1_BIT;
    ad.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR; ad.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    ad.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE; ad.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
    ad.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED; ad.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    VkAttachmentReference aref = { .attachment = 0, .layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL };
    VkSubpassDescription sub = {0}; sub.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS; sub.colorAttachmentCount = 1; sub.pColorAttachments = &aref;
    VkRenderPassCreateInfo rpci = { .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO };
    rpci.attachmentCount = 1; rpci.pAttachments = &ad; rpci.subpassCount = 1; rpci.pSubpasses = &sub;
    if (vkCreateRenderPass(g_device, &rpci, NULL, &g_renderPass) != VK_SUCCESS) return -1;

    // Command pool
    VkCommandPoolCreateInfo cpci = { .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
    cpci.queueFamilyIndex = g_queue_family; cpci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    if (vkCreateCommandPool(g_device, &cpci, NULL, &g_cmdPool) != VK_SUCCESS) return -1;

    // Image views, framebuffers, command buffers
    VkCommandBufferAllocateInfo cbai = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
    cbai.commandPool = g_cmdPool; cbai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cbai.commandBufferCount = g_imageCount;
    if (vkAllocateCommandBuffers(g_device, &cbai, g_cmds) != VK_SUCCESS) return -1;

    for (uint32_t i = 0; i < g_imageCount; i++) {
        VkImageViewCreateInfo ivci = { .sType = VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO };
        ivci.image = g_images[i]; ivci.viewType = VK_IMAGE_VIEW_TYPE_2D; ivci.format = g_format;
        ivci.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT; ivci.subresourceRange.baseMipLevel = 0; ivci.subresourceRange.levelCount = 1;
        ivci.subresourceRange.baseArrayLayer = 0; ivci.subresourceRange.layerCount = 1;
        if (vkCreateImageView(g_device, &ivci, NULL, &g_views[i]) != VK_SUCCESS) return -1;

    VkFramebufferCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO };
        fci.renderPass = g_renderPass; fci.attachmentCount = 1; fci.pAttachments = &g_views[i];
        fci.width = g_extent.width; fci.height = g_extent.height; fci.layers = 1;
        if (vkCreateFramebuffer(g_device, &fci, NULL, &g_fbos[i]) != VK_SUCCESS) return -1;

        // Record command buffer to clear color
        VkCommandBufferBeginInfo bi = { .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
        vkBeginCommandBuffer(g_cmds[i], &bi);
        VkClearValue clear = { .color = { .float32 = { 0.1f, 0.2f, 0.3f, 1.0f } } };
        VkRenderPassBeginInfo rbi = { .sType = VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO };
        rbi.renderPass = g_renderPass; rbi.framebuffer = g_fbos[i]; rbi.renderArea.offset.x = 0; rbi.renderArea.offset.y = 0; rbi.renderArea.extent = g_extent;
        rbi.clearValueCount = 1; rbi.pClearValues = &clear;
        vkCmdBeginRenderPass(g_cmds[i], &rbi, VK_SUBPASS_CONTENTS_INLINE);
        vkCmdEndRenderPass(g_cmds[i]);
        vkEndCommandBuffer(g_cmds[i]);
    }
    return 0;
}

static void* render_thread(void* arg) {
    (void)arg;
    LOGI("Render thread started");
    
    VkSemaphore imgAvail, renderDone;
    VkSemaphoreCreateInfo si = { .sType = VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    VkResult res = vkCreateSemaphore(g_device, &si, NULL, &imgAvail);
    if (res != VK_SUCCESS) {
        LOGE("Failed to create semaphore imgAvail: %d", res);
        return NULL;
    }
    res = vkCreateSemaphore(g_device, &si, NULL, &renderDone);
    if (res != VK_SUCCESS) {
        LOGE("Failed to create semaphore renderDone: %d", res);
        vkDestroySemaphore(g_device, imgAvail, NULL);
        return NULL;
    }
    
    int frame_count = 0;
    while (g_running) {
        uint32_t idx = 0;
        VkResult r = vkAcquireNextImageKHR(g_device, g_swapchain, UINT64_MAX, imgAvail, VK_NULL_HANDLE, &idx);
        if (r == VK_SUCCESS || r == VK_SUBOPTIMAL_KHR) {
            VkPipelineStageFlags stage = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
            VkSubmitInfo si2 = { .sType = VK_STRUCTURE_TYPE_SUBMIT_INFO };
            si2.waitSemaphoreCount = 1; 
            si2.pWaitSemaphores = &imgAvail; 
            si2.pWaitDstStageMask = &stage;
            si2.commandBufferCount = 1; 
            si2.pCommandBuffers = &g_cmds[idx];
            si2.signalSemaphoreCount = 1; 
            si2.pSignalSemaphores = &renderDone;
            
            // Use fence for proper synchronization
            VkFence fence;
            VkFenceCreateInfo fci = { .sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO };
            res = vkCreateFence(g_device, &fci, NULL, &fence);
            if (res != VK_SUCCESS) {
                LOGE("Failed to create fence: %d", res);
                break;
            }
            
            res = vkQueueSubmit(g_queue, 1, &si2, fence);
            if (res != VK_SUCCESS) {
                LOGE("vkQueueSubmit failed: %d", res);
                vkDestroyFence(g_device, fence, NULL);
                break;
            }
            
            // Wait for fence before presenting
            res = vkWaitForFences(g_device, 1, &fence, VK_TRUE, 1000000000); // 1 second timeout
            vkDestroyFence(g_device, fence, NULL);
            
            if (res != VK_SUCCESS) {
                LOGE("vkWaitForFences failed: %d", res);
                break;
            }
            
            VkPresentInfoKHR pi = { .sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR };
            pi.waitSemaphoreCount = 1; 
            pi.pWaitSemaphores = &renderDone;
            pi.swapchainCount = 1; 
            pi.pSwapchains = &g_swapchain; 
            pi.pImageIndices = &idx;
            
            res = vkQueuePresentKHR(g_queue, &pi);
            if (res != VK_SUCCESS && res != VK_SUBOPTIMAL_KHR) {
                LOGE("vkQueuePresentKHR failed: %d", res);
                break;
            }
            
            frame_count++;
            if (frame_count % 60 == 0) {
                LOGI("Rendered %d frames", frame_count);
            }
        } else if (r == VK_ERROR_OUT_OF_DATE_KHR) {
            LOGI("Swapchain out of date, skipping frame");
        } else {
            LOGE("vkAcquireNextImageKHR failed: %d", r);
            break;
        }
    }
    
    vkDeviceWaitIdle(g_device);
    vkDestroySemaphore(g_device, imgAvail, NULL);
    vkDestroySemaphore(g_device, renderDone, NULL);
    LOGI("Render thread stopped, rendered %d frames", frame_count);
    return NULL;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_MainActivity_nativeInit(JNIEnv* env, jobject thiz) {
    (void)env; (void)thiz;
    if (g_instance != VK_NULL_HANDLE) return;
    LOGI("Starting Wawona Compositor (Android stub)");
    VkResult r = create_instance();
    if (r != VK_SUCCESS) return;
    uint32_t count = 0; vkEnumeratePhysicalDevices(g_instance, &count, NULL);
    LOGI("vkEnumeratePhysicalDevices count=%u", count);
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
    
    if (create_render_resources() != 0) {
        LOGE("Failed to create render resources");
        ANativeWindow_release(win);
        pthread_mutex_unlock(&g_lock);
        return;
    }
    
    // Start render thread with delay to ensure surface is ready
    g_running = 1; 
    usleep(100000); // 100ms delay to let surface stabilize
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
        
        for (uint32_t i = 0; i < g_imageCount; i++) {
            if (g_fbos[i]) vkDestroyFramebuffer(g_device, g_fbos[i], NULL);
            if (g_views[i]) vkDestroyImageView(g_device, g_views[i], NULL);
        }
        
        if (g_cmdPool) vkDestroyCommandPool(g_device, g_cmdPool, NULL);
        if (g_renderPass) vkDestroyRenderPass(g_device, g_renderPass, NULL);
        if (g_swapchain) vkDestroySwapchainKHR(g_device, g_swapchain, NULL);
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
    
    g_imageCount = 0;
    LOGI("Surface destroyed");
    pthread_mutex_unlock(&g_lock);
}
