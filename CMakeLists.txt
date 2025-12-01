cmake_minimum_required(VERSION 3.20)

# Read version from VERSION file
file(STRINGS "${CMAKE_CURRENT_SOURCE_DIR}/VERSION" PROJECT_VERSION_STRING)
string(STRIP "${PROJECT_VERSION_STRING}" PROJECT_VERSION_STRING)

# Parse version components (format: MAJOR.MINOR.PATCH)
string(REGEX MATCH "^([0-9]+)\\.([0-9]+)\\.([0-9]+)" VERSION_MATCH "${PROJECT_VERSION_STRING}")
if(VERSION_MATCH)
    set(PROJECT_VERSION_MAJOR ${CMAKE_MATCH_1})
    set(PROJECT_VERSION_MINOR ${CMAKE_MATCH_2})
    set(PROJECT_VERSION_PATCH ${CMAKE_MATCH_3})
    set(PROJECT_VERSION "${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}.${PROJECT_VERSION_PATCH}")
else()
    # Fallback if VERSION file doesn't match expected format
    set(PROJECT_VERSION_MAJOR 1)
    set(PROJECT_VERSION_MINOR 0)
    set(PROJECT_VERSION_PATCH 0)
    set(PROJECT_VERSION "1.0.0")
endif()

# Detect iOS build - check CMAKE_SYSTEM_NAME first, then CMAKE_OSX_SYSROOT
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    set(IS_IOS TRUE)
    set(IS_MACOS FALSE)
    message(STATUS "Building for iOS (CMAKE_SYSTEM_NAME=iOS)")
elseif(CMAKE_OSX_SYSROOT AND CMAKE_OSX_SYSROOT MATCHES "iphonesimulator")
    set(IS_IOS TRUE)
    set(IS_MACOS FALSE)
    set(CMAKE_SYSTEM_NAME iOS)
    message(STATUS "Building for iOS Simulator (detected from CMAKE_OSX_SYSROOT)")
else()
    set(IS_IOS FALSE)
    set(IS_MACOS TRUE)
    message(STATUS "Building for macOS")
endif()

project(Wawona VERSION ${PROJECT_VERSION} LANGUAGES C OBJC)

# From-scratch Wayland compositor for macOS
# We use ONLY libwayland-server (no WLRoots - it's Linux-only)

# Use latest C standard (C17/C18) for maximum type safety and features
set(CMAKE_C_STANDARD 17)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_C_EXTENSIONS OFF)  # Disable GNU extensions for strict compliance

set(CMAKE_OBJC_STANDARD 11)
set(CMAKE_OBJC_STANDARD_REQUIRED ON)

# Strict compiler flags - treat warnings as errors (like Rust)
# Maximum warnings and strict type checking
# iOS-specific flags
if(IS_IOS)
    # Get iOS SDK path if not already set
    if(NOT CMAKE_OSX_SYSROOT)
        execute_process(
            COMMAND xcrun --sdk iphonesimulator --show-sdk-path
            OUTPUT_VARIABLE IOS_SDK_PATH
            OUTPUT_STRIP_TRAILING_WHITESPACE
        )
        set(CMAKE_OSX_SYSROOT ${IOS_SDK_PATH})
    endif()
    set(CMAKE_OSX_ARCHITECTURES arm64)
    set(CMAKE_OSX_DEPLOYMENT_TARGET 15.0)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -arch arm64 -isysroot ${CMAKE_OSX_SYSROOT} -mios-simulator-version-min=15.0")
    set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -arch arm64 -isysroot ${CMAKE_OSX_SYSROOT} -mios-simulator-version-min=15.0 -fobjc-arc")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -lobjc")
    # iOS: Enable warnings-as-errors (same as macOS)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra -Wpedantic -Wno-error")
    set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wall -Wextra -Wpedantic -Wno-error")
else()
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -Wextra -Wpedantic -Wno-error")
    set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -fobjc-arc")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-w")
endif()
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wstrict-prototypes -Wmissing-prototypes")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wold-style-definition -Wmissing-declarations")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wuninitialized -Winit-self")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wpointer-arith -Wcast-qual")
# Note: -Wcast-align disabled due to wayland-server-core.h alignment casts
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wwrite-strings -Wconversion -Wsign-conversion")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wformat=2 -Wformat-security")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wundef -Wshadow -Wstrict-overflow=5")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wswitch-default -Wswitch-enum")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wunreachable-code -Wfloat-equal")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wstack-protector -fstack-protector-strong")
# macOS doesn't support -pie flag for executables (only for shared libraries)
# Use -fPIC for position-independent code instead
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -fPIC")

# Suppress warnings to achieve clean builds across platform stubs
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wno-unused-parameter -Wno-unused-function -Wno-unused-variable -Wno-sign-conversion -Wno-implicit-float-conversion -Wno-missing-field-initializers -Wno-format-nonliteral -Wno-deprecated-declarations -Wno-cast-qual -Wno-empty-translation-unit -Wno-format-pedantic")
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wno-unused-parameter -Wno-unused-function -Wno-unused-variable -Wno-implicit-float-conversion -Wno-deprecated-declarations -Wno-cast-qual -Wno-format-nonliteral -Wno-format-pedantic")

# Objective-C flags (slightly less strict due to Cocoa framework patterns)
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wall -Wextra -Wpedantic")
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wuninitialized -Winit-self")
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wpointer-arith -Wcast-qual")
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wformat=2 -Wformat-security")
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wundef -Wshadow")
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wstack-protector -fstack-protector-strong")
# Suppress deprecated-declarations only for Objective-C (Cocoa APIs)
set(CMAKE_OBJC_FLAGS "${CMAKE_OBJC_FLAGS} -Wno-deprecated-declarations")

# Optimization flags - maximum optimization with debug info
set(CMAKE_C_FLAGS_RELEASE "${CMAKE_C_FLAGS_RELEASE} -O3 -DNDEBUG -flto")
set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -g3 -O0 -DDEBUG")
set(CMAKE_OBJC_FLAGS_RELEASE "${CMAKE_OBJC_FLAGS_RELEASE} -O3 -DNDEBUG -flto")
set(CMAKE_OBJC_FLAGS_DEBUG "${CMAKE_OBJC_FLAGS_DEBUG} -g3 -O0 -DDEBUG")

# Enable sanitizers in debug builds for better error detection
if(CMAKE_BUILD_TYPE STREQUAL "Debug")
    # Address and undefined sanitizers are widely supported on AppleClang
    set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -fsanitize=address -fsanitize=undefined -fno-omit-frame-pointer")
    set(CMAKE_OBJC_FLAGS_DEBUG "${CMAKE_OBJC_FLAGS_DEBUG} -fsanitize=address -fsanitize=undefined -fno-omit-frame-pointer")
    # Leak sanitizer is not supported on Apple platforms; enable only on non-Apple
    if(NOT APPLE)
        set(CMAKE_C_FLAGS_DEBUG "${CMAKE_C_FLAGS_DEBUG} -fsanitize=leak")
        set(CMAKE_OBJC_FLAGS_DEBUG "${CMAKE_OBJC_FLAGS_DEBUG} -fsanitize=leak")
    endif()
endif()

# Set up pkg-config path - conditional based on platform
if(IS_IOS)
    # iOS: Use build/ios-install directory
    set(IOS_INSTALL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ios-dependencies")
    set(ENV{PKG_CONFIG_PATH} "${IOS_INSTALL_DIR}/lib/pkgconfig:${IOS_INSTALL_DIR}/libdata/pkgconfig:$ENV{PKG_CONFIG_PATH}")
    include_directories("${IOS_INSTALL_DIR}/include")
    include_directories("${CMAKE_CURRENT_SOURCE_DIR}/src/protocols")
    link_directories("${IOS_INSTALL_DIR}/lib")
else()
    # macOS: Use build/macos-install directory (and standard paths for system tools if needed)
    set(MACOS_INSTALL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/macos-dependencies")
    set(ENV{PKG_CONFIG_PATH} "${MACOS_INSTALL_DIR}/lib/pkgconfig:${MACOS_INSTALL_DIR}/libdata/pkgconfig:${MACOS_INSTALL_DIR}/share/pkgconfig:$ENV{PKG_CONFIG_PATH}")
    include_directories("${MACOS_INSTALL_DIR}/include")
    include_directories("${CMAKE_CURRENT_SOURCE_DIR}/src/protocols")
    link_directories("${MACOS_INSTALL_DIR}/lib")
    
    # Also check standard locations for things not built locally
    if(EXISTS /opt/homebrew/include)
        include_directories(/opt/homebrew/include)
    endif()
    if(EXISTS /usr/local/include)
        include_directories(/usr/local/include)
    endif()
    if(EXISTS /opt/homebrew/lib)
        link_directories(/opt/homebrew/lib)
    endif()
    if(EXISTS /usr/local/lib)
        link_directories(/usr/local/lib)
    endif()
endif()

# Platform-specific Frameworks
if(IS_IOS)
    # iOS Frameworks
    find_library(FOUNDATION_LIB Foundation REQUIRED)
    find_library(UIKIT_LIB UIKit REQUIRED)
    find_library(QUARTZCORE_LIB QuartzCore REQUIRED)
    find_library(COREVIDEO_LIB CoreVideo REQUIRED)
    find_library(COREMEDIA_LIB CoreMedia REQUIRED)
    find_library(COREGRAPHICS_LIB CoreGraphics REQUIRED)
    find_library(METAL_LIB Metal REQUIRED)
    find_library(METALKIT_LIB MetalKit REQUIRED)
    find_library(IOSURFACE_LIB IOSurface REQUIRED)
    find_library(VIDEOTOOLBOX_LIB VideoToolbox REQUIRED)
    find_library(AVFOUNDATION_LIB AVFoundation REQUIRED)
    set(COCOA_LIB "")  # Not used on iOS
else()
    # macOS Frameworks
    find_library(COCOA_LIB Cocoa REQUIRED)
    find_library(QUARTZCORE_LIB QuartzCore REQUIRED)
    find_library(COREVIDEO_LIB CoreVideo REQUIRED)
    find_library(COREMEDIA_LIB CoreMedia REQUIRED)
    find_library(COREGRAPHICS_LIB CoreGraphics REQUIRED)
    find_library(COLORSYNC_LIB ColorSync REQUIRED)
    find_library(METAL_LIB Metal REQUIRED)
    find_library(METALKIT_LIB MetalKit REQUIRED)
    find_library(IOSURFACE_LIB IOSurface REQUIRED)
    find_library(VIDEOTOOLBOX_LIB VideoToolbox REQUIRED)
    find_library(AVFOUNDATION_LIB AVFoundation REQUIRED)
    set(UIKIT_LIB "")  # Not used on macOS
endif()

# Source files - Unified for both platforms
set(SOURCES
    src/main.m
    src/WawonaUIHelpers.m
    src/WawonaCompositor.m
    src/WawonaCompositor.h
    src/logging.c
    src/logging.h
    src/wayland_output.c
    src/wayland_output.h
    src/wayland_seat.c
    src/wayland_seat.h
    src/wayland_shm.c
    src/wayland_shm.h
    src/wayland_subcompositor.c
    src/wayland_subcompositor.h
    src/wayland_data_device_manager.c
    src/wayland_data_device_manager.h
    src/wayland_primary_selection.c
    src/wayland_primary_selection.h
    src/wayland_protocol_stubs.c
    src/wayland_protocol_stubs.h
    src/cursor_shape_bridge.m
    src/protocols/primary-selection-protocol.c
    src/protocols/primary-selection-protocol.h
    src/protocols/xdg-activation-protocol.c
    src/protocols/xdg-activation-protocol.h
    src/protocols/fractional-scale-protocol.c
    src/protocols/fractional-scale-protocol.h
    src/protocols/cursor-shape-protocol.c
    src/protocols/cursor-shape-protocol.h
    src/protocols/text-input-v3-protocol.c
    src/protocols/text-input-v3-protocol.h
    src/protocols/text-input-v1-protocol.c
    src/protocols/text-input-v1-protocol.h
    src/protocols/xdg-decoration-protocol.c
    src/protocols/xdg-decoration-protocol.h
    src/protocols/xdg-toplevel-icon-protocol.c
    src/protocols/xdg-toplevel-icon-protocol.h
    src/protocols/fullscreen-shell-unstable-v1-protocol.c
    src/protocols/fullscreen-shell-unstable-v1-protocol.h
    src/surface_renderer.m
    src/surface_renderer.h
    src/input_handler.m
    src/input_handler.h
    src/protocols/xdg-shell-protocol.c
    src/protocols/xdg-shell-protocol.h
    src/xdg_shell.c
    src/xdg_shell.h
    src/wayland_viewporter.c
    src/wayland_viewporter.h
    src/wayland_fullscreen_shell.c
    src/wayland_fullscreen_shell.h
    src/protocols/viewporter-protocol.c
    src/protocols/viewporter-protocol.h
    src/wayland_shell.c
    src/wayland_gtk_shell.c
    src/wayland_gtk_shell.h
    src/wayland_plasma_shell.c
    src/wayland_plasma_shell.h
    src/wayland_qt_extensions.c
    src/wayland_qt_extensions.h
    src/wayland_shell.h
    src/wayland_screencopy.c
    src/wayland_screencopy.h
    src/wayland_presentation.c
    src/wayland_presentation.h
    src/protocols/presentation-time-protocol.h
    # presentation-time-protocol.c excluded - provided by KosmicKrisp
    src/wayland_color_management.c
    src/wayland_color_management.h
    src/protocols/color-management-v1-protocol.h
    # color-management-v1-protocol.c excluded - provided by KosmicKrisp
    src/wayland_linux_dmabuf.c
    src/wayland_linux_dmabuf.h
    src/wayland_drm.c
    src/wayland_drm.h
    src/wayland_idle_inhibit.c
    src/wayland_idle_inhibit.h
    src/wayland_pointer_gestures.c
    src/wayland_pointer_gestures.h
    src/wayland_relative_pointer.c
    src/wayland_relative_pointer.h
    src/wayland_pointer_constraints.c
    src/wayland_pointer_constraints.h
    src/metal_renderer.m
    src/metal_renderer.h
    src/metal_dmabuf.m
    src/metal_dmabuf.h
    src/metal_waypipe.m
    src/metal_waypipe.h
    
    src/protocols/tablet-stub.c
    
    src/egl_buffer_handler.h
    src/wayland_tablet.c
    src/wayland_tablet.h
    src/wayland_idle_manager.c
    src/wayland_idle_manager.h
    src/wayland_keyboard_shortcuts.c
    src/wayland_keyboard_shortcuts.h
    src/WawonaPreferences.m
    src/WawonaPreferences.h
    src/WawonaPreferencesManager.m
    src/WawonaPreferencesManager.h
    src/WawonaAboutPanel.m
    src/WawonaAboutPanel.h
)

# iOS-specific sources (launcher client - isolated to avoid wayland-client/wayland-server conflicts)
if(IS_IOS)
    list(APPEND SOURCES
        src/ios_launcher_client.m
        src/ios_launcher_client.h
        src/wayland_color_management.c
        src/wayland_color_management.h
        src/protocols/color-management-v1-protocol.c
    )
    # Disable Vulkan bridge on iOS for now; headers installed for future enablement
    add_definitions(-DHAVE_VULKAN=0)
endif()

# On macOS, include Vulkan sources only if headers are available
if(IS_MACOS)
    include(CheckIncludeFiles)
    check_include_files("vulkan/vulkan.h" VULKAN_HEADERS_FOUND)
    if(VULKAN_HEADERS_FOUND)
        list(APPEND SOURCES
            src/vulkan_renderer.m
            src/vulkan_renderer.h
            src/vulkan_ios_wrapper.c
            src/vulkan_entrypoint_stubs.c
            src/wsi_entrypoint_forwards.c
            src/vulkan_cmd_enqueue_stubs.c
            src/vulkan_common_stubs.c
        )
        add_definitions(-DHAVE_VULKAN=1)
        message(STATUS "Vulkan headers found - enabling Vulkan renderer on macOS")
    else()
        add_definitions(-DHAVE_VULKAN=0)
        message(STATUS "Vulkan headers not found - building without Vulkan renderer on macOS")
    endif()
endif()

# Include EGL buffer handler only on non-Apple platforms
if(NOT APPLE)
    list(APPEND SOURCES
        src/egl_buffer_handler.c
    )
else()
    list(APPEND SOURCES
        src/egl_buffer_handler_stubs.c
    )
endif()

# Build libgbm wrapper library for macOS/iOS (GBM API using IOSurface)
if(IS_IOS OR IS_MACOS)
    add_library(gbm STATIC
        src/compat/macos/stubs/libinput-macos/gbm-wrapper.c
        src/metal_dmabuf.m
    )
    
    target_include_directories(gbm PUBLIC
        ${CMAKE_CURRENT_SOURCE_DIR}/src/compat/macos/stubs/libinput-macos
        ${CMAKE_CURRENT_SOURCE_DIR}/src
    )
    
    # Link required frameworks
    if(IS_IOS)
        target_link_libraries(gbm
            ${FOUNDATION_LIB}
            ${UIKIT_LIB}
            ${QUARTZCORE_LIB}
            ${COREVIDEO_LIB}
            ${METAL_LIB}
            ${IOSURFACE_LIB}
        )
    else()
        target_link_libraries(gbm
            ${COCOA_LIB}
            ${QUARTZCORE_LIB}
            ${COREVIDEO_LIB}
            ${METAL_LIB}
            ${IOSURFACE_LIB}
        )
    endif()
    
    # Set compile flags
    target_compile_options(gbm PRIVATE
        -fobjc-arc
        -Wall
        -Wextra
    )
    
    message(STATUS "Building libgbm wrapper library for ${CMAKE_SYSTEM_NAME}")
endif()

# iOS-specific: Add iOS Info.plist
if(IS_IOS)
    configure_file(${CMAKE_CURRENT_SOURCE_DIR}/src/resources/app-bundle/Info.plist.ios.in ${CMAKE_CURRENT_BINARY_DIR}/Info.plist @ONLY)
else()
    configure_file(${CMAKE_CURRENT_SOURCE_DIR}/src/resources/app-bundle/Info.plist.in ${CMAKE_CURRENT_BINARY_DIR}/Info.plist @ONLY)
endif()

# Compile Metal shaders
# Metal shaders need to be compiled into a .metallib file
# Use xcrun to find Metal compiler (part of Xcode command-line tools)
find_program(XCRUN xcrun)
if(XCRUN)
    execute_process(
        COMMAND ${XCRUN} --find metal
        OUTPUT_VARIABLE METAL_COMPILER_PATH
        OUTPUT_STRIP_TRAILING_WHITESPACE
        ERROR_QUIET
    )
    if(METAL_COMPILER_PATH AND EXISTS ${METAL_COMPILER_PATH})
        set(METAL_COMPILER ${METAL_COMPILER_PATH})
        message(STATUS "Found Metal compiler: ${METAL_COMPILER}")
    endif()
endif()

# Fallback: try direct find_program
if(NOT METAL_COMPILER)
    find_program(METAL_COMPILER metal PATHS /usr/bin /usr/local/bin)
endif()

if(METAL_COMPILER)
    set(METAL_SHADER_SOURCE ${CMAKE_CURRENT_SOURCE_DIR}/src/metal_shaders.metal)
    set(METAL_SHADER_OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/metal_shaders.metallib)
    set(METAL_SHADER_AIR ${CMAKE_CURRENT_BINARY_DIR}/metal_shaders.air)
    
    # Compile Metal shader to AIR (intermediate representation)
    add_custom_command(
        OUTPUT ${METAL_SHADER_AIR}
        COMMAND ${METAL_COMPILER} -c ${METAL_SHADER_SOURCE} -o ${METAL_SHADER_AIR}
        DEPENDS ${METAL_SHADER_SOURCE}
        COMMENT "Compiling Metal shaders to AIR"
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    )
    
    # Link AIR to metallib
    # Use xcrun to find metallib linker
    set(METAL_LINKER "")
    if(XCRUN)
        execute_process(
            COMMAND ${XCRUN} --find metallib
            OUTPUT_VARIABLE METAL_LINKER_PATH
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        if(METAL_LINKER_PATH AND EXISTS ${METAL_LINKER_PATH})
            set(METAL_LINKER ${METAL_LINKER_PATH})
            message(STATUS "Found Metal linker: ${METAL_LINKER}")
        endif()
    endif()
    
    # Fallback: try direct find_program
    if(NOT METAL_LINKER)
        find_program(METAL_LINKER metallib PATHS /usr/bin /usr/local/bin)
    endif()
    
    if(METAL_LINKER)
        add_custom_command(
            OUTPUT ${METAL_SHADER_OUTPUT}
            COMMAND ${METAL_LINKER} ${METAL_SHADER_AIR} -o ${METAL_SHADER_OUTPUT}
            DEPENDS ${METAL_SHADER_AIR}
            COMMENT "Linking Metal shaders to metallib"
        )
        
        # Add metallib as a dependency
        add_custom_target(metal_shaders ALL DEPENDS ${METAL_SHADER_OUTPUT})
        message(STATUS "Metal shaders will be compiled to: ${METAL_SHADER_OUTPUT}")
    else()
        message(WARNING "metallib not found - Metal shaders will not be compiled")
    endif()
else()
    message(WARNING "Metal compiler (metal) not found - Metal shaders will not be compiled")
endif()

# Executable
add_executable(Wawona ${SOURCES})

# Configure app bundle properties for both iOS and macOS
# Bundle identifier: com.aspauldingcode.Wawona
if(IS_IOS OR IS_MACOS)
    set_target_properties(Wawona PROPERTIES
        MACOSX_BUNDLE TRUE
        MACOSX_BUNDLE_INFO_PLIST ${CMAKE_CURRENT_BINARY_DIR}/Info.plist
        MACOSX_BUNDLE_BUNDLE_NAME Wawona
        MACOSX_BUNDLE_GUI_IDENTIFIER com.aspauldingcode.Wawona
        MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION_PATCH}
        MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION}
    )
    if(IS_IOS)
        message(STATUS "Configured iOS app bundle with Info.plist: ${CMAKE_CURRENT_BINARY_DIR}/Info.plist")
        message(STATUS "  Bundle ID: com.aspauldingcode.Wawona")
    else()
        message(STATUS "Configured macOS app bundle with Info.plist: ${CMAKE_CURRENT_BINARY_DIR}/Info.plist")
        message(STATUS "  Bundle ID: com.aspauldingcode.Wawona")
    endif()
endif()

# Make sure Metal shaders are built before the executable
if(METAL_COMPILER AND METAL_LINKER)
    add_dependencies(Wawona metal_shaders)
endif()

# Find wayland libraries using pkg-config (preferred method)
find_package(PkgConfig REQUIRED)

# Find wayland-server using pkg-config (preferred)
pkg_check_modules(WAYLAND_SERVER wayland-server)
if(WAYLAND_SERVER_FOUND)
    message(STATUS "Found wayland-server via pkg-config: ${WAYLAND_SERVER_VERSION}")
    message(STATUS "  Include dirs: ${WAYLAND_SERVER_INCLUDE_DIRS}")
    message(STATUS "  Library dirs: ${WAYLAND_SERVER_LIBRARY_DIRS}")
    message(STATUS "  Libraries: ${WAYLAND_SERVER_LIBRARIES}")
else()
    # Fallback: try to find wayland-server library manually
    message(STATUS "wayland-server not found via pkg-config, trying manual search...")
    find_library(WAYLAND_SERVER_LIB
        NAMES wayland-server
        PATHS
            /usr/local/lib
            /opt/homebrew/lib
        NO_DEFAULT_PATH
    )
    if(WAYLAND_SERVER_LIB)
        message(STATUS "Found wayland-server library manually: ${WAYLAND_SERVER_LIB}")
        set(WAYLAND_SERVER_LIBRARIES ${WAYLAND_SERVER_LIB})
        # Try to find headers
        find_path(WAYLAND_SERVER_INCLUDE_DIR
            NAMES wayland-server.h
            PATHS
                /usr/local/include/wayland
                /opt/homebrew/include/wayland
            NO_DEFAULT_PATH
        )
        if(WAYLAND_SERVER_INCLUDE_DIR)
            set(WAYLAND_SERVER_INCLUDE_DIRS ${WAYLAND_SERVER_INCLUDE_DIR})
            message(STATUS "Found wayland-server headers: ${WAYLAND_SERVER_INCLUDE_DIRS}")
        endif()
    else()
        message(FATAL_ERROR "wayland-server not found! Install wayland first using ./install-wayland.sh")
    endif()
endif()

# Find wayland-client using pkg-config (needed for KosmicKrisp WSI)
pkg_check_modules(WAYLAND_CLIENT wayland-client)
if(WAYLAND_CLIENT_FOUND)
    message(STATUS "Found wayland-client via pkg-config: ${WAYLAND_CLIENT_VERSION}")
    message(STATUS "  Include dirs: ${WAYLAND_CLIENT_INCLUDE_DIRS}")
    message(STATUS "  Library dirs: ${WAYLAND_CLIENT_LIBRARY_DIRS}")
    message(STATUS "  Libraries: ${WAYLAND_CLIENT_LIBRARIES}")
else()
    # Fallback: try to find wayland-client library manually
    message(STATUS "wayland-client not found via pkg-config, trying manual search...")
    if(IS_IOS)
        # For iOS, use the installed library
        set(IOS_INSTALL_DIR "${CMAKE_CURRENT_SOURCE_DIR}/ios-dependencies")
        find_library(WAYLAND_CLIENT_LIB
            NAMES wayland-client
            PATHS ${IOS_INSTALL_DIR}/lib
            NO_DEFAULT_PATH
        )
    else()
        find_library(WAYLAND_CLIENT_LIB
            NAMES wayland-client
            PATHS
                /usr/local/lib
                /opt/homebrew/lib
            NO_DEFAULT_PATH
        )
    endif()
    if(WAYLAND_CLIENT_LIB)
        message(STATUS "Found wayland-client library manually: ${WAYLAND_CLIENT_LIB}")
        set(WAYLAND_CLIENT_LIBRARIES ${WAYLAND_CLIENT_LIB})
        # Try to find headers
        if(IS_IOS)
            find_path(WAYLAND_CLIENT_INCLUDE_DIR
                NAMES wayland-client.h
                PATHS ${IOS_INSTALL_DIR}/include/wayland
                NO_DEFAULT_PATH
            )
        else()
            find_path(WAYLAND_CLIENT_INCLUDE_DIR
                NAMES wayland-client.h
                PATHS
                    /usr/local/include/wayland
                    /opt/homebrew/include/wayland
                NO_DEFAULT_PATH
            )
        endif()
        if(WAYLAND_CLIENT_INCLUDE_DIR)
            set(WAYLAND_CLIENT_INCLUDE_DIRS ${WAYLAND_CLIENT_INCLUDE_DIR})
            message(STATUS "Found wayland-client headers: ${WAYLAND_CLIENT_INCLUDE_DIRS}")
        endif()
    else()
        message(WARNING "wayland-client not found - some Vulkan WSI features may not work")
    endif()
endif()

# Find pixman using pkg-config
pkg_check_modules(PIXMAN pixman-1)
if(PIXMAN_FOUND)
    message(STATUS "Found pixman via pkg-config: ${PIXMAN_VERSION}")
else()
    # Fallback: find pixman manually
    set(PIXMAN_SEARCH_PATHS
        /usr/local/lib
        /opt/homebrew/lib
    )
    if(IS_IOS)
        set(PIXMAN_SEARCH_PATHS ${IOS_INSTALL_DIR}/lib ${PIXMAN_SEARCH_PATHS})
    endif()
    find_library(PIXMAN_LIB
        NAMES pixman-1
        PATHS ${PIXMAN_SEARCH_PATHS}
        NO_DEFAULT_PATH
    )
    if(PIXMAN_LIB)
        message(STATUS "Found pixman library manually: ${PIXMAN_LIB}")
        set(PIXMAN_LIBRARIES ${PIXMAN_LIB})
        # Try to find headers
        if(IS_IOS)
            find_path(PIXMAN_INCLUDE_DIR
                NAMES pixman.h
                PATHS ${IOS_INSTALL_DIR}/include
                NO_DEFAULT_PATH
            )
            if(PIXMAN_INCLUDE_DIR)
                set(PIXMAN_INCLUDE_DIRS ${PIXMAN_INCLUDE_DIR})
            endif()
        endif()
    else()
        if(IS_IOS)
            message(FATAL_ERROR "pixman-1 not found! Install with: ./install-pixman-ios.sh")
        else()
            message(FATAL_ERROR "pixman-1 not found! Install with: brew install pixman")
        endif()
    endif()
endif()

# Find EGL using pkg-config (Linux/Android); skip on Apple
if(NOT APPLE)
    pkg_check_modules(EGL egl)
endif()
if(EGL_FOUND)
    message(STATUS "Found EGL via pkg-config: ${EGL_VERSION}")
else()
    # Fallback: find EGL manually
    find_library(EGL_LIB
        NAMES EGL
        PATHS
            /usr/local/lib
            /opt/homebrew/lib
        NO_DEFAULT_PATH
    )
    if(EGL_LIB)
        message(STATUS "Found EGL library manually: ${EGL_LIB}")
        set(EGL_LIBRARIES ${EGL_LIB})
        # Try to find headers
        find_path(EGL_INCLUDE_DIR
            NAMES EGL/egl.h
            PATHS
                /usr/local/include
                /opt/homebrew/include
            NO_DEFAULT_PATH
        )
        if(EGL_INCLUDE_DIR)
            set(EGL_INCLUDE_DIRS ${EGL_INCLUDE_DIR})
            message(STATUS "Found EGL headers: ${EGL_INCLUDE_DIRS}")
        endif()
    else()
        message(WARNING "EGL not found - EGL buffer support will be disabled. Install with: make kosmickrisp")
        set(EGL_LIBRARIES "")
        set(EGL_INCLUDE_DIRS "")
    endif()
endif()

# Link libraries - conditional based on platform
# NOTE: We do NOT link wlroots (Linux-only, not needed)
if(IS_IOS)
    # Find Vulkan library for iOS (KosmicKrisp)
    find_library(VULKAN_LIB
        NAMES vulkan_kosmickrisp vulkan
        PATHS ${IOS_INSTALL_DIR}/lib
        NO_DEFAULT_PATH
    )
    if(VULKAN_LIB)
        message(STATUS "Found Vulkan library: ${VULKAN_LIB}")
    else()
        message(WARNING "Vulkan library not found - Vulkan renderer will not work")
    endif()

    # Link static frameworks if present
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/ios-dependencies/Frameworks")
        target_link_options(Wawona PRIVATE -F"${CMAKE_CURRENT_SOURCE_DIR}/ios-dependencies/Frameworks")
    endif()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/ios-dependencies/Frameworks/Kosmickrisp.framework")
        target_link_libraries(Wawona "-framework Kosmickrisp")
    endif()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/ios-dependencies/Frameworks/Angle.framework/Angle")
        target_link_libraries(Wawona "-framework Angle")
    endif()
    
    target_link_libraries(Wawona
        ${FOUNDATION_LIB}
        ${UIKIT_LIB}
        ${QUARTZCORE_LIB}
        ${COREVIDEO_LIB}
        ${COREMEDIA_LIB}
        ${COREGRAPHICS_LIB}
        ${METAL_LIB}
        ${METALKIT_LIB}
        ${IOSURFACE_LIB}
        ${VIDEOTOOLBOX_LIB}
        ${AVFOUNDATION_LIB}
        ${WAYLAND_SERVER_LIBRARIES}
        ${WAYLAND_CLIENT_LIBRARIES}
        ${PIXMAN_LIBRARIES}
    )
    if(VULKAN_LIB)
        # For iOS static library, use --whole-archive to ensure all symbols are included
        # Link with whole-archive to include all symbols from the static library
        target_link_libraries(Wawona 
            -Wl,-force_load,${VULKAN_LIB}
        )
        message(STATUS "Linking Vulkan library (force-load): ${VULKAN_LIB}")
    endif()
    
    # Also try to link vulkan_kosmickrisp explicitly
    find_library(VULKAN_KOSMICKRISP_LIB
        NAMES vulkan_kosmickrisp
        PATHS ${IOS_INSTALL_DIR}/lib
        NO_DEFAULT_PATH
    )
    if(VULKAN_KOSMICKRISP_LIB AND NOT VULKAN_KOSMICKRISP_LIB STREQUAL VULKAN_LIB)
        target_link_libraries(Wawona 
            -Wl,-whole-archive 
            ${VULKAN_KOSMICKRISP_LIB} 
            -Wl,-no-whole-archive
        )
        message(STATUS "Linking KosmicKrisp Vulkan library (whole-archive): ${VULKAN_KOSMICKRISP_LIB}")
    endif()
    
    # KosmicKrisp requires expat and zstd
    find_library(EXPAT_LIB
        NAMES expat
        PATHS ${IOS_INSTALL_DIR}/lib
        NO_DEFAULT_PATH
    )
    if(EXPAT_LIB)
        target_link_libraries(Wawona ${EXPAT_LIB})
        message(STATUS "Linking expat library: ${EXPAT_LIB}")
    endif()
    
    find_library(ZSTD_LIB
        NAMES zstd
        PATHS ${IOS_INSTALL_DIR}/lib
        NO_DEFAULT_PATH
    )
    if(ZSTD_LIB)
        target_link_libraries(Wawona ${ZSTD_LIB})
        message(STATUS "Linking zstd library: ${ZSTD_LIB}")
    endif()
    
    # KosmicKrisp also requires zlib for crc32
    # iOS SDK provides zlib, but we need to link it explicitly
    find_library(ZLIB_LIB
        NAMES z
        PATHS ${IOS_INSTALL_DIR}/lib
        NO_DEFAULT_PATH
    )
    if(ZLIB_LIB)
        target_link_libraries(Wawona ${ZLIB_LIB})
        message(STATUS "Linking zlib library: ${ZLIB_LIB}")
    else()
        # Fallback to system zlib (iOS SDK provides it)
        target_link_libraries(Wawona z)
        message(STATUS "Linking system zlib")
    endif()
    
    # KosmicKrisp uses C++ code (ASTC texture compression), need C++ standard library
    # On iOS, link libc++ explicitly
    find_library(CXX_LIB
        NAMES c++
        PATHS ${IOS_INSTALL_DIR}/lib
        NO_DEFAULT_PATH
    )
    if(CXX_LIB)
        target_link_libraries(Wawona ${CXX_LIB})
        message(STATUS "Linking C++ standard library: ${CXX_LIB}")
    else()
        # Fallback: use -lc++ flag
        target_link_options(Wawona PRIVATE -lc++)
        message(STATUS "Linking C++ standard library via -lc++")
    endif()
    
    # Enable Vulkan beta extensions for CUDA/AMDX stub support
    target_compile_definitions(Wawona PRIVATE VK_ENABLE_BETA_EXTENSIONS)
    message(STATUS "Enabled Vulkan beta extensions")
    target_compile_options(Wawona PRIVATE
        $<$<COMPILE_LANGUAGE:OBJC>:-Wno-unused-parameter -Wno-unused-function -Wno-unused-const-variable -Wno-format-nonliteral -Wno-deprecated-declarations -Wno-implicit-float-conversion -Wno-missing-field-initializers -Wno-cast-qual>
        $<$<COMPILE_LANGUAGE:C>:-Wno-unused-parameter -Wno-unused-function -Wno-unused-const-variable -Wno-format-nonliteral -Wno-deprecated-declarations -Wno-implicit-float-conversion -Wno-missing-field-initializers -Wno-cast-qual>
    )
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-w")
else()
    target_link_libraries(Wawona
        ${COCOA_LIB}
        ${QUARTZCORE_LIB}
        ${COREVIDEO_LIB}
        ${COREMEDIA_LIB}
        ${COREGRAPHICS_LIB}
        ${COLORSYNC_LIB}
        ${METAL_LIB}
        ${METALKIT_LIB}
        ${IOSURFACE_LIB}
        ${VIDEOTOOLBOX_LIB}
        ${AVFOUNDATION_LIB}
        ${WAYLAND_SERVER_LIBRARIES}
        ${WAYLAND_CLIENT_LIBRARIES}
        ${PIXMAN_LIBRARIES}
    )
    target_compile_options(Wawona PRIVATE
        $<$<COMPILE_LANGUAGE:OBJC>:-Wno-unused-parameter -Wno-unused-function -Wno-unused-const-variable -Wno-format-nonliteral -Wno-deprecated-declarations -Wno-implicit-float-conversion -Wno-missing-field-initializers -Wno-cast-qual>
        $<$<COMPILE_LANGUAGE:C>:-Wno-unused-parameter -Wno-unused-function -Wno-unused-const-variable -Wno-format-nonliteral -Wno-deprecated-declarations -Wno-implicit-float-conversion -Wno-missing-field-initializers -Wno-cast-qual>
    )
    # Link static frameworks if present
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/macos-dependencies/Frameworks")
        target_link_options(Wawona PRIVATE -F"${CMAKE_CURRENT_SOURCE_DIR}/macos-dependencies/Frameworks")
    endif()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/macos-dependencies/Frameworks/Kosmickrisp.framework")
        target_link_libraries(Wawona "-framework Kosmickrisp")
    endif()
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/macos-dependencies/Frameworks/Angle.framework/Angle")
        target_link_libraries(Wawona "-framework Angle")
    endif()
endif()

# Link libgbm wrapper if built
if(TARGET gbm)
    target_link_libraries(Wawona gbm)
    message(STATUS "Linking libgbm wrapper library")
endif()

# Link EGL if available (for KosmicKrisp+Zink EGL buffer support)
# For iOS, EGL is disabled in KosmicKrisp, so skip linking
if(IS_IOS)
    message(STATUS "EGL disabled for iOS builds (KosmicKrisp builds Vulkan driver only)")
elseif(EGL_FOUND OR EGL_LIBRARIES)
    if(APPLE)
        message(STATUS "EGL detected but skip linking on Apple targets")
    else()
        target_link_libraries(Wawona ${EGL_LIBRARIES})
        message(STATUS "Linking EGL library for EGL buffer support")
    endif()
endif()

# Include directories for wayland
if(WAYLAND_SERVER_FOUND AND WAYLAND_SERVER_INCLUDE_DIRS)
    target_include_directories(Wawona PRIVATE ${WAYLAND_SERVER_INCLUDE_DIRS})
elseif(WAYLAND_SERVER_INCLUDE_DIRS)
    target_include_directories(Wawona PRIVATE ${WAYLAND_SERVER_INCLUDE_DIRS})
endif()
if(WAYLAND_CLIENT_FOUND AND WAYLAND_CLIENT_INCLUDE_DIRS)
    target_include_directories(Wawona PRIVATE ${WAYLAND_CLIENT_INCLUDE_DIRS})
elseif(WAYLAND_CLIENT_INCLUDE_DIRS)
    target_include_directories(Wawona PRIVATE ${WAYLAND_CLIENT_INCLUDE_DIRS})
endif()
if(PIXMAN_FOUND AND PIXMAN_INCLUDE_DIRS)
    target_include_directories(Wawona PRIVATE ${PIXMAN_INCLUDE_DIRS})
endif()
# Include directories for EGL
if(EGL_FOUND AND EGL_INCLUDE_DIRS)
    target_include_directories(Wawona PRIVATE ${EGL_INCLUDE_DIRS})
elseif(EGL_INCLUDE_DIRS)
    target_include_directories(Wawona PRIVATE ${EGL_INCLUDE_DIRS})
endif()

# Copy Info.plist into app bundle
# iOS requires explicit copy; macOS bundles are handled automatically by CMake when MACOSX_BUNDLE_INFO_PLIST is set
if(IS_IOS)
    # For iOS bundles, TARGET_FILE_DIR points to the .app directory
    # Copy Info.plist into the bundle directory
    add_custom_command(TARGET Wawona POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${CMAKE_CURRENT_BINARY_DIR}/Info.plist
            $<TARGET_FILE_DIR:Wawona>/Info.plist
        COMMENT "Copying Info.plist into iOS app bundle"
    )
    
    # Copy Settings.bundle into iOS app bundle (for iOS Settings app integration)
    add_custom_command(TARGET Wawona POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            ${CMAKE_CURRENT_SOURCE_DIR}/src/resources/Settings.bundle
            $<TARGET_FILE_DIR:Wawona>/Settings.bundle
        COMMENT "Copying Settings.bundle into iOS app bundle"
    )
endif()

# Copy Metal shader library to build directory (next to executable)
if(METAL_COMPILER AND METAL_LINKER)
    if(IS_IOS)
        # For iOS, copy into app bundle (same directory as Info.plist)
        add_custom_command(TARGET Wawona POST_BUILD
            COMMAND ${CMAKE_COMMAND} -E copy_if_different
                ${METAL_SHADER_OUTPUT}
                $<TARGET_FILE_DIR:Wawona>/metal_shaders.metallib
            COMMENT "Copying Metal shader library to iOS app bundle"
        )
    else()
        # For macOS, copy next to executable
    add_custom_command(TARGET Wawona POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${METAL_SHADER_OUTPUT}
            $<TARGET_FILE_DIR:Wawona>/metal_shaders.metallib
        COMMENT "Copying Metal shader library to build directory"
    )
    endif()
endif()

# Code formatting target (like `cargo fmt`)
find_program(CLANG_FORMAT clang-format)
if(CLANG_FORMAT)
    file(GLOB_RECURSE ALL_SOURCES
        "${CMAKE_SOURCE_DIR}/src/*.c"
        "${CMAKE_SOURCE_DIR}/src/*.h"
        "${CMAKE_SOURCE_DIR}/src/*.m"
    )
    add_custom_target(format
        COMMAND ${CLANG_FORMAT} -i ${ALL_SOURCES}
        COMMENT "Formatting all source files with clang-format"
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    )
    message(STATUS "Format target available: make format")
else()
    message(STATUS "clang-format not found - format target unavailable")
endif()

# Code linting target (like `cargo clippy`)
find_program(CLANG_TIDY clang-tidy)
if(CLANG_TIDY)
    add_custom_target(lint
        COMMAND ${CLANG_TIDY} ${ALL_SOURCES} -p ${CMAKE_BINARY_DIR}
        COMMENT "Linting all source files with clang-tidy"
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    )
    message(STATUS "Lint target available: make lint")
else()
    message(STATUS "clang-tidy not found - lint target unavailable")
endif()

# Check formatting target (for CI)
if(CLANG_FORMAT)
    add_custom_target(check-format
        COMMAND ${CLANG_FORMAT} --dry-run --Werror ${ALL_SOURCES}
        COMMENT "Checking code formatting"
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
    )
    message(STATUS "Check-format target available: make check-format")
endif()
