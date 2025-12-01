#import "metal_renderer.h"
#import "metal_dmabuf.h"
#import "metal_waypipe.h"
#if HAVE_VULKAN
#import "vulkan_renderer.h"
#endif
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/CAMetalLayer.h>
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
#import <IOSurface/IOSurface.h>
#endif
#import <simd/simd.h>
#include "WawonaCompositor.h"
#include "logging.h"
#include "wayland_color_management.h"
#include "wayland_viewporter.h"

// Forward declaration
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
extern IOSurfaceRef metal_dmabuf_create_iosurface_from_data(void *data, uint32_t width, uint32_t height, uint32_t stride, uint32_t format);
#endif

// Custom MTKView subclass that allows window dragging
@interface CompositorMTKView : MTKView
@end

@implementation CompositorMTKView
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
- (BOOL)mouseDownCanMoveWindow {
    // Allow window to be moved by dragging the background
    // This ensures window controls (resize, close, etc.) remain functional
    return YES;
}

- (NSView *)hitTest:(NSPoint)point {
    // Always return self to receive events for Wayland clients
    // But allow window controls to work via mouseDownCanMoveWindow
    return [super hitTest:point];
}

- (BOOL)acceptsMouseMovedEvents {
    // Accept mouse moved events for Wayland client input
    return YES;
}
#endif
@end

// Metal renderer implementation for full compositor rendering
// Used when forwarding entire compositor (like Weston) via waypipe

@interface MetalSurface : NSObject
@property (nonatomic, strong) id<MTLTexture> texture;  // Changed to strong for proper retention
@property (nonatomic, assign) CGRect frame;
@property (nonatomic, assign) struct wl_surface_impl *surface;
@property (nonatomic, assign) void *lastBufferData;  // Track buffer to avoid unnecessary recreations
@property (nonatomic, assign) int32_t lastWidth;
@property (nonatomic, assign) int32_t lastHeight;
@property (nonatomic, assign) uint32_t lastFormat;
@property (nonatomic, assign) CGColorSpaceRef colorSpace;
@property (nonatomic, assign) float u0;
@property (nonatomic, assign) float u1;
@property (nonatomic, assign) float vTop;
@property (nonatomic, assign) float vBottom;
@end

@implementation MetalSurface
- (void)dealloc {
    if (_colorSpace) {
        CGColorSpaceRelease(_colorSpace);
    }
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}
@end

@implementation MetalRenderer

- (instancetype)initWithMetalView:(MTKView *)view {
    self = [super init];
    if (self) {
        _metalView = view;
        _device = MTLCreateSystemDefaultDevice();
        if (!_device) {
            NSLog(@"❌ Failed to create Metal device");
            return nil;
        }
        
        _metalView.device = _device;
        _metalView.delegate = self;
        
        // Initialize Vulkan renderer if enabled and available
#if HAVE_VULKAN
        BOOL vkEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:@"EnableVulkanDrivers"];
        if (vkEnabled) {
            _vulkanRenderer = [[VulkanRenderer alloc] initWithMetalDevice:_device];
            if (_vulkanRenderer) {
                NSLog(@"✅ Vulkan renderer initialized inside Metal renderer");
            } else {
                NSLog(@"⚠️ Failed to initialize Vulkan renderer inside Metal renderer");
            }
        } else {
            _vulkanRenderer = nil;
            NSLog(@"ℹ️ Vulkan drivers disabled via settings; using Cocoa renderer");
        }
#else
        _vulkanRenderer = nil;
#endif

        // Enable continuous rendering for nested compositors (like Weston)
        // With enableSetNeedsDisplay=NO, MTKView uses its internal display link for continuous rendering
        // This ensures the view draws continuously at display refresh rate
        _metalView.enableSetNeedsDisplay = NO;  // Continuous rendering mode
        _metalView.paused = NO;  // Keep rendering active
        
        // Ensure the Metal layer is configured for continuous rendering
        // The CAMetalLayer will automatically sync with the display refresh rate
        CAMetalLayer *metalLayer = (CAMetalLayer *)_metalView.layer;
        if (metalLayer) {
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
            metalLayer.displaySyncEnabled = YES;  // Sync with display refresh
#endif
            metalLayer.presentsWithTransaction = NO;  // Use standard presentation
            
            // Set output color space to main display color space
            // This ensures correct color rendering for HDR/WCG content
            CGColorSpaceRef colorSpace = get_display_color_space();
            if (colorSpace) {
                metalLayer.colorspace = colorSpace;
                CFRelease(colorSpace); // metalLayer retains it
                NSLog(@"✅ Metal layer color space configured");
            }
        }
        
        _commandQueue = [_device newCommandQueue];
        if (!_commandQueue) {
            NSLog(@"❌ Failed to create Metal command queue");
            return nil;
        }
        
        // Create render pipeline with Metal library
        id<MTLLibrary> library = nil;
        
        // First try to load compiled metallib from bundle/resources (for app bundles)
        NSBundle *mainBundle = [NSBundle mainBundle];
        NSURL *metallibURL = [mainBundle URLForResource:@"metal_shaders" withExtension:@"metallib"];
        
        // If not in bundle, try to find metallib next to executable (for command-line tools)
        if (!metallibURL) {
            // Get executable path - try multiple methods
            NSString *executablePath = nil;
            
            // Method 1: Use NSBundle executablePath (most reliable)
            if (mainBundle && mainBundle.executablePath) {
                executablePath = [mainBundle.executablePath stringByDeletingLastPathComponent];
            }
            
            // Method 2: Use process arguments[0] (fallback)
            if (!executablePath && [NSProcessInfo processInfo].arguments.count > 0) {
                NSString *arg0 = [NSProcessInfo processInfo].arguments[0];
                if ([arg0 isAbsolutePath]) {
                    executablePath = [arg0 stringByDeletingLastPathComponent];
                } else {
                    // Resolve relative path
                    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
                    executablePath = [[cwd stringByAppendingPathComponent:arg0] stringByDeletingLastPathComponent];
                }
            }
            
            if (executablePath) {
                NSString *metallibPath = [executablePath stringByAppendingPathComponent:@"metal_shaders.metallib"];
                if ([[NSFileManager defaultManager] fileExistsAtPath:metallibPath]) {
                    metallibURL = [NSURL fileURLWithPath:metallibPath];
                }
            }
        }
        
        if (metallibURL && [[NSFileManager defaultManager] fileExistsAtPath:metallibURL.path]) {
            NSError *error = nil;
            library = [_device newLibraryWithURL:metallibURL error:&error];
            if (library) {
                NSLog(@"✅ Loaded Metal shaders from: %@", metallibURL.path);
            } else {
                NSLog(@"⚠️ Failed to load Metal library from %@: %@", metallibURL.path, error);
            }
        }
        
        // Fallback to default library (for app bundles)
        if (!library) {
            library = [_device newDefaultLibrary];
            if (library) {
                NSLog(@"✅ Using default Metal library");
            } else {
                NSLog(@"⚠️ Default Metal library not found - shaders may need to be compiled");
            }
        }
        
        id<MTLFunction> vertexFunction = nil;
        id<MTLFunction> fragmentFunction = nil;
        
        if (library) {
            vertexFunction = [library newFunctionWithName:@"vertexShader"];
            fragmentFunction = [library newFunctionWithName:@"fragmentShader"];
            
            if (!vertexFunction) {
                NSLog(@"⚠️ vertexShader function not found in Metal library");
            }
            if (!fragmentFunction) {
                NSLog(@"⚠️ fragmentShader function not found in Metal library");
            }
        }
        
        if (vertexFunction && fragmentFunction) {
            MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
            pipelineDescriptor.vertexFunction = vertexFunction;
            pipelineDescriptor.fragmentFunction = fragmentFunction;
            pipelineDescriptor.colorAttachments[0].pixelFormat = _metalView.colorPixelFormat;
            // For nested compositors, surfaces are typically opaque - disable blending for better performance
            // and to prevent white artifacts from blending with clear color
            pipelineDescriptor.colorAttachments[0].blendingEnabled = NO;
            // If blending is needed later, use these settings:
            // pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
            // pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
            // pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
            // pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
            // pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
            // pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorZero;
            // pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorZero;
            
            // Configure vertex descriptor to match our vertex layout
            MTLVertexDescriptor *vertexDescriptor = [[MTLVertexDescriptor alloc] init];
            // Position attribute (index 0)
            vertexDescriptor.attributes[0].format = MTLVertexFormatFloat2;
            vertexDescriptor.attributes[0].offset = 0;
            vertexDescriptor.attributes[0].bufferIndex = 0;
            // Texture coordinate attribute (index 1)
            vertexDescriptor.attributes[1].format = MTLVertexFormatFloat2;
            vertexDescriptor.attributes[1].offset = sizeof(simd_float2);
            vertexDescriptor.attributes[1].bufferIndex = 0;
            // Buffer layout
            vertexDescriptor.layouts[0].stride = sizeof(simd_float2) * 2; // position + texCoord
            vertexDescriptor.layouts[0].stepRate = 1;
            vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerVertex;
            
            pipelineDescriptor.vertexDescriptor = vertexDescriptor;
            
            NSError *error = nil;
            _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
            if (!_pipelineState) {
                NSLog(@"⚠️ Failed to create pipeline state: %@", error);
            } else {
                NSLog(@"✅ Metal render pipeline created successfully");
            }
        } else {
            NSLog(@"⚠️ Shader functions not found - using basic rendering");
            // Will use basic rendering without shaders
        }
        
        _surfaceTextures = [[NSMutableDictionary alloc] init];
        
        // Initialize Metal waypipe context for video codec support
        _waypipeContext = metal_waypipe_create(_device);
        if (_waypipeContext) {
            NSLog(@"✅ Metal waypipe context initialized");
        } else {
            NSLog(@"⚠️ Failed to initialize Metal waypipe context");
        }
        
        NSLog(@"✅ Metal renderer initialized");
    }
    return self;
}

- (void)dealloc {
    // Clean up Metal waypipe context
    if (_waypipeContext) {
        metal_waypipe_destroy(_waypipeContext);
        _waypipeContext = NULL;
    }
    
    // Clear delegate to prevent callbacks after deallocation
    if (_metalView) {
        _metalView.delegate = nil;
    }
    
    // Clear surfaces
    @synchronized(self) {
        _surfaceTextures = nil;
    }
    
#if !__has_feature(objc_arc)
    [super dealloc];
#endif
}

- (void)renderSurface:(struct wl_surface_impl *)surface {
    if (!surface || !surface->buffer_resource) {
        return;
    }
    
    // Get buffer data - handle both SHM buffers and EGL buffers
    struct buffer_data {
        void *data;
        int32_t offset;
        int32_t width;
        int32_t height;
        int32_t stride;
        uint32_t format;
    };
    
    int32_t width, height, stride;
    uint32_t format;
    void *data = NULL;
    struct wl_shm_buffer *shm_buffer = wl_shm_buffer_get(surface->buffer_resource);
    struct buffer_data *buf_data = NULL;
    
    // First, try to handle as SHM buffer
    if (shm_buffer) {
        // Standard Wayland SHM buffer
        width = wl_shm_buffer_get_width(shm_buffer);
        height = wl_shm_buffer_get_height(shm_buffer);
        stride = wl_shm_buffer_get_stride(shm_buffer);
        format = wl_shm_buffer_get_format(shm_buffer);
        
        wl_shm_buffer_begin_access(shm_buffer);
        data = wl_shm_buffer_get_data(shm_buffer);
    } else {
        // Not an SHM buffer - might be EGL buffer or custom buffer with buffer_data
        buf_data = wl_resource_get_user_data(surface->buffer_resource);
        
        if (buf_data && buf_data->data) {
            // Custom buffer with buffer_data (from wayland_shm.c)
            width = buf_data->width;
            height = buf_data->height;
            stride = buf_data->stride;
            format = buf_data->format;
            data = (char *)buf_data->data + buf_data->offset;
            
            if ((uintptr_t)data < (uintptr_t)buf_data->data) {
                NSLog(@"[METAL RENDERER] ❌ Invalid data pointer calculation");
                return;
            }
        } else {
            // Neither SHM buffer nor custom buffer_data - likely an EGL buffer
            
            // Try using Vulkan renderer
            // Render via Vulkan bridge if available
#if HAVE_VULKAN
            if (self.vulkanRenderer) {
                id<MTLTexture> vulkanTexture = [(VulkanRenderer *)self.vulkanRenderer renderEGLSurface:surface];
                if (vulkanTexture) {
                    // We got a texture from Vulkan!
                    // Update MetalSurface and return
                    NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
                    @synchronized(self) {
                        if (!_surfaceTextures) _surfaceTextures = [[NSMutableDictionary alloc] init];
                        MetalSurface *ms = _surfaceTextures[key];
                        if (!ms) {
                            ms = [[MetalSurface alloc] init];
                            ms.surface = surface;
                            _surfaceTextures[key] = ms;
                        }
                        ms.texture = vulkanTexture;
                        ms.frame = CGRectMake(surface->x, surface->y, surface->width, surface->height);
                        
                        // Update metadata to prevent unnecessary recreations if we were tracking it
                        ms.lastBufferData = NULL; // Not using CPU buffer
                        ms.lastWidth = surface->width;
                        ms.lastHeight = surface->height;
                        ms.lastFormat = 0; // EGL format
                    }
                    
                    // Release buffer
                     if (!surface->buffer_release_sent) {
                        struct wl_client *release_buffer_client = wl_resource_get_client(surface->buffer_resource);
                        if (release_buffer_client) {
                            wl_buffer_send_release(surface->buffer_resource);
                            surface->buffer_release_sent = true;
                        }
                    }
                    return;
                }
            }

            // EGL buffers are not yet supported without Vulkan bridge
            NSLog(@"[METAL RENDERER] ⚠️ EGL buffer detected but Vulkan render unavailable - skipping render");
#endif
            
            // Still send buffer release to client
            if (!surface->buffer_release_sent) {
                struct wl_client *release_buffer_client = wl_resource_get_client(surface->buffer_resource);
                if (release_buffer_client) {
                    wl_buffer_send_release(surface->buffer_resource);
                    surface->buffer_release_sent = true;
                }
            }
            return;
        }
    }
    
    // Verify we have valid data
    if (!data) {
        if (shm_buffer) {
            wl_shm_buffer_end_access(shm_buffer);
        }
        return;
    }
    
    // OPTIMIZED: Check if we can reuse existing texture
    // Only recreate if buffer data pointer, dimensions, or format changed
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
    @synchronized(self) {
        if (!_surfaceTextures) {
            _surfaceTextures = [[NSMutableDictionary alloc] init];
        }
        
        MetalSurface *metalSurface = _surfaceTextures[key];
        BOOL needsNewTexture = YES;
        
        if (metalSurface && metalSurface.texture) {
            // Check if buffer data, dimensions, or format changed
            if (metalSurface.lastBufferData == data &&
                metalSurface.lastWidth == width &&
                metalSurface.lastHeight == height &&
                metalSurface.lastFormat == format) {
                // Buffer data pointer matches - reuse existing texture object
                needsNewTexture = NO;
                
                // CRITICAL: For SHM buffers, we MUST re-upload data even if pointer is the same
                // The client likely updated the content in place
                // Only skip upload if we know for sure content hasn't changed (difficult for SHM)
                // Since renderSurface is called on commit, we assume content changed
                if (shm_buffer || (buf_data && buf_data->data)) {
                    MTLRegion region = MTLRegionMake2D(0, 0, width, height);
                    [metalSurface.texture replaceRegion:region
                                            mipmapLevel:0
                                              withBytes:data
                                            bytesPerRow:stride];
                }
            }
        }
        
        if (!metalSurface) {
            metalSurface = [[MetalSurface alloc] init];
            metalSurface.surface = surface;
            _surfaceTextures[key] = metalSurface;
        }
        
        id<MTLTexture> texture = nil;
        
        if (needsNewTexture) {
            // Create texture from buffer data
            // For DMA-BUF/IOSurface, create IOSurface and Metal texture from it
            // For regular buffers, create texture directly
            
            // Try to create IOSurface-based texture (for DMA-BUF support)
#if !TARGET_OS_IPHONE && !TARGET_OS_SIMULATOR
            IOSurfaceRef iosurface = metal_dmabuf_create_iosurface_from_data(data, width, height, stride, 0);
            if (iosurface) {
                // Create Metal texture from IOSurface
                MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                                              width:width
                                                                                                             height:height
                                                                                                          mipmapped:NO];
                textureDescriptor.usage = MTLTextureUsageShaderRead;
                textureDescriptor.storageMode = MTLStorageModeShared;
                
                texture = [_device newTextureWithDescriptor:textureDescriptor iosurface:iosurface plane:0];
                CFRelease(iosurface);
                
                if (texture) {
                    NSLog(@"[METAL] Created texture from IOSurface: %dx%d", width, height);
                } else {
                    NSLog(@"[METAL] Failed to create texture from IOSurface");
                }
            }
#endif
            
            // Fallback to direct texture creation if IOSurface method failed
            if (!texture) {
                // Create Metal texture from buffer data directly
                MTLTextureDescriptor *textureDescriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                                              width:width
                                                                                                             height:height
                                                                                                          mipmapped:NO];
                textureDescriptor.usage = MTLTextureUsageShaderRead;
                
                texture = [_device newTextureWithDescriptor:textureDescriptor];
                if (!texture) {
                    NSLog(@"❌ Failed to create Metal texture");
                    return;
                }
                
                // Upload pixel data to texture
                MTLRegion region = MTLRegionMake2D(0, 0, width, height);
                [texture replaceRegion:region mipmapLevel:0 withBytes:data bytesPerRow:stride];
                NSLog(@"[METAL] Created texture directly from buffer: %dx%d", width, height);
            }
            
            // Update texture and cache buffer info
            metalSurface.texture = texture;
            metalSurface.lastBufferData = data;
            metalSurface.lastWidth = width;
            metalSurface.lastHeight = height;
            metalSurface.lastFormat = format;

            // Handle Color Management
            if (surface->color_management) {
                struct wp_color_management_surface_impl *color_surface = 
                    (struct wp_color_management_surface_impl *)surface->color_management;
                
                if (color_surface && color_surface->current_image_description) {
                    struct wp_image_description_impl *desc = color_surface->current_image_description;
                    
                    // Create color space if not already created
                    if (!desc->color_space) {
                        desc->color_space = create_colorspace_from_image_description(desc);
                    }
                    
                    // Update surface color space
                    if (desc->color_space) {
                        if (metalSurface.colorSpace) {
                            CGColorSpaceRelease(metalSurface.colorSpace);
                        }
                        metalSurface.colorSpace = CGColorSpaceRetain(desc->color_space);
                    }
                }
            }
        } else {
            // Reuse existing texture - no need to recreate
            texture = metalSurface.texture;
        }
        
        // For nested compositors (like Weston), ALWAYS scale the surface to fill the entire Metal view
        // Get the Metal view frame (points) to determine the target size
        CGRect targetFrame = CGRectMake(surface->x, surface->y, width, height);
        struct wl_viewport_impl *vp = wl_viewport_from_surface(surface);
        if (vp && vp->has_destination) {
            targetFrame.size.width = vp->dst_width;
            targetFrame.size.height = vp->dst_height;
        }
        if (_metalView) {
            CGRect viewBounds = _metalView.frame;  // Use frame.size (points) not bounds
            
            // ALWAYS scale to fill view for nested compositors
            // The nested compositor's main output should always fill the entire window
            // Check if this is likely the main compositor output:
            // 1. Surface at origin (0,0) - most common case
            // 2. Surface is the largest/only surface
            // 3. Surface area is significant (not a small overlay like cursor)
            BOOL shouldScaleToFill = NO;
            
            // CRITICAL: Never scale small surfaces (cursors, icons, etc.)
            // Cursor surfaces are typically 32x32, 64x64, or similar small sizes
            // Main compositor outputs are much larger (typically > 800x600)
            NSInteger thisSurfaceArea = width * height;
            const NSInteger MAX_CURSOR_SIZE = 256; // Cursors are typically <= 256x256
            BOOL isSmallSurface = (width <= MAX_CURSOR_SIZE && height <= MAX_CURSOR_SIZE);
            
            if (isSmallSurface) {
                // This is likely a cursor or small overlay - never scale it
                shouldScaleToFill = NO;
                NSLog(@"[METAL] Small surface detected (%dx%d) - not scaling (likely cursor)", width, height);
            } else {
                // For large surfaces, check if this should be scaled to fill
                // Check if this is the largest surface (likely main output)
                @synchronized(self) {
                    NSInteger maxSurfaceArea = 0;
                    NSInteger totalLargeSurfaces = 0;
                    
                    for (MetalSurface *otherSurface in [_surfaceTextures allValues]) {
                        if (otherSurface != metalSurface && otherSurface.texture) {
                            CGRect otherFrame = otherSurface.frame;
                            NSInteger otherArea = otherFrame.size.width * otherFrame.size.height;
                            if (otherArea > maxSurfaceArea) {
                                maxSurfaceArea = otherArea;
                            }
                            // Count large surfaces (not cursors)
                            if (otherFrame.size.width > MAX_CURSOR_SIZE || otherFrame.size.height > MAX_CURSOR_SIZE) {
                                totalLargeSurfaces++;
                            }
                        }
                    }
                    
                    // Scale to fill if:
                    // 1. This is the only large surface (first/main compositor output), OR
                    // 2. This is the largest surface and reasonably large (> 10000 pixels), OR
                    // 3. Surface is at origin (0,0) and large (main compositor output)
                    // Be more aggressive: if it's large and we don't have many large surfaces, scale it
                    if (totalLargeSurfaces == 0 || 
                        (thisSurfaceArea >= maxSurfaceArea && thisSurfaceArea > 10000) ||
                        (surface->x == 0 && surface->y == 0 && thisSurfaceArea > 10000) ||
                        (totalLargeSurfaces <= 1 && thisSurfaceArea > 50000)) {
                        shouldScaleToFill = YES;
                        NSLog(@"[METAL] Scaling large surface to fill: buffer=%dx%d (area=%ld, pos=%d,%d, totalLarge=%ld, maxArea=%ld)",
                              width, height, (long)thisSurfaceArea, surface->x, surface->y, (long)totalLargeSurfaces, (long)maxSurfaceArea);
                    } else {
                        NSLog(@"[METAL] Not scaling surface: buffer=%dx%d (area=%ld, pos=%d,%d, maxArea=%ld, totalLarge=%ld)",
                              width, height, (long)thisSurfaceArea, surface->x, surface->y, (long)maxSurfaceArea, (long)totalLargeSurfaces);
                    }
                }
            }
            
            if (shouldScaleToFill) {
                // Scale to fill entire view - this handles nested compositors like Weston
                // The buffer will be stretched to fill the view
                targetFrame = CGRectMake(0, 0, viewBounds.size.width, viewBounds.size.height);
                NSLog(@"[METAL] Scaling surface to fill view: buffer=%dx%d -> view=%.0fx%.0f (surface at %d,%d, viewBounds=%.0fx%.0f)",
                      width, height, viewBounds.size.width, viewBounds.size.height, 
                      surface->x, surface->y, viewBounds.size.width, viewBounds.size.height);
            } else {
                // For non-main surfaces, still ensure they don't exceed view bounds
                CGFloat maxX = viewBounds.size.width;
                CGFloat maxY = viewBounds.size.height;
                if (targetFrame.origin.x + targetFrame.size.width > maxX) {
                    targetFrame.size.width = maxX - targetFrame.origin.x;
                }
                if (targetFrame.origin.y + targetFrame.size.height > maxY) {
                    targetFrame.size.height = maxY - targetFrame.origin.y;
                }
            }
        }
        metalSurface.frame = targetFrame;

        // Set texture sampling coordinates (apply viewporter source crop if present)
        float u0 = 0.0f, u1 = 1.0f, vTop = 0.0f, vBottom = 1.0f;
        if (vp && vp->has_source) {
            u0 = (float)(vp->src_x / (double)width);
            u1 = (float)((vp->src_x + vp->src_width) / (double)width);
            vTop = (float)(vp->src_y / (double)height);
            vBottom = (float)((vp->src_y + vp->src_height) / (double)height);
        }
        metalSurface.u0 = u0;
        metalSurface.u1 = u1;
        metalSurface.vTop = vTop;
        metalSurface.vBottom = vBottom;
    }
    
    // Release SHM buffer access if we used one
    if (shm_buffer) {
        wl_shm_buffer_end_access(shm_buffer);
    }
    
    // With continuous rendering enabled (enableSetNeedsDisplay=NO), 
    // we don't need to call setNeedsDisplay: - the view renders automatically
    // However, we can still trigger it if needed for immediate updates
    // For now, let continuous rendering handle it automatically
}

- (void)removeSurface:(struct wl_surface_impl *)surface {
    if (!surface || !self) return;
    
    NSNumber *key = [NSNumber numberWithUnsignedLongLong:(unsigned long long)surface];
    @synchronized(self) {
        if (_surfaceTextures) {
            [_surfaceTextures removeObjectForKey:key];
        }
    }
}

- (void)setNeedsDisplay {
    // CRITICAL: Force immediate synchronous redraw for nested compositors
    // This must be synchronous to ensure updates appear immediately when clients commit buffers
    // Wayland compositors MUST repaint immediately on surface commit - no async delays!
    if (!self.metalView) return;
    
    // Check if we're on main thread - if not, dispatch sync to main thread
    if ([NSThread isMainThread]) {
        [self setNeedsDisplaySync];
    } else {
        dispatch_sync(dispatch_get_main_queue(), ^{
            [self setNeedsDisplaySync];
        });
    }
}

- (void)setNeedsDisplaySync {
    // This runs on main thread - force immediate redraw
    // CRITICAL: For nested compositors, we MUST redraw immediately when textures update
    if (!self.metalView) return;
    
    BOOL wasEnabled = self.metalView.enableSetNeedsDisplay;
    if (!wasEnabled) {
        // Temporarily enable to force immediate frame
        self.metalView.enableSetNeedsDisplay = YES;
    }
    
    // Trigger redraw immediately - this will cause MTKView to call drawInMTKView:
#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
    [self.metalView setNeedsDisplay];
#else
    [self.metalView setNeedsDisplay:YES];
#endif
    
    // CRITICAL: Force immediate rendering by directly calling the delegate method
    // This bypasses the display link and renders immediately for nested compositor updates
    // Wayland compositors MUST repaint synchronously when clients commit buffers
    if (self.metalView.delegate == self) {
        // We are the delegate - directly call drawInMTKView to force immediate render
        [self drawInMTKView:self.metalView];
    }
    
    // Restore continuous rendering mode after triggering redraw
    if (!wasEnabled) {
        self.metalView.enableSetNeedsDisplay = NO;
    }
}

// MTKViewDelegate
- (void)drawInMTKView:(MTKView *)view {
    @autoreleasepool {
        // Validate required objects - check self first to ensure we're not deallocated
        // Continue rendering even when window isn't focused - clients need frame callbacks
        // This method is called continuously at display refresh rate when enableSetNeedsDisplay=NO
        if (!self || !_commandQueue) {
            return;
        }
        
        // Log first few draws to verify continuous rendering is working
        static int continuous_draw_count = 0;
        if (continuous_draw_count < 5) {
            NSLog(@"[METAL] drawInMTKView: called (continuous rendering active, draw #%d)", continuous_draw_count);
            continuous_draw_count++;
        }
        
        // Safely get a snapshot of surfaces to avoid race conditions
        NSArray<MetalSurface *> *surfaces = nil;
        @synchronized(self) {
            if (!_surfaceTextures) {
                return;
            }
            // Create a copy of the array to avoid issues if dictionary is modified during iteration
            surfaces = [[_surfaceTextures allValues] copy];
        }
        
        if (!surfaces || surfaces.count == 0) {
            // No surfaces to draw - just clear the view
            id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
            if (!commandBuffer) {
                return;
            }
            
            MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
            if (!renderPassDescriptor) {
                return;
            }
            
            MTLRenderPassColorAttachmentDescriptor *colorAttachment = renderPassDescriptor.colorAttachments[0];
            if (colorAttachment) {
                colorAttachment.clearColor = MTLClearColorMake(0.1, 0.1, 0.2, 1.0);
                colorAttachment.loadAction = MTLLoadActionClear;
                colorAttachment.storeAction = MTLStoreActionStore;
            }
            
            id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
            if (renderEncoder) {
                // Set scissor rect even when clearing
                MTLScissorRect scissorRect;
                scissorRect.x = 0;
                scissorRect.y = 0;
                // Use drawableSize for scissor rect (pixels) - matches viewport
                scissorRect.width = (NSUInteger)view.drawableSize.width;
                scissorRect.height = (NSUInteger)view.drawableSize.height;
                [renderEncoder setScissorRect:scissorRect];
                [renderEncoder endEncoding];
            }
            
            id<CAMetalDrawable> drawable = view.currentDrawable;
            if (drawable) {
                [commandBuffer presentDrawable:drawable];
            }
            
            [commandBuffer commit];
            return;
        }
        
        id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
        if (!commandBuffer) {
            return;
        }
        
        MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
        if (!renderPassDescriptor) {
            return;
        }
        
        // Set clear color BEFORE creating render encoder (must be done before encoder creation)
        MTLRenderPassColorAttachmentDescriptor *colorAttachment = renderPassDescriptor.colorAttachments[0];
        if (colorAttachment) {
            colorAttachment.clearColor = MTLClearColorMake(0.1, 0.1, 0.2, 1.0);
            // Ensure we load and store the color attachment properly
            colorAttachment.loadAction = MTLLoadActionClear;
            colorAttachment.storeAction = MTLStoreActionStore;
        }
        
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        if (!renderEncoder) {
            return;
        }
        
        // Set scissor rect to clip rendering to view bounds (prevents artifacts outside view)
        MTLScissorRect scissorRect;
        scissorRect.x = 0;
        scissorRect.y = 0;
        scissorRect.width = (NSUInteger)view.bounds.size.width;
        scissorRect.height = (NSUInteger)view.bounds.size.height;
        [renderEncoder setScissorRect:scissorRect];
        
        // Set up render state
        if (_pipelineState) {
            [renderEncoder setRenderPipelineState:_pipelineState];
        }
        
        // Draw all surfaces (using the snapshot we created earlier)
        for (MetalSurface *metalSurface in surfaces) {
            // Validate surface is still valid
            if (!metalSurface || !metalSurface.texture) {
                continue;
            }
            
            // Set up viewport for this surface
            // CRITICAL: Use view.frame.size (points) not view.bounds.size for coordinate calculations
            // MTKView automatically handles Retina scaling for drawableSize, but frame/bounds are in points
            CGRect frame = metalSurface.frame;
            CGSize viewSize = view.frame.size;  // Use frame.size (points) for coordinate calculations
            
            // Use full-screen viewport (Metal uses normalized device coordinates)
            // Metal viewport: bottom-left origin, but we'll use full screen and transform vertices
            // Use drawableSize for viewport (pixels) - MTKView handles Retina scaling automatically
            MTLViewport viewport;
            viewport.originX = 0;
            viewport.originY = 0;
            viewport.width = view.drawableSize.width;   // Use drawableSize (pixels) for viewport
            viewport.height = view.drawableSize.height;  // MTKView handles Retina scaling
            viewport.znear = 0.0;
            viewport.zfar = 1.0;
            [renderEncoder setViewport:viewport];
            
            // Bind texture
            [renderEncoder setFragmentTexture:metalSurface.texture atIndex:0];
            
            // Create vertex data for a textured quad
            // Vertices: position (x, y), texture coordinate (u, v)
            // Positions are in normalized device coordinates (-1 to 1), then transformed to screen space
            typedef struct {
                simd_float2 position;
                simd_float2 texCoord;
            } Vertex;
            
            // Convert frame coordinates (points) to normalized device coordinates (-1 to 1)
            // Wayland uses top-left origin, Metal NDC uses bottom-left origin
            // Use viewSize (points) for coordinate calculations - this ensures correct scaling
            float x0 = (frame.origin.x / viewSize.width) * 2.0f - 1.0f;
            float x1 = ((frame.origin.x + frame.size.width) / viewSize.width) * 2.0f - 1.0f;
            float y0 = 1.0f - ((frame.origin.y + frame.size.height) / viewSize.height) * 2.0f; // Flip Y
            float y1 = 1.0f - (frame.origin.y / viewSize.height) * 2.0f; // Flip Y
            
            // Ensure we're using the full viewport (for nested compositors)
            // Clamp coordinates to full screen if frame is close to view size (within 1 point tolerance)
            if (fabs(frame.size.width - viewSize.width) < 1.0f && 
                fabs(frame.size.height - viewSize.height) < 1.0f) {
                // Surface fills the view - use full screen coordinates
                x0 = -1.0f;
                x1 = 1.0f;
                y0 = -1.0f;
                y1 = 1.0f;
            }
            
            // Create vertices for a quad covering the surface frame
            // Texture coordinates: apply viewporter source crop and flip Y for Metal
            Vertex vertices[4];
            // Bottom-left (screen space)
            vertices[0].position = simd_make_float2(x0, y0);
            vertices[0].texCoord = simd_make_float2(metalSurface.u0, metalSurface.vBottom);
            // Bottom-right (screen space)
            vertices[1].position = simd_make_float2(x1, y0);
            vertices[1].texCoord = simd_make_float2(metalSurface.u1, metalSurface.vBottom);
            // Top-left (screen space)
            vertices[2].position = simd_make_float2(x0, y1);
            vertices[2].texCoord = simd_make_float2(metalSurface.u0, metalSurface.vTop);
            // Top-right (screen space)
            vertices[3].position = simd_make_float2(x1, y1);
            vertices[3].texCoord = simd_make_float2(metalSurface.u1, metalSurface.vTop);
            
            // Create vertex buffer
            id<MTLBuffer> vertexBuffer = [_device newBufferWithBytes:vertices
                                                               length:sizeof(vertices)
                                                              options:MTLResourceStorageModeShared];
            
            if (vertexBuffer) {
                // Set vertex buffer
                [renderEncoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
                
                // Draw quad as triangle strip (4 vertices = 2 triangles)
                [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip
                                  vertexStart:0
                                  vertexCount:4];
            }
        }
        
        [renderEncoder endEncoding];
        
        id<CAMetalDrawable> drawable = view.currentDrawable;
        if (drawable) {
            [commandBuffer presentDrawable:drawable];
        }
        
        [commandBuffer commit];
    }
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    // Handle size changes - Metal view is resizing to match compositor window
    NSLog(@"[METAL] Metal view drawable size changing to %.0fx%.0f", size.width, size.height);
    
    // CRITICAL: Do NOT set view.bounds to drawable size!
    // drawableSize is in pixels (may be Retina-scaled), but bounds should be in points
    // MTKView automatically handles the conversion - we should NOT override it
    // The view's frame/bounds should match the window content size in points, not pixels
    // MTKView will automatically create a drawable that matches the pixel density
    
    // The view's frame should already be updated by the window resize handler
    // This delegate method is called when the drawable (backing texture) size changes
    // We don't need to do anything special here - the rendering code will use the new size
    // MTKView handles bounds automatically based on the view's frame
}

#if TARGET_OS_IPHONE || TARGET_OS_SIMULATOR
- (void)drawSurfacesInRect:(CGRect)dirtyRect {
#else
- (void)drawSurfacesInRect:(NSRect)dirtyRect {
#endif
    // Stub - MetalRenderer uses MTKViewDelegate (drawInMTKView) for rendering
}

@end
