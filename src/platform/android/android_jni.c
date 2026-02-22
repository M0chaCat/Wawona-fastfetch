/**
 * Android JNI Bridge for Wawona Wayland Compositor
 *
 * This file provides the Java Native Interface (JNI) bridge between the Android
 * application layer and the Wawona compositor. It handles Vulkan surface
 * creation, safe area detection, and iOS settings compatibility.
 *
 * Features:
 * - Vulkan rendering with hardware acceleration
 * - Android WindowInsets integration for safe area support
 * - iOS settings 1:1 mapping
 * - Thread-safe initialization and cleanup
 */

#include "WWNSettings.h"
#include "input_android.h"
#include "renderer_android.h"
#include <android/choreographer.h>
#include <android/log.h>
#include <android/looper.h>
#include <android/native_window_jni.h>
#include <jni.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vulkan/vulkan.h>
#include <vulkan/vulkan_android.h>

#include <stdarg.h>
#include <time.h>

static void wwn_log(int prio, const char *tag, const char *fmt, ...)
    __attribute__((format(printf, 3, 4)));
static void wwn_log(int prio, const char *tag, const char *fmt, ...) {
  char msg[1024];
  char timebuf[32];
  time_t now = time(NULL);
  struct tm *tm = localtime(&now);
  strftime(timebuf, sizeof(timebuf), "%Y-%m-%d %H:%M:%S", tm);
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(msg, sizeof(msg), fmt, ap);
  va_end(ap);
  __android_log_print(prio, "Wawona", "%s [%s] %s", timebuf, tag, msg);
}

#define LOGI(...) wwn_log(ANDROID_LOG_INFO, "JNI", __VA_ARGS__)
#define LOGE(...) wwn_log(ANDROID_LOG_ERROR, "JNI", __VA_ARGS__)

// ============================================================================
// Forward declarations for Rust backend FFI (from c_api.rs / libwawona.a)
// ============================================================================
extern void *WWNCoreNew(void);
extern int WWNCoreStart(void *core, const char *socket_name);
extern int WWNCoreStop(void *core);
extern int WWNCoreIsRunning(const void *core);
extern int WWNCoreProcessEvents(void *core);
extern void WWNCoreSetOutputSize(void *core, uint32_t width, uint32_t height,
                                 float scale);
extern void WWNCoreSetSafeAreaInsets(void *core, int32_t top, int32_t right,
                                     int32_t bottom, int32_t left);
extern void WWNCoreSetForceSSD(void *core, int enabled);
extern void WWNCoreFree(void *core);

typedef struct {
  CRenderNode *nodes;
  size_t count;
  size_t capacity;
  int has_cursor;
  float cursor_x, cursor_y;
  float cursor_hotspot_x, cursor_hotspot_y;
  uint64_t cursor_buffer_id;
  uint32_t cursor_width, cursor_height, cursor_stride, cursor_format;
  uint32_t cursor_iosurface_id;
} CRenderScene;

extern CRenderScene *WWNCoreGetRenderScene(void *core);
extern void WWNRenderSceneFree(CRenderScene *scene);

typedef struct {
  uint64_t window_id;
  uint32_t surface_id;
  uint64_t buffer_id;
  uint32_t width, height, stride, format;
  uint8_t *pixels;
  size_t size;
  size_t capacity;
  uint32_t iosurface_id;
} CBufferData;

extern CBufferData *WWNCorePopPendingBuffer(void *core);
extern void WWNBufferDataFree(CBufferData *data);
extern void WWNCoreNotifyFramePresented(void *core, uint32_t surface_id,
                                        uint64_t buffer_id, uint32_t timestamp);

/* Window events - drain and apply title to UI */
enum {
  CWindowEventTypeCreated = 0,
  CWindowEventTypeTitleChanged = 2,
};
typedef struct {
  uint64_t event_type;
  uint64_t window_id;
  uint32_t surface_id;
  char *title; /* FFI: *mut c_char */
  uint32_t width, height;
  uint64_t parent_id;
  int32_t x, y;
  uint8_t decoration_mode;
  uint8_t fullscreen_shell;
  uint16_t padding;
} CWindowEvent;
extern CWindowEvent *WWNCorePopWindowEvent(void *core);
extern void WWNWindowEventFree(CWindowEvent *event);

/* Screencopy (zwlr_screencopy_manager_v1) - platform writes ARGB8888 to ptr */
typedef struct {
  uint64_t capture_id;
  void *ptr;
  uint32_t width;
  uint32_t height;
  uint32_t stride;
  size_t size;
} CScreencopyRequest;
extern CScreencopyRequest WWNCoreGetPendingScreencopy(void *core);
extern void WWNCoreScreencopyDone(void *core, uint64_t capture_id);
extern void WWNCoreScreencopyFailed(void *core, uint64_t capture_id);
extern CScreencopyRequest WWNCoreGetPendingImageCopyCapture(void *core);
extern void WWNCoreImageCopyCaptureDone(void *core, uint64_t capture_id);
extern void WWNCoreImageCopyCaptureFailed(void *core, uint64_t capture_id);

extern void WWNCoreInjectTouchDown(void *core, int32_t id, double x, double y,
                                   uint32_t timestamp_ms);
extern void WWNCoreInjectTouchUp(void *core, int32_t id, uint32_t timestamp_ms);
extern void WWNCoreInjectTouchMotion(void *core, int32_t id, double x, double y,
                                     uint32_t timestamp_ms);
extern void WWNCoreInjectTouchCancel(void *core);
extern void WWNCoreInject_touch_frame(void *core);
extern void WWNCoreInjectKey(void *core, uint32_t keycode, uint32_t state,
                             uint32_t timestamp_ms);
extern void WWNCoreInjectModifiers(void *core, uint32_t depressed,
                                   uint32_t latched, uint32_t locked,
                                   uint32_t group);
extern void WWNCoreInjectPointerMotion(void *core, uint64_t window_id, double x,
                                       double y, uint32_t timestamp_ms);
extern void WWNCoreInjectPointerButton(void *core, uint64_t window_id,
                                       uint32_t button_code, uint32_t state,
                                       uint32_t timestamp_ms);
extern void WWNCoreInjectPointerEnter(void *core, uint64_t window_id, double x,
                                      double y, uint32_t timestamp_ms);
extern void WWNCoreInjectPointerLeave(void *core, uint64_t window_id,
                                      uint32_t timestamp_ms);
extern void WWNCoreInjectPointerAxis(void *core, uint64_t window_id,
                                     uint32_t axis, double value,
                                     uint32_t timestamp_ms);
extern void WWNCoreInjectKeyboardEnter(void *core, uint64_t window_id,
                                       const uint32_t *keys, size_t count,
                                       uint32_t timestamp_ms);
extern void WWNCoreInjectKeyboardLeave(void *core, uint64_t window_id);

extern void WWNCoreTextInputCommit(void *core, const char *text);
extern void WWNCoreTextInputPreedit(void *core, const char *text,
                                    int32_t cursor_begin, int32_t cursor_end);
extern void WWNCoreTextInputDeleteSurrounding(void *core, uint32_t before,
                                              uint32_t after);
extern void WWNCoreTextInputGetCursorRect(void *core, int32_t *out_x,
                                          int32_t *out_y, int32_t *out_width,
                                          int32_t *out_height);

extern int waypipe_main(int argc, const char **argv);
extern int weston_simple_shm_main(int argc, const char **argv);

// JNI Function Prototypes
JNIEXPORT void JNICALL Java_com_aspauldingcode_wawona_WawonaNative_nativeInit(
    JNIEnv *env, jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetSurface(JNIEnv *env,
                                                             jobject thiz,
                                                             jobject surface);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeDestroySurface(JNIEnv *env,
                                                                 jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeUpdateSafeArea(
    JNIEnv *env, jobject thiz, jint left, jint top, jint right, jint bottom);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeApplySettings(
    JNIEnv *env, jobject thiz, jboolean forceServerSideDecorations,
    jboolean autoRetinaScaling, jint renderingBackend, jboolean respectSafeArea,
    jboolean renderMacOSPointer, jboolean swapCmdAsCtrl,
    jboolean universalClipboard, jboolean colorSyncSupport,
    jboolean nestedCompositorsSupport, jboolean useMetal4ForNested,
    jboolean multipleClients, jboolean waypipeRSSupport,
    jboolean enableTCPListener, jint tcpPort, jstring vulkanDriver,
    jstring openglDriver);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetCore(JNIEnv *env,
                                                          jobject thiz,
                                                          jlong corePtr);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeCommitText(JNIEnv *env,
                                                             jobject thiz,
                                                             jstring text);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePreeditText(
    JNIEnv *env, jobject thiz, jstring text, jint cursorBegin, jint cursorEnd);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeDeleteSurroundingText(
    JNIEnv *env, jobject thiz, jint beforeLength, jint afterLength);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetCursorRect(
    JNIEnv *env, jobject thiz, jintArray outRect);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWaypipe(
    JNIEnv *env, jobject thiz, jboolean sshEnabled, jstring sshHost,
    jstring sshUser, jstring sshPassword, jstring remoteCommand,
    jstring compress, jint threads, jstring video, jboolean debug,
    jboolean oneshot, jboolean noGpu, jboolean loginShell, jstring titlePrefix,
    jstring secCtx);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWaypipe(JNIEnv *env,
                                                              jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWaypipeRunning(
    JNIEnv *env, jobject thiz);

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWestonSimpleSHM(
    JNIEnv *env, jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWestonSimpleSHM(
    JNIEnv *env, jobject thiz);
JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWestonSimpleSHMRunning(
    JNIEnv *env, jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchDown(
    JNIEnv *env, jobject thiz, jint id, jfloat x, jfloat y, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchUp(JNIEnv *env,
                                                          jobject thiz, jint id,
                                                          jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchMotion(
    JNIEnv *env, jobject thiz, jint id, jfloat x, jfloat y, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchCancel(JNIEnv *env,
                                                              jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchFrame(JNIEnv *env,
                                                             jobject thiz);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeKeyEvent(
    JNIEnv *env, jobject thiz, jint keycode, jint state, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerAxis(
    JNIEnv *env, jobject thiz, jint axis, jfloat value, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerMotion(
    JNIEnv *env, jobject thiz, jdouble x, jdouble y, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerButton(
    JNIEnv *env, jobject thiz, jint buttonCode, jint state, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerEnter(
    JNIEnv *env, jobject thiz, jdouble x, jdouble y, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerLeave(
    JNIEnv *env, jobject thiz, jint timestampMs);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeKeyboardFocus(
    JNIEnv *env, jobject thiz, jboolean hasFocus);
JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetFocusedWindowTitle(
    JNIEnv *env, jobject thiz);
JNIEXPORT jlong JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetPendingScreencopy(
    JNIEnv *env, jobject thiz, jintArray outWidthHeight);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeScreencopyComplete(
    JNIEnv *env, jobject thiz, jlong captureId, jbyteArray pixels);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeScreencopyFailed(
    JNIEnv *env, jobject thiz, jlong captureId);
JNIEXPORT jlong JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetPendingImageCopyCapture(
    JNIEnv *env, jobject thiz, jintArray outWidthHeight);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeImageCopyCaptureComplete(
    JNIEnv *env, jobject thiz, jlong captureId, jbyteArray pixels);
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeImageCopyCaptureFailed(
    JNIEnv *env, jobject thiz, jlong captureId);

// ============================================================================
// Global State
// ============================================================================

// Vulkan resources
VkInstance g_instance = VK_NULL_HANDLE;
VkPhysicalDevice g_physicalDevice = VK_NULL_HANDLE;
VkSurfaceKHR g_surface = VK_NULL_HANDLE;
VkDevice g_device = VK_NULL_HANDLE;
VkQueue g_queue = VK_NULL_HANDLE;
VkSwapchainKHR g_swapchain = VK_NULL_HANDLE;
uint32_t g_queue_family = 0;
ANativeWindow *g_window = NULL;

// Threading
static int g_running = 0;
static pthread_t g_render_thread = 0;
static pthread_mutex_t g_lock = PTHREAD_MUTEX_INITIALIZER;

// Window title from drained CWindowEvent (TitleChanged) - for ActionBar/status
// display
#define WINDOW_TITLE_MAX 256
static char g_window_title[WINDOW_TITLE_MAX];
static pthread_mutex_t g_title_lock = PTHREAD_MUTEX_INITIALIZER;

// Pending screencopy - ptr stored for nativeScreencopyComplete (must run on
// same thread as GetPending)
static void *g_screencopy_ptr = NULL;
static uint32_t g_screencopy_stride = 0;
static size_t g_screencopy_size = 0;

// Safe area support (for display cutouts, notches, etc.)
static int g_safeAreaLeft = 0;
static int g_safeAreaTop = 0;
static int g_safeAreaRight = 0;
static int g_safeAreaBottom = 0;

// Raw safe area values from Android (independent of setting)
static int g_rawSafeAreaLeft = 0;
static int g_rawSafeAreaTop = 0;
static int g_rawSafeAreaRight = 0;
static int g_rawSafeAreaBottom = 0;

// Compositor core pointer (set when Rust core is initialised)
static void *g_core = NULL;

/* Modifier state for InjectModifiers (XKB modifier mask) */
#define XKB_MOD_SHIFT (1 << 0)
#define XKB_MOD_CAPS (1 << 1)
#define XKB_MOD_CTRL (1 << 2)
#define XKB_MOD_ALT (1 << 3)
#define XKB_MOD_NUM (1 << 4)
#define XKB_MOD_LOGO (1 << 5) /* Super/Meta */
static uint32_t g_modifiers_depressed = 0;

/* Single full-screen window id for pointer enter/leave/axis (Android has no
 * multi-window UI) */
static uint64_t g_pointer_window_id = 1;

/* Active touch count - for pointer enter/leave (inject enter on 0->1, leave on
 * 1->0) */
static int g_active_touches = 0;

// iOS Settings 1:1 mapping (for compatibility with iOS version)
// Now managed by WawonaSettings.c via WWNSettings_UpdateConfig

// ============================================================================
// Safe Area Detection
// ============================================================================

/**
 * Update safe area insets from Android WindowInsets API
 * Handles display cutouts (notches, punch holes) and system gesture insets
 */
static void update_safe_area(JNIEnv *env, jobject activity) {
  LOGI("update_safe_area called");
  if (!activity) {
    LOGE("update_safe_area: activity is NULL");
    g_safeAreaLeft = 0;
    g_safeAreaTop = 0;
    g_safeAreaRight = 0;
    g_safeAreaBottom = 0;
    return;
  }
  if (!WWNSettings_GetRespectSafeArea()) {
    LOGI("Safe area respect disabled, setting to 0");
    g_safeAreaLeft = 0;
    g_safeAreaTop = 0;
    g_safeAreaRight = 0;
    g_safeAreaBottom = 0;
    return;
  }
  LOGI("Updating safe area from WindowInsets...");

  // Get WindowInsets
  jclass activityClass = (*env)->GetObjectClass(env, activity);
  jmethodID getWindowMethod = (*env)->GetMethodID(
      env, activityClass, "getWindow", "()Landroid/view/Window;");
  jobject window = (*env)->CallObjectMethod(env, activity, getWindowMethod);

  if (window) {
    jclass windowClass = (*env)->GetObjectClass(env, window);
    jmethodID getDecorViewMethod = (*env)->GetMethodID(
        env, windowClass, "getDecorView", "()Landroid/view/View;");
    jobject decorView =
        (*env)->CallObjectMethod(env, window, getDecorViewMethod);

    if (decorView) {
      // Get root window insets
      jclass viewClass = (*env)->GetObjectClass(env, decorView);
      jmethodID getRootWindowInsetsMethod =
          (*env)->GetMethodID(env, viewClass, "getRootWindowInsets",
                              "()Landroid/view/WindowInsets;");
      jobject windowInsets =
          (*env)->CallObjectMethod(env, decorView, getRootWindowInsetsMethod);

      if (windowInsets) {
        // Get display cutout for notch/punch hole
        jclass windowInsetsClass = (*env)->GetObjectClass(env, windowInsets);
        jmethodID getDisplayCutoutMethod =
            (*env)->GetMethodID(env, windowInsetsClass, "getDisplayCutout",
                                "()Landroid/view/DisplayCutout;");
        jobject displayCutout =
            (*env)->CallObjectMethod(env, windowInsets, getDisplayCutoutMethod);

        if (displayCutout) {
          jclass displayCutoutClass =
              (*env)->GetObjectClass(env, displayCutout);

          // Get safe insets
          jmethodID getSafeInsetLeftMethod = (*env)->GetMethodID(
              env, displayCutoutClass, "getSafeInsetLeft", "()I");
          jmethodID getSafeInsetTopMethod = (*env)->GetMethodID(
              env, displayCutoutClass, "getSafeInsetTop", "()I");
          jmethodID getSafeInsetRightMethod = (*env)->GetMethodID(
              env, displayCutoutClass, "getSafeInsetRight", "()I");
          jmethodID getSafeInsetBottomMethod = (*env)->GetMethodID(
              env, displayCutoutClass, "getSafeInsetBottom", "()I");

          g_safeAreaLeft =
              (*env)->CallIntMethod(env, displayCutout, getSafeInsetLeftMethod);
          g_safeAreaTop =
              (*env)->CallIntMethod(env, displayCutout, getSafeInsetTopMethod);
          g_safeAreaRight = (*env)->CallIntMethod(env, displayCutout,
                                                  getSafeInsetRightMethod);
          g_safeAreaBottom = (*env)->CallIntMethod(env, displayCutout,
                                                   getSafeInsetBottomMethod);

          LOGI("Safe area updated: left=%d, top=%d, right=%d, bottom=%d",
               g_safeAreaLeft, g_safeAreaTop, g_safeAreaRight,
               g_safeAreaBottom);

          (*env)->DeleteLocalRef(env, displayCutout);
        } else {
          // Fallback to system gesture insets for navigation bar
          jmethodID getSystemGestureInsetsMethod = (*env)->GetMethodID(
              env, windowInsetsClass, "getSystemGestureInsets",
              "()Landroid/graphics/Insets;");
          jobject systemGestureInsets = (*env)->CallObjectMethod(
              env, windowInsets, getSystemGestureInsetsMethod);

          if (systemGestureInsets) {
            jclass insetsClass =
                (*env)->GetObjectClass(env, systemGestureInsets);
            jfieldID leftField =
                (*env)->GetFieldID(env, insetsClass, "left", "I");
            jfieldID topField =
                (*env)->GetFieldID(env, insetsClass, "top", "I");
            jfieldID rightField =
                (*env)->GetFieldID(env, insetsClass, "right", "I");
            jfieldID bottomField =
                (*env)->GetFieldID(env, insetsClass, "bottom", "I");

            g_safeAreaLeft =
                (*env)->GetIntField(env, systemGestureInsets, leftField);
            g_safeAreaTop =
                (*env)->GetIntField(env, systemGestureInsets, topField);
            g_safeAreaRight =
                (*env)->GetIntField(env, systemGestureInsets, rightField);
            g_safeAreaBottom =
                (*env)->GetIntField(env, systemGestureInsets, bottomField);

            LOGI("System gesture insets: left=%d, top=%d, right=%d, bottom=%d",
                 g_safeAreaLeft, g_safeAreaTop, g_safeAreaRight,
                 g_safeAreaBottom);

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

// ============================================================================
// Vulkan Initialization
// ============================================================================

/**
 * Create Vulkan instance with Android surface extensions
 */
static VkResult create_instance(void) {
  const char *vulkanDriver = WWNSettings_GetVulkanDriver();

  // If Waypipe support is enabled, force SwiftShader for compatibility
  if (WWNSettings_GetWaypipeRSSupportEnabled()) {
    LOGI("Waypipe support enabled: Forcing SwiftShader ICD");
    setenv("VK_ICD_FILENAMES", "/system/etc/vulkan/icd.d/swiftshader_icd.json",
           1);
  } else if (strcmp(vulkanDriver, "none") == 0) {
    // Vulkan disabled - use SwiftShader as safe fallback so compositor can
    // still run
    LOGI("Vulkan driver 'none' selected: Using SwiftShader fallback");
    setenv("VK_ICD_FILENAMES", "/system/etc/vulkan/icd.d/swiftshader_icd.json",
           1);
  } else if (strcmp(vulkanDriver, "swiftshader") == 0) {
    LOGI("Vulkan driver 'swiftshader' selected");
    setenv("VK_ICD_FILENAMES", "/system/etc/vulkan/icd.d/swiftshader_icd.json",
           1);
  } else if (strcmp(vulkanDriver, "turnip") == 0) {
    LOGI("Vulkan driver 'turnip' (freedreno) selected");
    setenv("VK_ICD_FILENAMES", "/data/local/tmp/freedreno_icd.json", 1);
  } else {
    // "system" or unknown - use system default (unset or platform default)
    LOGI("Vulkan driver 'system' selected: Using platform default");
    unsetenv("VK_ICD_FILENAMES");
  }

  const char *exts[] = {VK_KHR_SURFACE_EXTENSION_NAME,
                        VK_KHR_ANDROID_SURFACE_EXTENSION_NAME};
  VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO};
  app.pApplicationName = "Wawona";
  app.applicationVersion = VK_MAKE_VERSION(0, 0, 1);
  app.pEngineName = "Wawona";
  app.engineVersion = VK_MAKE_VERSION(0, 0, 1);
  app.apiVersion = VK_API_VERSION_1_0;

  VkInstanceCreateInfo ci = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
  ci.pApplicationInfo = &app;
  ci.enabledExtensionCount = (uint32_t)(sizeof(exts) / sizeof(exts[0]));
  ci.ppEnabledExtensionNames = exts;

  VkResult res = vkCreateInstance(&ci, NULL, &g_instance);
  if (res != VK_SUCCESS) {
    LOGE("vkCreateInstance failed: %d", res);
    // Try SwiftShader fallback
    setenv("VK_ICD_FILENAMES", "/system/etc/vulkan/icd.d/swiftshader_icd.json",
           1);
    res = vkCreateInstance(&ci, NULL, &g_instance);
  }
  if (res != VK_SUCCESS)
    LOGE("vkCreateInstance failed: %d", res);
  return res;
}

/**
 * Pick the first available Vulkan physical device
 */
static VkPhysicalDevice pick_device(void) {
  uint32_t count = 0;
  VkResult res = vkEnumeratePhysicalDevices(g_instance, &count, NULL);
  if (res != VK_SUCCESS || count == 0) {
    LOGE("vkEnumeratePhysicalDevices failed: %d, count=%u", res, count);
    return VK_NULL_HANDLE;
  }
  VkPhysicalDevice devs[4];
  if (count > 4)
    count = 4;
  res = vkEnumeratePhysicalDevices(g_instance, &count, devs);
  if (res != VK_SUCCESS) {
    LOGE("vkEnumeratePhysicalDevices failed: %d", res);
    return VK_NULL_HANDLE;
  }
  LOGI("Found %u Vulkan devices", count);

  // Print device names
  for (uint32_t i = 0; i < count; i++) {
    VkPhysicalDeviceProperties props;
    vkGetPhysicalDeviceProperties(devs[i], &props);
    LOGI("Device %u: %s (Type: %d, API: %u.%u.%u)", i, props.deviceName,
         props.deviceType, VK_VERSION_MAJOR(props.apiVersion),
         VK_VERSION_MINOR(props.apiVersion),
         VK_VERSION_PATCH(props.apiVersion));
  }

  g_physicalDevice = devs[0];
  return devs[0];
}

/**
 * Find a queue family that supports graphics and surface presentation
 */
static int pick_queue_family(VkPhysicalDevice pd) {
  uint32_t count = 0;
  vkGetPhysicalDeviceQueueFamilyProperties(pd, &count, NULL);
  if (count == 0)
    return -1;

  VkQueueFamilyProperties props[8];
  if (count > 8)
    count = 8;
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

/**
 * Check if an extension is available in the list
 */
static int is_extension_available(const char *name,
                                  VkExtensionProperties *props,
                                  uint32_t count) {
  for (uint32_t i = 0; i < count; i++) {
    if (strcmp(name, props[i].extensionName) == 0) {
      return 1;
    }
  }
  return 0;
}

/**
 * Create Vulkan logical device with swapchain extension
 */
static int create_device(VkPhysicalDevice pd) {
  int q = pick_queue_family(pd);
  if (q < 0)
    return -1;
  g_queue_family = (uint32_t)q;

  float prio = 1.0f;
  VkDeviceQueueCreateInfo qci = {
      .sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
  qci.queueFamilyIndex = g_queue_family;
  qci.queueCount = 1;
  qci.pQueuePriorities = &prio;

  // Check available extensions
  uint32_t extCount = 0;
  vkEnumerateDeviceExtensionProperties(pd, NULL, &extCount, NULL);
  VkExtensionProperties *availableExts =
      malloc(sizeof(VkExtensionProperties) * extCount);
  if (availableExts) {
    vkEnumerateDeviceExtensionProperties(pd, NULL, &extCount, availableExts);
  }

  // List of desired extensions
  const char *desired_exts[] = {
      VK_KHR_SWAPCHAIN_EXTENSION_NAME, VK_KHR_EXTERNAL_MEMORY_EXTENSION_NAME,
      VK_KHR_EXTERNAL_MEMORY_FD_EXTENSION_NAME,
      "VK_EXT_external_memory_dma_buf", // Explicit string if header missing
      "VK_ANDROID_external_memory_android_hardware_buffer"};
  uint32_t desiredCount = sizeof(desired_exts) / sizeof(desired_exts[0]);

  // Filter enabled extensions
  const char *enabled_exts[16];
  uint32_t enabledCount = 0;

  for (uint32_t i = 0; i < desiredCount; i++) {
    if (availableExts &&
        is_extension_available(desired_exts[i], availableExts, extCount)) {
      enabled_exts[enabledCount++] = desired_exts[i];
      LOGI("Enabling extension: %s", desired_exts[i]);
    } else {
      LOGI("Extension not available (skipping): %s", desired_exts[i]);
    }
  }

  if (availableExts)
    free(availableExts);

  VkDeviceCreateInfo dci = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
  dci.queueCreateInfoCount = 1;
  dci.pQueueCreateInfos = &qci;
  dci.enabledExtensionCount = enabledCount;
  dci.ppEnabledExtensionNames = enabled_exts;

  if (vkCreateDevice(pd, &dci, NULL, &g_device) != VK_SUCCESS) {
    LOGE("vkCreateDevice failed");
    return -1;
  }
  vkGetDeviceQueue(g_device, g_queue_family, 0, &g_queue);
  LOGI("Device created successfully");
  return 0;
}

/**
 * Create swapchain for surface presentation
 */
static int create_swapchain(VkPhysicalDevice pd) {
  VkSurfaceCapabilitiesKHR caps;
  VkResult res =
      vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pd, g_surface, &caps);
  if (res != VK_SUCCESS) {
    LOGE("vkGetPhysicalDeviceSurfaceCapabilitiesKHR failed: %d", res);
    return -1;
  }

  VkExtent2D ext = caps.currentExtent;
  if (ext.width == 0 || ext.height == 0)
    ext = (VkExtent2D){640, 480};
  LOGI("Swapchain extent: %ux%u", ext.width, ext.height);

  VkSwapchainCreateInfoKHR sci = {
      .sType = VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
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

// ============================================================================
// Rendering
// ============================================================================

static VkImageView *g_imageViews = NULL;
static VkFramebuffer *g_framebuffers = NULL;
static VkRenderPass g_renderPass = VK_NULL_HANDLE;
static uint32_t g_swapchainImageCount = 0;

/**
 * Create Image Views
 */
static int create_image_views(uint32_t imageCount, VkImage *images) {
  if (g_imageViews)
    free(g_imageViews);
  g_imageViews = malloc(imageCount * sizeof(VkImageView));
  g_swapchainImageCount = imageCount;
  for (uint32_t i = 0; i < imageCount; i++) {
    VkImageViewCreateInfo ivci = {.sType =
                                      VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    ivci.image = images[i];
    ivci.viewType = VK_IMAGE_VIEW_TYPE_2D;
    ivci.format = VK_FORMAT_R8G8B8A8_UNORM; // Must match swapchain format
    ivci.components.r = VK_COMPONENT_SWIZZLE_IDENTITY;
    ivci.components.g = VK_COMPONENT_SWIZZLE_IDENTITY;
    ivci.components.b = VK_COMPONENT_SWIZZLE_IDENTITY;
    ivci.components.a = VK_COMPONENT_SWIZZLE_IDENTITY;
    ivci.subresourceRange.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    ivci.subresourceRange.baseMipLevel = 0;
    ivci.subresourceRange.levelCount = 1;
    ivci.subresourceRange.baseArrayLayer = 0;
    ivci.subresourceRange.layerCount = 1;

    if (vkCreateImageView(g_device, &ivci, NULL, &g_imageViews[i]) !=
        VK_SUCCESS) {
      LOGE("Failed to create image view %u", i);
      return -1;
    }
  }
  return 0;
}

/**
 * Create Render Pass
 */
static int create_render_pass(void) {
  if (g_renderPass != VK_NULL_HANDLE)
    vkDestroyRenderPass(g_device, g_renderPass, NULL);

  VkAttachmentDescription colorAttachment = {0};
  colorAttachment.format = VK_FORMAT_R8G8B8A8_UNORM;
  colorAttachment.samples = VK_SAMPLE_COUNT_1_BIT;
  colorAttachment.loadOp =
      VK_ATTACHMENT_LOAD_OP_CLEAR; // Clear to background (Dark Blue)
  colorAttachment.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
  colorAttachment.stencilLoadOp = VK_ATTACHMENT_LOAD_OP_DONT_CARE;
  colorAttachment.stencilStoreOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;
  colorAttachment.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
  colorAttachment.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;

  VkAttachmentReference colorAttachmentRef = {0};
  colorAttachmentRef.attachment = 0;
  colorAttachmentRef.layout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;

  VkSubpassDescription subpass = {0};
  subpass.pipelineBindPoint = VK_PIPELINE_BIND_POINT_GRAPHICS;
  subpass.colorAttachmentCount = 1;
  subpass.pColorAttachments = &colorAttachmentRef;

  VkSubpassDependency dependency = {0};
  dependency.srcSubpass = VK_SUBPASS_EXTERNAL;
  dependency.dstSubpass = 0;
  dependency.srcStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  dependency.srcAccessMask = 0;
  dependency.dstStageMask = VK_PIPELINE_STAGE_COLOR_ATTACHMENT_OUTPUT_BIT;
  dependency.dstAccessMask = VK_ACCESS_COLOR_ATTACHMENT_WRITE_BIT;

  VkRenderPassCreateInfo renderPassInfo = {
      .sType = VK_STRUCTURE_TYPE_RENDER_PASS_CREATE_INFO};
  renderPassInfo.attachmentCount = 1;
  renderPassInfo.pAttachments = &colorAttachment;
  renderPassInfo.subpassCount = 1;
  renderPassInfo.pSubpasses = &subpass;
  renderPassInfo.dependencyCount = 1;
  renderPassInfo.pDependencies = &dependency;

  if (vkCreateRenderPass(g_device, &renderPassInfo, NULL, &g_renderPass) !=
      VK_SUCCESS) {
    LOGE("Failed to create render pass");
    return -1;
  }
  return 0;
}

/**
 * Create Framebuffers
 */
static int create_framebuffers(uint32_t imageCount, VkExtent2D extent) {
  if (g_framebuffers)
    free(g_framebuffers);
  g_framebuffers = malloc(imageCount * sizeof(VkFramebuffer));
  for (uint32_t i = 0; i < imageCount; i++) {
    VkImageView attachments[] = {g_imageViews[i]};

    VkFramebufferCreateInfo framebufferInfo = {
        .sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO};
    framebufferInfo.renderPass = g_renderPass;
    framebufferInfo.attachmentCount = 1;
    framebufferInfo.pAttachments = attachments;
    framebufferInfo.width = extent.width;
    framebufferInfo.height = extent.height;
    framebufferInfo.layers = 1;

    if (vkCreateFramebuffer(g_device, &framebufferInfo, NULL,
                            &g_framebuffers[i]) != VK_SUCCESS) {
      LOGE("Failed to create framebuffer %u", i);
      return -1;
    }
  }
  return 0;
}

/** Context for Choreographer vsync-driven frame callback (Phase E) */
typedef struct {
  VkCommandBuffer cmdBuf;
  VkCommandPool cmdPool;
  VkExtent2D extent;
  int frame_count;
} RenderFrameCtx;

/** Frame callback invoked at display vsync by AChoreographer (NDK API:
 * frameTimeNanos first, then data) */
static void choreographer_frame_cb(int64_t frameTimeNanos, void *data) {
  (void)frameTimeNanos;
  RenderFrameCtx *ctx = (RenderFrameCtx *)data;
  if (!ctx || !g_running)
    return;

  VkResult res;
  uint32_t imageIndex;

  if (g_core) {
    WWNCoreProcessEvents(g_core);
    /* Drain window events - update g_window_title for TitleChanged */
    CWindowEvent *evt;
    while ((evt = WWNCorePopWindowEvent(g_core)) != NULL) {
      if ((evt->event_type == CWindowEventTypeTitleChanged ||
           evt->event_type == CWindowEventTypeCreated) &&
          evt->title != NULL) {
        pthread_mutex_lock(&g_title_lock);
        strncpy(g_window_title, evt->title, WINDOW_TITLE_MAX - 1);
        g_window_title[WINDOW_TITLE_MAX - 1] = '\0';
        pthread_mutex_unlock(&g_title_lock);
      }
      WWNWindowEventFree(evt);
    }
  }

  res = vkAcquireNextImageKHR(g_device, g_swapchain, UINT64_MAX, VK_NULL_HANDLE,
                              VK_NULL_HANDLE, &imageIndex);
  if (res != VK_SUCCESS && res != VK_SUBOPTIMAL_KHR) {
    if (res != VK_ERROR_OUT_OF_DATE_KHR)
      LOGE("vkAcquireNextImageKHR failed: %d", res);
    return;
  }

  res = vkBeginCommandBuffer(
      ctx->cmdBuf, &(VkCommandBufferBeginInfo){
                       .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO,
                       .flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT});
  if (res != VK_SUCCESS)
    return;

  /* Process pending buffers BEFORE render pass - upload SHM to textures */
  if (g_core) {
    CBufferData *buf;
    while ((buf = WWNCorePopPendingBuffer(g_core)) != NULL) {
      if (buf->pixels && buf->width > 0 && buf->height > 0) {
        renderer_android_cache_buffer(ctx->cmdBuf, buf->buffer_id, buf->width,
                                      buf->height, buf->stride, buf->format,
                                      buf->pixels, buf->size);
      }
      WWNBufferDataFree(buf);
    }
  }

  VkClearValue clearValue = {{{0.0f, 0.0f, 0.0f, 1.0f}}};
  VkRenderPassBeginInfo rpbi = {.sType =
                                    VK_STRUCTURE_TYPE_RENDER_PASS_BEGIN_INFO,
                                .renderPass = g_renderPass,
                                .framebuffer = g_framebuffers[imageIndex],
                                .renderArea = {{0, 0}, ctx->extent},
                                .clearValueCount = 1,
                                .pClearValues = &clearValue};
  vkCmdBeginRenderPass(ctx->cmdBuf, &rpbi, VK_SUBPASS_CONTENTS_INLINE);

  /* Set viewport and scissor (required for dynamic state) */
  VkViewport viewport = {.x = 0,
                         .y = 0,
                         .width = (float)ctx->extent.width,
                         .height = (float)ctx->extent.height,
                         .minDepth = 0,
                         .maxDepth = 1};
  vkCmdSetViewport(ctx->cmdBuf, 0, 1, &viewport);
  VkRect2D scissor = {{0, 0}, ctx->extent};
  vkCmdSetScissor(ctx->cmdBuf, 0, 1, &scissor);

  /* Draw scene nodes as textured quads */
  if (g_core) {
    CRenderScene *scene = WWNCoreGetRenderScene(g_core);
    if (scene) {
      if (scene->count > 0) {
        g_pointer_window_id =
            scene->nodes[0].window_id; /* Update for pointer/input focus */
        renderer_android_draw_quads(ctx->cmdBuf, scene->nodes, scene->count,
                                    ctx->extent.width, ctx->extent.height);
      }
      /* Draw cursor after scene nodes */
      if (scene->has_cursor && scene->cursor_buffer_id > 0) {
        renderer_android_draw_cursor(
            ctx->cmdBuf, scene->cursor_buffer_id, scene->cursor_x,
            scene->cursor_y, scene->cursor_hotspot_x, scene->cursor_hotspot_y,
            ctx->extent.width, ctx->extent.height);
      }
      for (size_t i = 0; i < scene->count; i++) {
        CRenderNode *node = &scene->nodes[i];
        WWNCoreNotifyFramePresented(g_core, node->surface_id, node->buffer_id,
                                    (uint32_t)(ctx->frame_count * 16));
      }
      WWNRenderSceneFree(scene);
    }
  }

  vkCmdEndRenderPass(ctx->cmdBuf);
  vkEndCommandBuffer(ctx->cmdBuf);

  VkFence fence;
  vkCreateFence(
      g_device,
      &(VkFenceCreateInfo){.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}, NULL,
      &fence);
  vkQueueSubmit(g_queue, 1,
                &(VkSubmitInfo){.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                                .commandBufferCount = 1,
                                .pCommandBuffers = &ctx->cmdBuf},
                fence);
  vkWaitForFences(g_device, 1, &fence, VK_TRUE, UINT64_MAX);
  vkDestroyFence(g_device, fence, NULL);

  res = vkQueuePresentKHR(
      g_queue, &(VkPresentInfoKHR){.sType = VK_STRUCTURE_TYPE_PRESENT_INFO_KHR,
                                   .swapchainCount = 1,
                                   .pSwapchains = &g_swapchain,
                                   .pImageIndices = &imageIndex});
  if (res != VK_SUCCESS && res != VK_SUBOPTIMAL_KHR &&
      res != VK_ERROR_OUT_OF_DATE_KHR) {
    LOGE("vkQueuePresentKHR failed: %d", res);
    return;
  }

  ctx->frame_count++;
  if (ctx->frame_count % 300 == 0)
    LOGI("Rendered frame %d (vsync)", ctx->frame_count);

  if (g_running) {
    AChoreographer_postFrameCallback(AChoreographer_getInstance(),
                                     choreographer_frame_cb, ctx);
  }
}

/**
 * Render thread - renders frames to the swapchain
 * Uses AChoreographer for vsync-aligned frame timing (Phase E)
 */
static void *render_thread(void *arg) {
  (void)arg;
  LOGI("Render thread started with settings:");
  LOGI("  Force Server-Side Decorations: %s",
       WWNSettings_GetForceServerSideDecorations() ? "enabled" : "disabled");
  LOGI("  Auto Retina Scaling: %s",
       WWNSettings_GetAutoRetinaScalingEnabled() ? "enabled" : "disabled");
  LOGI("  Rendering Backend: %d (0=Automatic, 1=Vulkan, 2=Surface)",
       WWNSettings_GetRenderingBackend());
  LOGI("  Respect Safe Area: %s",
       WWNSettings_GetRespectSafeArea() ? "enabled" : "disabled");
  LOGI("  Safe Area: left=%d, top=%d, right=%d, bottom=%d", g_safeAreaLeft,
       g_safeAreaTop, g_safeAreaRight, g_safeAreaBottom);
  LOGI("  Render macOS Pointer: %s",
       WWNSettings_GetRenderMacOSPointer() ? "enabled" : "disabled");
  LOGI("  Swap Cmd as Ctrl: %s",
       WWNSettings_GetSwapCmdAsCtrl() ? "enabled" : "disabled");
  LOGI("  Universal Clipboard: %s",
       WWNSettings_GetUniversalClipboardEnabled() ? "enabled" : "disabled");
  LOGI("  ColorSync Support: %s",
       WWNSettings_GetColorSyncSupportEnabled() ? "enabled" : "disabled");
  LOGI("  Nested Compositors Support: %s",
       WWNSettings_GetNestedCompositorsSupportEnabled() ? "enabled"
                                                        : "disabled");
  LOGI("  Use Metal 4 for Nested: %s",
       WWNSettings_GetUseMetal4ForNested() ? "enabled" : "disabled");
  LOGI("  Multiple Clients: %s",
       WWNSettings_GetMultipleClientsEnabled() ? "enabled" : "disabled");
  LOGI("  Waypipe RS Support: %s",
       WWNSettings_GetWaypipeRSSupportEnabled() ? "enabled" : "disabled");
  LOGI("  Enable TCP Listener: %s",
       WWNSettings_GetEnableTCPListener() ? "enabled" : "disabled");
  LOGI("  TCP Port: %d", WWNSettings_GetTCPListenerPort());

  // Get swapchain images
  uint32_t imageCount = 0;
  VkResult res =
      vkGetSwapchainImagesKHR(g_device, g_swapchain, &imageCount, NULL);
  if (res != VK_SUCCESS || imageCount == 0) {
    LOGE("Failed to get swapchain images: %d, count=%u", res, imageCount);
    return NULL;
  }

  VkImage *images = malloc(imageCount * sizeof(VkImage));
  res = vkGetSwapchainImagesKHR(g_device, g_swapchain, &imageCount, images);
  if (res != VK_SUCCESS) {
    LOGE("Failed to get swapchain images: %d", res);
    free(images);
    return NULL;
  }

  LOGI("Got %u swapchain images", imageCount);

  // Get surface capabilities for extent
  VkSurfaceCapabilitiesKHR caps;
  VkPhysicalDevice pd = pick_device();
  vkGetPhysicalDeviceSurfaceCapabilitiesKHR(pd, g_surface, &caps);
  VkExtent2D extent = caps.currentExtent;

  // Create Render Pass and Framebuffers
  if (create_image_views(imageCount, images) != 0)
    return NULL;
  if (create_render_pass() != 0)
    return NULL;
  if (create_framebuffers(imageCount, extent) != 0)
    return NULL;

  // Create textured quad pipeline for surface rendering
  if (renderer_android_create_pipeline(g_device, pick_device(), g_renderPass,
                                       g_queue_family, extent.width,
                                       extent.height) != 0) {
    LOGI("Warning: renderer pipeline creation failed, surfaces may not render");
  }

  // Create command pool
  VkCommandPool cmdPool;
  VkCommandPoolCreateInfo cpci = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
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
  VkCommandBufferAllocateInfo cbai = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
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

  // Set output size for the compositor core
  if (g_core) {
    WWNCoreSetOutputSize(g_core, extent.width, extent.height, 1.0f);
    LOGI("Set compositor output size: %ux%u", extent.width, extent.height);
  }

  /* Phase E: Choreographer vsync - prepare Looper and drive frames at display
   * refresh */
  RenderFrameCtx frame_ctx = {
      .cmdBuf = cmdBuf, .cmdPool = cmdPool, .extent = extent, .frame_count = 0};

  ALooper_prepare(0);
  AChoreographer_postFrameCallback(AChoreographer_getInstance(),
                                   choreographer_frame_cb, &frame_ctx);

  while (g_running) {
    int ret = ALooper_pollOnce(-1, NULL, NULL, NULL);
    if (ret == ALOOPER_POLL_ERROR)
      break;
  }

  vkDeviceWaitIdle(g_device);
  renderer_android_destroy_pipeline();
  vkFreeCommandBuffers(g_device, cmdPool, 1, &cmdBuf);
  vkDestroyCommandPool(g_device, cmdPool, NULL);
  free(images);

  LOGI("Render thread stopped, rendered %d frames", frame_ctx.frame_count);
  return NULL;
}

// ============================================================================
// JNI Interface
// ============================================================================

/**
 * Initialize the compositor - create Vulkan instance
 * Called from Android Activity.onCreate()
 */
JNIEXPORT void JNICALL Java_com_aspauldingcode_wawona_WawonaNative_nativeInit(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  pthread_mutex_lock(&g_lock);
  if (g_instance != VK_NULL_HANDLE) {
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Starting Wawona Compositor (Android) - Rust Core + Vulkan");

  // Initialize the Rust compositor core
  if (!g_core) {
    // Set up XDG_RUNTIME_DIR for the Wayland socket
    const char *cache_dir = getenv("TMPDIR");
    if (!cache_dir)
      cache_dir = "/data/local/tmp";
    char runtime_dir[256];
    snprintf(runtime_dir, sizeof(runtime_dir), "%s/wawona-runtime", cache_dir);
    mkdir(runtime_dir, 0700);
    setenv("XDG_RUNTIME_DIR", runtime_dir, 1);
    LOGI("XDG_RUNTIME_DIR=%s", runtime_dir);

    g_core = WWNCoreNew();
    if (g_core) {
      LOGI("WWNCoreNew() succeeded: %p", g_core);
      if (WWNCoreStart(g_core, "wayland-0")) {
        LOGI("Compositor started on wayland-0");
        setenv("WAYLAND_DISPLAY", "wayland-0", 1);
      } else {
        LOGE("WWNCoreStart() failed");
      }
    } else {
      LOGE("WWNCoreNew() returned NULL");
    }
  }

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

/**
 * Set the Android Surface and initialize rendering
 * Called when the SurfaceView is created/updated
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetSurface(JNIEnv *env,
                                                             jobject thiz,
                                                             jobject surface) {
  (void)thiz;
  pthread_mutex_lock(&g_lock);

  LOGI("nativeSetSurface called");

  if (g_window) {
    LOGI("Releasing existing ANativeWindow");
    ANativeWindow_release(g_window);
    g_window = NULL;
  }

  ANativeWindow *win = ANativeWindow_fromSurface(env, surface);
  if (!win) {
    LOGE("ANativeWindow_fromSurface returned NULL");
    pthread_mutex_unlock(&g_lock);
    return;
  }
  g_window = win;
  LOGI("Received ANativeWindow %p", (void *)win);

  // Skip safe area update for now - thiz is WawonaNative object, not Activity
  // Safe area will be updated when settings are applied via nativeApplySettings
  LOGI("Skipping safe area update (will be set via settings)");
  g_safeAreaLeft = 0;
  g_safeAreaTop = 0;
  g_safeAreaRight = 0;
  g_safeAreaBottom = 0;

  if (g_instance == VK_NULL_HANDLE) {
    LOGI("Creating Vulkan instance...");
    if (create_instance() != VK_SUCCESS) {
      LOGE("Failed to create Vulkan instance");
      ANativeWindow_release(win);
      g_window = NULL;
      pthread_mutex_unlock(&g_lock);
      return;
    }
    LOGI("Vulkan instance created");
  } else {
    LOGI("Vulkan instance already exists");
  }

  LOGI("Creating Android surface...");
  VkAndroidSurfaceCreateInfoKHR sci = {
      .sType = VK_STRUCTURE_TYPE_ANDROID_SURFACE_CREATE_INFO_KHR};
  sci.window = win;
  VkResult res = vkCreateAndroidSurfaceKHR(g_instance, &sci, NULL, &g_surface);
  if (res != VK_SUCCESS) {
    LOGE("vkCreateAndroidSurfaceKHR failed: %d", res);
    ANativeWindow_release(win);
    g_window = NULL;
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Android VkSurfaceKHR created: %p", (void *)g_surface);

  LOGI("Picking Vulkan device...");
  VkPhysicalDevice pd = pick_device();
  if (pd == VK_NULL_HANDLE) {
    LOGE("No Vulkan devices found");
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    ANativeWindow_release(win);
    g_window = NULL;
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Vulkan device picked");

  LOGI("Creating Vulkan device...");
  if (create_device(pd) != 0) {
    LOGE("Failed to create device");
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    ANativeWindow_release(win);
    g_window = NULL;
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Vulkan device created");

  LOGI("Creating swapchain...");
  if (create_swapchain(pd) != 0) {
    LOGE("Failed to create swapchain");
    vkDestroyDevice(g_device, NULL);
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    ANativeWindow_release(win);
    g_window = NULL;
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Swapchain created");

  // Start render thread with delay to ensure surface is ready
  LOGI("Starting render thread...");
  g_running = 1;
  usleep(500000); // 500ms delay to let surface stabilize
  int thread_result =
      pthread_create(&g_render_thread, NULL, render_thread, NULL);
  if (thread_result != 0) {
    LOGE("Failed to create render thread: %d", thread_result);
    g_running = 0;
    vkDestroySwapchainKHR(g_device, g_swapchain, NULL);
    vkDestroyDevice(g_device, NULL);
    vkDestroySurfaceKHR(g_instance, g_surface, NULL);
    ANativeWindow_release(win);
    g_window = NULL;
    pthread_mutex_unlock(&g_lock);
    return;
  }
  LOGI("Render thread created successfully");

  LOGI("Wawona Compositor initialized successfully");
  pthread_mutex_unlock(&g_lock);
}

/**
 * Destroy surface and clean up Vulkan resources
 * Called when the SurfaceView is destroyed
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeDestroySurface(JNIEnv *env,
                                                                 jobject thiz) {
  (void)env;
  (void)thiz;
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

  // Clean up Framebuffers
  if (g_framebuffers) {
    for (uint32_t i = 0; i < g_swapchainImageCount; i++) {
      vkDestroyFramebuffer(g_device, g_framebuffers[i], NULL);
    }
    free(g_framebuffers);
    g_framebuffers = NULL;
  }

  // Clean up Render Pass
  if (g_renderPass != VK_NULL_HANDLE) {
    vkDestroyRenderPass(g_device, g_renderPass, NULL);
    g_renderPass = VK_NULL_HANDLE;
  }

  // Clean up Image Views
  if (g_imageViews) {
    for (uint32_t i = 0; i < g_swapchainImageCount; i++) {
      vkDestroyImageView(g_device, g_imageViews[i], NULL);
    }
    free(g_imageViews);
    g_imageViews = NULL;
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

  if (g_window) {
    ANativeWindow_release(g_window);
    g_window = NULL;
  }

  // Stop and free the compositor core
  if (g_core) {
    LOGI("Stopping compositor core...");
    WWNCoreStop(g_core);
    WWNCoreFree(g_core);
    g_core = NULL;
  }

  LOGI("Surface destroyed");
  pthread_mutex_unlock(&g_lock);
}

/**
 * Update safe area insets from Android WindowInsets API
 * Called directly from Kotlin to avoid complex JNI reflection
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeUpdateSafeArea(
    JNIEnv *env, jobject thiz, jint left, jint top, jint right, jint bottom) {
  (void)env;
  (void)thiz;
  pthread_mutex_lock(&g_lock);

  g_rawSafeAreaLeft = left;
  g_rawSafeAreaTop = top;
  g_rawSafeAreaRight = right;
  g_rawSafeAreaBottom = bottom;

  if (WWNSettings_GetRespectSafeArea()) {
    g_safeAreaLeft = left;
    g_safeAreaTop = top;
    g_safeAreaRight = right;
    g_safeAreaBottom = bottom;
    LOGI("JNI Update Safe Area: Applied (L=%d, T=%d, R=%d, B=%d)", left, top,
         right, bottom);
  } else {
    g_safeAreaLeft = 0;
    g_safeAreaTop = 0;
    g_safeAreaRight = 0;
    g_safeAreaBottom = 0;
    LOGI("JNI Update Safe Area: Cached (L=%d, T=%d, R=%d, B=%d), but disabled",
         left, top, right, bottom);
  }
  /* Push to Rust backend for layer-shell exclusive zones etc. */
  if (g_core) {
    WWNCoreSetSafeAreaInsets(g_core, g_safeAreaTop, g_safeAreaRight,
                             g_safeAreaBottom, g_safeAreaLeft);
  }
  pthread_mutex_unlock(&g_lock);
}

/**
 * Apply iOS-compatible settings
 * Provides 1:1 mapping of iOS settings for cross-platform compatibility
 */
JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeApplySettings(
    JNIEnv *env, jobject thiz, jboolean forceServerSideDecorations,
    jboolean autoRetinaScaling, jint renderingBackend, jboolean respectSafeArea,
    jboolean renderMacOSPointer, jboolean swapCmdAsCtrl,
    jboolean universalClipboard, jboolean colorSyncSupport,
    jboolean nestedCompositorsSupport, jboolean useMetal4ForNested,
    jboolean multipleClients, jboolean waypipeRSSupport,
    jboolean enableTCPListener, jint tcpPort, jstring vulkanDriver,
    jstring openglDriver) {
  (void)thiz;
  pthread_mutex_lock(&g_lock);

  LOGI("Applying Wawona settings:");
  LOGI("  Force Server-Side Decorations: %s",
       forceServerSideDecorations ? "enabled" : "disabled");
  LOGI("  Auto Retina Scaling: %s", autoRetinaScaling ? "enabled" : "disabled");
  LOGI("  Rendering Backend: %d (0=Automatic, 1=Vulkan, 2=Surface)",
       renderingBackend);
  LOGI("  Respect Safe Area: %s", respectSafeArea ? "enabled" : "disabled");
  LOGI("  Render Software Pointer: %s",
       renderMacOSPointer ? "enabled" : "disabled");
  LOGI("  Swap Cmd as Ctrl: %s", swapCmdAsCtrl ? "enabled" : "disabled");
  LOGI("  Universal Clipboard: %s",
       universalClipboard ? "enabled" : "disabled");
  LOGI("  ColorSync Support: %s", colorSyncSupport ? "enabled" : "disabled");
  LOGI("  Nested Compositors Support: %s",
       nestedCompositorsSupport ? "enabled" : "disabled");
  LOGI("  Use Metal 4 for Nested: %s",
       useMetal4ForNested ? "enabled" : "disabled");
  LOGI("  Multiple Clients: %s", multipleClients ? "enabled" : "disabled");
  LOGI("  Waypipe RS Support: %s", waypipeRSSupport ? "enabled" : "disabled");
  LOGI("  Enable TCP Listener: %s", enableTCPListener ? "enabled" : "disabled");
  LOGI("  TCP Port: %d", tcpPort);

  char vulkanDriverBuf[32] = {0};
  char openglDriverBuf[32] = {0};
  if (vulkanDriver) {
    const char *s = (*env)->GetStringUTFChars(env, vulkanDriver, NULL);
    if (s) {
      strncpy(vulkanDriverBuf, s, sizeof(vulkanDriverBuf) - 1);
      (*env)->ReleaseStringUTFChars(env, vulkanDriver, s);
    }
  }
  if (openglDriver) {
    const char *s = (*env)->GetStringUTFChars(env, openglDriver, NULL);
    if (s) {
      strncpy(openglDriverBuf, s, sizeof(openglDriverBuf) - 1);
      (*env)->ReleaseStringUTFChars(env, openglDriver, s);
    }
  }
  LOGI("  Vulkan Driver: %s", vulkanDriverBuf[0] ? vulkanDriverBuf : "system");
  LOGI("  OpenGL Driver: %s", openglDriverBuf[0] ? openglDriverBuf : "system");

  // Apply settings
  WWNSettingsConfig config = {
      .forceServerSideDecorations = forceServerSideDecorations,
      .autoRetinaScaling = autoRetinaScaling,
      .renderingBackend = renderingBackend,
      .respectSafeArea = respectSafeArea,
      .renderMacOSPointer = renderMacOSPointer,
      .swapCmdAsCtrl = swapCmdAsCtrl,
      .universalClipboard = universalClipboard,
      .colorSyncSupport = colorSyncSupport,
      .nestedCompositorsSupport = nestedCompositorsSupport,
      .useMetal4ForNested = useMetal4ForNested,
      .multipleClients = multipleClients,
      .waypipeRSSupport = waypipeRSSupport,
      .enableTCPListener = enableTCPListener,
      .tcpPort = tcpPort,
      .vulkanDrivers = false,
      .eglDrivers = false};
  strncpy(config.vulkanDriver, vulkanDriverBuf[0] ? vulkanDriverBuf : "system",
          sizeof(config.vulkanDriver) - 1);
  config.vulkanDriver[sizeof(config.vulkanDriver) - 1] = '\0';
  strncpy(config.openglDriver, openglDriverBuf[0] ? openglDriverBuf : "system",
          sizeof(config.openglDriver) - 1);
  config.openglDriver[sizeof(config.openglDriver) - 1] = '\0';
  WWNSettings_UpdateConfig(&config);

  /* Push to Rust backend */
  if (g_core) {
    WWNCoreSetForceSSD(g_core, forceServerSideDecorations ? 1 : 0);
    WWNCoreSetSafeAreaInsets(g_core, g_safeAreaTop, g_safeAreaRight,
                             g_safeAreaBottom, g_safeAreaLeft);
  }

  // Update safe area based on new setting
  if (respectSafeArea) {
    g_safeAreaLeft = g_rawSafeAreaLeft;
    g_safeAreaTop = g_rawSafeAreaTop;
    g_safeAreaRight = g_rawSafeAreaRight;
    g_safeAreaBottom = g_rawSafeAreaBottom;
  } else {
    g_safeAreaLeft = 0;
    g_safeAreaTop = 0;
    g_safeAreaRight = 0;
    g_safeAreaBottom = 0;
  }

  LOGI("Safe area updated based on settings: %s (L=%d, T=%d, R=%d, B=%d)",
       respectSafeArea ? "enabled" : "disabled", g_safeAreaLeft, g_safeAreaTop,
       g_safeAreaRight, g_safeAreaBottom);

  LOGI("Wawona settings applied successfully with safe area support");
  pthread_mutex_unlock(&g_lock);
}

// ============================================================================
// JNI Initialization
// ============================================================================

static int pfd[2];
static pthread_t thr;
static const char *tag = "Wawona-Stdout";

static void *thread_func(void *arg) {
  ssize_t rdsz;
  char buf[128];
  while ((rdsz = read(pfd[0], buf, sizeof buf - 1)) > 0) {
    if (buf[rdsz - 1] == '\n')
      --rdsz;
    buf[rdsz] = 0; /* add null-terminator */
    __android_log_write(ANDROID_LOG_DEBUG, tag, buf);
  }
  return 0;
}

// ---------------------------------------------------------------------------
// Text Input (IME / Emoji) — forward composed text to Wayland text-input-v3
// ---------------------------------------------------------------------------

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeSetCore(JNIEnv *env,
                                                          jobject thiz,
                                                          jlong corePtr) {
  (void)env;
  (void)thiz;
  pthread_mutex_lock(&g_lock);
  g_core = (void *)(intptr_t)corePtr;
  LOGI("Compositor core pointer set: %p", g_core);
  pthread_mutex_unlock(&g_lock);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeCommitText(JNIEnv *env,
                                                             jobject thiz,
                                                             jstring text) {
  (void)thiz;
  const char *utf8 = (*env)->GetStringUTFChars(env, text, NULL);
  if (!utf8)
    return;
  LOGI("Text input commit: %s", utf8);
  if (g_core)
    WWNCoreTextInputCommit(g_core, utf8);
  (*env)->ReleaseStringUTFChars(env, text, utf8);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePreeditText(
    JNIEnv *env, jobject thiz, jstring text, jint cursorBegin, jint cursorEnd) {
  (void)thiz;
  const char *utf8 = (*env)->GetStringUTFChars(env, text, NULL);
  if (!utf8)
    return;
  LOGI("Text input preedit: %s [%d..%d]", utf8, cursorBegin, cursorEnd);
  if (g_core)
    WWNCoreTextInputPreedit(g_core, utf8, cursorBegin, cursorEnd);
  (*env)->ReleaseStringUTFChars(env, text, utf8);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeDeleteSurroundingText(
    JNIEnv *env, jobject thiz, jint beforeLength, jint afterLength) {
  (void)env;
  (void)thiz;
  LOGI("Text input delete surrounding: before=%d after=%d", beforeLength,
       afterLength);
  if (g_core)
    WWNCoreTextInputDeleteSurrounding(g_core, (uint32_t)beforeLength,
                                      (uint32_t)afterLength);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetCursorRect(
    JNIEnv *env, jobject thiz, jintArray outRect) {
  (void)thiz;
  if (!outRect)
    return;
  jsize len = (*env)->GetArrayLength(env, outRect);
  if (len < 4)
    return;
  int32_t x = 0, y = 0, w = 0, h = 0;
  if (g_core)
    WWNCoreTextInputGetCursorRect(g_core, &x, &y, &w, &h);
  jint buf[4] = {x, y, w, h};
  (*env)->SetIntArrayRegion(env, outRect, 0, 4, buf);
}

// ============================================================================
// Touch / Key Input Forwarding
// ============================================================================

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchDown(
    JNIEnv *env, jobject thiz, jint id, jfloat x, jfloat y, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    if (g_active_touches == 0) {
      WWNCoreInjectPointerEnter(g_core, g_pointer_window_id, (double)x,
                                (double)y, (uint32_t)timestampMs);
    }
    g_active_touches++;
    WWNCoreInjectTouchDown(g_core, id, (double)x, (double)y,
                           (uint32_t)timestampMs);
    WWNCoreInject_touch_frame(g_core);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchUp(JNIEnv *env,
                                                          jobject thiz, jint id,
                                                          jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    WWNCoreInjectTouchUp(g_core, id, (uint32_t)timestampMs);
    g_active_touches--;
    if (g_active_touches <= 0) {
      g_active_touches = 0;
      WWNCoreInjectPointerLeave(g_core, g_pointer_window_id,
                                (uint32_t)timestampMs);
    }
    WWNCoreInject_touch_frame(g_core);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchMotion(
    JNIEnv *env, jobject thiz, jint id, jfloat x, jfloat y, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    WWNCoreInjectTouchMotion(g_core, id, (double)x, (double)y,
                             (uint32_t)timestampMs);
    WWNCoreInject_touch_frame(g_core);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchCancel(JNIEnv *env,
                                                              jobject thiz) {
  (void)env;
  (void)thiz;
  if (g_core) {
    WWNCoreInjectTouchCancel(g_core);
    g_active_touches = 0;
    WWNCoreInjectPointerLeave(g_core, g_pointer_window_id, 0);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTouchFrame(JNIEnv *env,
                                                             jobject thiz) {
  (void)env;
  (void)thiz;
  if (g_core) {
    WWNCoreInject_touch_frame(g_core);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeKeyEvent(
    JNIEnv *env, jobject thiz, jint keycode, jint state, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (!g_core)
    return;

  uint32_t linux_keycode = android_keycode_to_linux((uint32_t)keycode);

  /* Update modifier state before injecting key */
  int pressed = (state == 1);
  uint32_t mod_bit = 0;
  if (linux_keycode == 42)
    mod_bit = XKB_MOD_SHIFT; /* KEY_LEFTSHIFT */
  else if (linux_keycode == 54)
    mod_bit = XKB_MOD_SHIFT; /* KEY_RIGHTSHIFT */
  else if (linux_keycode == 29)
    mod_bit = XKB_MOD_CTRL; /* KEY_LEFTCTRL */
  else if (linux_keycode == 97)
    mod_bit = XKB_MOD_CTRL; /* KEY_RIGHTCTRL */
  else if (linux_keycode == 56)
    mod_bit = XKB_MOD_ALT; /* KEY_LEFTALT */
  else if (linux_keycode == 100)
    mod_bit = XKB_MOD_ALT; /* KEY_RIGHTALT */
  else if (linux_keycode == 125)
    mod_bit = XKB_MOD_LOGO; /* KEY_LEFTMETA */
  else if (linux_keycode == 126)
    mod_bit = XKB_MOD_LOGO; /* KEY_RIGHTMETA */

  if (mod_bit) {
    if (pressed)
      g_modifiers_depressed |= mod_bit;
    else
      g_modifiers_depressed &= ~mod_bit;
    WWNCoreInjectModifiers(g_core, g_modifiers_depressed, 0, 0, 0);
  }

  WWNCoreInjectKey(g_core, linux_keycode, (uint32_t)state,
                   (uint32_t)timestampMs);
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerAxis(
    JNIEnv *env, jobject thiz, jint axis, jfloat value, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core && value != 0.0f) {
    /* axis: 0 = vertical, 1 = horizontal */
    WWNCoreInjectPointerAxis(g_core, g_pointer_window_id, (uint32_t)axis,
                             (double)value, (uint32_t)timestampMs);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerMotion(
    JNIEnv *env, jobject thiz, jdouble x, jdouble y, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    WWNCoreInjectPointerMotion(g_core, g_pointer_window_id, x, y,
                               (uint32_t)timestampMs);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerButton(
    JNIEnv *env, jobject thiz, jint buttonCode, jint state, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    /* buttonCode: 0x110 = BTN_LEFT, 0x111 = BTN_RIGHT */
    WWNCoreInjectPointerButton(g_core, g_pointer_window_id,
                               (uint32_t)buttonCode, (uint32_t)state,
                               (uint32_t)timestampMs);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerEnter(
    JNIEnv *env, jobject thiz, jdouble x, jdouble y, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    WWNCoreInjectPointerEnter(g_core, g_pointer_window_id, x, y,
                              (uint32_t)timestampMs);
  }
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativePointerLeave(
    JNIEnv *env, jobject thiz, jint timestampMs) {
  (void)env;
  (void)thiz;
  if (g_core) {
    WWNCoreInjectPointerLeave(g_core, g_pointer_window_id,
                              (uint32_t)timestampMs);
  }
}

JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetFocusedWindowTitle(
    JNIEnv *env, jobject thiz) {
  (void)thiz;
  pthread_mutex_lock(&g_title_lock);
  jstring result =
      (*env)->NewStringUTF(env, g_window_title[0] ? g_window_title : "");
  pthread_mutex_unlock(&g_title_lock);
  return result;
}

JNIEXPORT jlong JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetPendingScreencopy(
    JNIEnv *env, jobject thiz, jintArray outWidthHeight) {
  (void)thiz;
  jlong capture_id = 0;
  if (!g_core)
    return 0;
  CScreencopyRequest req = WWNCoreGetPendingScreencopy(g_core);
  if (req.capture_id == 0 || req.ptr == NULL)
    return 0;
  g_screencopy_ptr = req.ptr;
  g_screencopy_stride = req.stride;
  g_screencopy_size = req.size;
  capture_id = (jlong)req.capture_id;
  if (outWidthHeight && (*env)->GetArrayLength(env, outWidthHeight) >= 3) {
    jint whs[3] = {(jint)req.width, (jint)req.height, (jint)req.stride};
    (*env)->SetIntArrayRegion(env, outWidthHeight, 0, 3, whs);
  } else if (outWidthHeight &&
             (*env)->GetArrayLength(env, outWidthHeight) >= 2) {
    jint wh[2] = {(jint)req.width, (jint)req.height};
    (*env)->SetIntArrayRegion(env, outWidthHeight, 0, 2, wh);
  }
  return capture_id;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeScreencopyComplete(
    JNIEnv *env, jobject thiz, jlong captureId, jbyteArray pixels) {
  (void)thiz;
  if (!g_core || g_screencopy_ptr == NULL || !pixels)
    return;
  jsize len = (*env)->GetArrayLength(env, pixels);
  if ((size_t)len > g_screencopy_size)
    len = (jsize)g_screencopy_size;
  jbyte *src = (*env)->GetByteArrayElements(env, pixels, NULL);
  if (src) {
    memcpy(g_screencopy_ptr, src, (size_t)len);
    (*env)->ReleaseByteArrayElements(env, pixels, src, JNI_ABORT);
  }
  WWNCoreScreencopyDone(g_core, (uint64_t)captureId);
  g_screencopy_ptr = NULL;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeScreencopyFailed(
    JNIEnv *env, jobject thiz, jlong captureId) {
  (void)env;
  (void)thiz;
  if (!g_core)
    return;
  WWNCoreScreencopyFailed(g_core, (uint64_t)captureId);
  g_screencopy_ptr = NULL;
}

JNIEXPORT jlong JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeGetPendingImageCopyCapture(
    JNIEnv *env, jobject thiz, jintArray outWidthHeight) {
  (void)thiz;
  jlong capture_id = 0;
  if (!g_core)
    return 0;
  CScreencopyRequest req = WWNCoreGetPendingImageCopyCapture(g_core);
  if (req.capture_id == 0 || req.ptr == NULL)
    return 0;
  g_screencopy_ptr = req.ptr;
  g_screencopy_stride = req.stride;
  g_screencopy_size = req.size;
  capture_id = (jlong)req.capture_id;
  if (outWidthHeight && (*env)->GetArrayLength(env, outWidthHeight) >= 3) {
    jint whs[3] = {(jint)req.width, (jint)req.height, (jint)req.stride};
    (*env)->SetIntArrayRegion(env, outWidthHeight, 0, 3, whs);
  } else if (outWidthHeight &&
             (*env)->GetArrayLength(env, outWidthHeight) >= 2) {
    jint wh[2] = {(jint)req.width, (jint)req.height};
    (*env)->SetIntArrayRegion(env, outWidthHeight, 0, 2, wh);
  }
  return capture_id;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeImageCopyCaptureComplete(
    JNIEnv *env, jobject thiz, jlong captureId, jbyteArray pixels) {
  (void)thiz;
  if (!g_core || g_screencopy_ptr == NULL || !pixels)
    return;
  jsize len = (*env)->GetArrayLength(env, pixels);
  if ((size_t)len > g_screencopy_size)
    len = (jsize)g_screencopy_size;
  jbyte *src = (*env)->GetByteArrayElements(env, pixels, NULL);
  if (src) {
    memcpy(g_screencopy_ptr, src, (size_t)len);
    (*env)->ReleaseByteArrayElements(env, pixels, src, JNI_ABORT);
  }
  WWNCoreImageCopyCaptureDone(g_core, (uint64_t)captureId);
  g_screencopy_ptr = NULL;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeImageCopyCaptureFailed(
    JNIEnv *env, jobject thiz, jlong captureId) {
  (void)env;
  (void)thiz;
  if (!g_core)
    return;
  WWNCoreImageCopyCaptureFailed(g_core, (uint64_t)captureId);
  g_screencopy_ptr = NULL;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeKeyboardFocus(
    JNIEnv *env, jobject thiz, jboolean hasFocus) {
  (void)env;
  (void)thiz;
  if (!g_core)
    return;
  if (hasFocus) {
    WWNCoreInjectKeyboardEnter(g_core, g_pointer_window_id, NULL, 0, 0);
  } else {
    WWNCoreInjectKeyboardLeave(g_core, g_pointer_window_id);
  }
}

// ============================================================================
// Waypipe Integration
// ============================================================================

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <poll.h>
#include <signal.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <unistd.h>

static char g_ssh_bin_path[512] = {0};
static char g_sshpass_bin_path[512] = {0};

static void resolve_ssh_binary_paths(void) {
  if (g_ssh_bin_path[0])
    return;

  Dl_info info;
  if (dladdr((void *)resolve_ssh_binary_paths, &info) && info.dli_fname) {
    char nativeLibDir[512];
    strncpy(nativeLibDir, info.dli_fname, sizeof(nativeLibDir) - 1);
    char *lastSlash = strrchr(nativeLibDir, '/');
    if (lastSlash)
      *lastSlash = '\0';

    LOGI("[SSH] Native lib dir: %s", nativeLibDir);

    const char *cacheDir = getenv("XDG_RUNTIME_DIR");
    if (!cacheDir)
      cacheDir = "/data/local/tmp";
    char sshDest[512], sshpassDest[512];
    snprintf(sshDest, sizeof(sshDest), "%s/ssh", cacheDir);
    snprintf(sshpassDest, sizeof(sshpassDest), "%s/sshpass", cacheDir);

    char sshSrc[512], sshpassSrc[512];
    snprintf(sshSrc, sizeof(sshSrc), "%s/libssh_bin.so", nativeLibDir);
    snprintf(sshpassSrc, sizeof(sshpassSrc), "%s/libsshpass_bin.so",
             nativeLibDir);

    struct stat st;
    int need_copy_ssh = 1, need_copy_sshpass = 1;
    struct stat srcSt;
    if (stat(sshDest, &st) == 0 && stat(sshSrc, &srcSt) == 0 &&
        st.st_size == srcSt.st_size)
      need_copy_ssh = 0;
    if (stat(sshpassDest, &st) == 0 && stat(sshpassSrc, &srcSt) == 0 &&
        st.st_size == srcSt.st_size)
      need_copy_sshpass = 0;

    for (int i = 0; i < 2; i++) {
      const char *srcPath = (i == 0) ? sshSrc : sshpassSrc;
      const char *dstPath = (i == 0) ? sshDest : sshpassDest;
      int need = (i == 0) ? need_copy_ssh : need_copy_sshpass;
      const char *label = (i == 0) ? "ssh" : "sshpass";
      if (!need) {
        LOGI("[SSH] %s already up to date at %s", label, dstPath);
        continue;
      }
      int src_fd = open(srcPath, O_RDONLY);
      if (src_fd < 0) {
        LOGE("[SSH] Cannot open %s: %s", srcPath, strerror(errno));
        continue;
      }
      int dst_fd = open(dstPath, O_WRONLY | O_CREAT | O_TRUNC, 0755);
      if (dst_fd < 0) {
        LOGE("[SSH] Cannot create %s: %s", dstPath, strerror(errno));
        close(src_fd);
        continue;
      }
      char buf[65536];
      ssize_t n;
      while ((n = read(src_fd, buf, sizeof(buf))) > 0) {
        write(dst_fd, buf, n);
      }
      close(src_fd);
      close(dst_fd);
      chmod(dstPath, 0755);
      LOGI("[SSH] Installed %s to %s", label, dstPath);
    }

    strncpy(g_ssh_bin_path, sshDest, sizeof(g_ssh_bin_path) - 1);
    strncpy(g_sshpass_bin_path, sshpassDest, sizeof(g_sshpass_bin_path) - 1);
    LOGI("[SSH] ssh binary: %s", g_ssh_bin_path);
    LOGI("[SSH] sshpass binary: %s", g_sshpass_bin_path);
  } else {
    LOGE("[SSH] dladdr failed - cannot locate native lib directory");
  }
}

static volatile int g_waypipe_running = 0;
static pthread_t g_waypipe_thread = 0;
static volatile int g_waypipe_stop_requested = 0;

typedef struct {
  int ssh_enabled;
  char ssh_host[256];
  char ssh_user[128];
  char ssh_password[256];
  char remote_command[512];
  char compress[64];
  int threads;
  char video[64];
  int debug;
  int oneshot;
  int no_gpu;
  int login_shell;
  char title_prefix[128];
  char sec_ctx[128];
} WaypipeConfig;

static WaypipeConfig g_waypipe_config;

// SSH bridge: connects to remote via OpenSSH and runs a remote command.
// Bridges data between a local Unix socket and the SSH channel.
typedef struct {
  char local_socket_path[512];
  char host[256];
  char user[128];
  char password[256];
  char remote_cmd[4096];
  int port;
  volatile int *stop_flag;
} SSHBridgeConfig;

static SSHBridgeConfig g_ssh_bridge;

// SSH bridge thread: connects to remote via OpenSSH (fork/exec),
// runs a remote command, then bridges data between the local waypipe
// Unix socket and the SSH process's stdin/stdout pipes.
static void *ssh_bridge_thread(void *arg) {
  SSHBridgeConfig *cfg = (SSHBridgeConfig *)arg;
  int local_fd = -1;
  pid_t ssh_pid = -1;
  int ssh_stdin[2] = {-1, -1};
  int ssh_stdout[2] = {-1, -1};
  int ssh_stderr[2] = {-1, -1};

  LOGI("[SSH-BRIDGE] Connecting via OpenSSH to %s@%s:%d", cfg->user, cfg->host,
       cfg->port);

  if (pipe(ssh_stdin) < 0 || pipe(ssh_stdout) < 0 || pipe(ssh_stderr) < 0) {
    LOGE("[SSH-BRIDGE] pipe() failed: %s", strerror(errno));
    return NULL;
  }

  char port_str[16];
  snprintf(port_str, sizeof(port_str), "%d", cfg->port);

  ssh_pid = fork();
  if (ssh_pid < 0) {
    LOGE("[SSH-BRIDGE] fork() failed: %s", strerror(errno));
    return NULL;
  }

  if (ssh_pid == 0) {
    close(ssh_stdin[1]);
    close(ssh_stdout[0]);
    close(ssh_stderr[0]);
    dup2(ssh_stdin[0], STDIN_FILENO);
    dup2(ssh_stdout[1], STDOUT_FILENO);
    dup2(ssh_stderr[1], STDERR_FILENO);
    close(ssh_stdin[0]);
    close(ssh_stdout[1]);
    close(ssh_stderr[1]);

    if (cfg->password[0] != '\0') {
      setenv("SSHPASS", cfg->password, 1);
    }

    /* Dropbear (dbclient) bundled as ssh: use -y to auto-accept host keys,
       -T for no-pty mode (we're bridging raw data) */
    execl(g_ssh_bin_path, "ssh", "-y", "-T", "-p", port_str, "-l", cfg->user,
          cfg->host, cfg->remote_cmd, (char *)NULL);

    fprintf(stderr, "[SSH-BRIDGE] exec failed: %s (path=%s)\n", strerror(errno),
            g_ssh_bin_path);
    _exit(127);
  }

  close(ssh_stdin[0]);
  ssh_stdin[0] = -1;
  close(ssh_stdout[1]);
  ssh_stdout[1] = -1;
  close(ssh_stderr[1]);
  ssh_stderr[1] = -1;
  LOGI("[SSH-BRIDGE] SSH child process started (pid %d)", (int)ssh_pid);

  LOGI("[SSH-BRIDGE] Waiting for local socket: %s", cfg->local_socket_path);
  for (int i = 0; i < 100 && !*(cfg->stop_flag); i++) {
    struct stat st;
    if (stat(cfg->local_socket_path, &st) == 0 && (st.st_mode & S_IFSOCK))
      break;
    usleep(100000);
  }

  local_fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (local_fd < 0) {
    LOGE("[SSH-BRIDGE] Unix socket: %s", strerror(errno));
    goto cleanup;
  }
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  strncpy(addr.sun_path, cfg->local_socket_path, sizeof(addr.sun_path) - 1);
  if (connect(local_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
    LOGE("[SSH-BRIDGE] Unix connect to %s: %s", cfg->local_socket_path,
         strerror(errno));
    goto cleanup;
  }
  LOGI("[SSH-BRIDGE] Connected to local waypipe socket");

  fcntl(local_fd, F_SETFL, fcntl(local_fd, F_GETFL, 0) | O_NONBLOCK);
  fcntl(ssh_stdout[0], F_SETFL, fcntl(ssh_stdout[0], F_GETFL, 0) | O_NONBLOCK);
  fcntl(ssh_stderr[0], F_SETFL, fcntl(ssh_stderr[0], F_GETFL, 0) | O_NONBLOCK);

  {
    char buf[65536];
    LOGI("[SSH-BRIDGE] Forwarding data...");

    while (!*(cfg->stop_flag)) {
      int did_work = 0;

      ssize_t n = read(local_fd, buf, sizeof(buf));
      if (n > 0) {
        did_work = 1;
        ssize_t off = 0;
        while (off < n) {
          ssize_t w = write(ssh_stdin[1], buf + off, n - off);
          if (w < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            usleep(500);
            continue;
          }
          if (w < 0) {
            LOGE("[SSH-BRIDGE] write ssh stdin: %s", strerror(errno));
            goto cleanup;
          }
          off += w;
        }
      } else if (n == 0) {
        LOGI("[SSH-BRIDGE] local socket EOF");
        break;
      } else if (errno != EAGAIN && errno != EWOULDBLOCK) {
        LOGE("[SSH-BRIDGE] read local: %s", strerror(errno));
        break;
      }

      n = read(ssh_stdout[0], buf, sizeof(buf));
      if (n > 0) {
        did_work = 1;
        ssize_t off = 0;
        while (off < n) {
          ssize_t w = write(local_fd, buf + off, n - off);
          if (w < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            usleep(500);
            continue;
          }
          if (w < 0) {
            LOGE("[SSH-BRIDGE] write local: %s", strerror(errno));
            goto cleanup;
          }
          off += w;
        }
      } else if (n == 0) {
        LOGI("[SSH-BRIDGE] SSH stdout EOF");
        break;
      } else if (errno != EAGAIN && errno != EWOULDBLOCK) {
        LOGE("[SSH-BRIDGE] read ssh stdout: %s", strerror(errno));
        break;
      }

      ssize_t en = read(ssh_stderr[0], buf, sizeof(buf) - 1);
      if (en > 0) {
        buf[en] = '\0';
        LOGI("[SSH-BRIDGE] remote stderr: %s", buf);
      }

      if (!did_work)
        usleep(1000);
    }
  }

cleanup:
  LOGI("[SSH-BRIDGE] Shutting down");
  if (ssh_stdin[1] >= 0)
    close(ssh_stdin[1]);
  if (ssh_stdout[0] >= 0)
    close(ssh_stdout[0]);
  if (ssh_stderr[0] >= 0)
    close(ssh_stderr[0]);
  if (local_fd >= 0)
    close(local_fd);
  if (ssh_pid > 0) {
    kill(ssh_pid, SIGTERM);
    int status;
    waitpid(ssh_pid, &status, 0);
    LOGI("[SSH-BRIDGE] SSH process exit status: %d", WEXITSTATUS(status));
  }
  LOGI("[SSH-BRIDGE] Thread finished");
  return NULL;
}

static void *waypipe_thread_func(void *arg) {
  (void)arg;
  resolve_ssh_binary_paths();
  LOGI("Waypipe thread started");
  LOGI("  SSH: %s", g_waypipe_config.ssh_enabled ? "enabled" : "disabled");
  if (g_waypipe_config.ssh_enabled) {
    LOGI("  Host: %s", g_waypipe_config.ssh_host);
    LOGI("  User: %s", g_waypipe_config.ssh_user);
    LOGI("  Remote Command: %s", g_waypipe_config.remote_command);
  }
  LOGI("  Compression: %s", g_waypipe_config.compress);
  LOGI("  Threads: %d", g_waypipe_config.threads);
  LOGI("  Debug: %s", g_waypipe_config.debug ? "yes" : "no");
  LOGI("  Oneshot: %s", g_waypipe_config.oneshot ? "yes" : "no");
  LOGI("  No GPU: %s", g_waypipe_config.no_gpu ? "yes" : "no");

  const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
  LOGI("XDG_RUNTIME_DIR=%s  WAYLAND_DISPLAY=%s", xdg_dir ? xdg_dir : "(null)",
       getenv("WAYLAND_DISPLAY") ? getenv("WAYLAND_DISPLAY") : "(null)");

  // Build waypipe argv
  const char *argv[32];
  int argc = 0;
  argv[argc++] = "waypipe";

  if (g_waypipe_config.compress[0]) {
    argv[argc++] = "--compress";
    argv[argc++] = g_waypipe_config.compress;
  }

  char threads_str[16];
  if (g_waypipe_config.threads > 0) {
    argv[argc++] = "--threads";
    snprintf(threads_str, sizeof(threads_str), "%d", g_waypipe_config.threads);
    argv[argc++] = threads_str;
  }

  if (g_waypipe_config.oneshot || g_waypipe_config.ssh_enabled) {
    argv[argc++] = "--oneshot";
  }

  if (g_waypipe_config.no_gpu) {
    argv[argc++] = "--no-gpu";
  }

  if (g_waypipe_config.login_shell) {
    argv[argc++] = "--login-shell";
  }

  if (g_waypipe_config.debug) {
    argv[argc++] = "--debug";
  }

  if (g_waypipe_config.title_prefix[0]) {
    argv[argc++] = "--title-prefix";
    argv[argc++] = g_waypipe_config.title_prefix;
  }

  if (g_waypipe_config.sec_ctx[0]) {
    argv[argc++] = "--secctx";
    argv[argc++] = g_waypipe_config.sec_ctx;
  }

  int result;

  if (g_waypipe_config.ssh_enabled && g_waypipe_config.ssh_host[0]) {
    // ── SSH mode ──
    // Architecture:
    //   Local:  waypipe --socket /path/wp.sock --oneshot client
    //           (creates /path/wp.sock, connects to compositor, waits for
    //           server)
    //   Remote: Python script that creates a Unix socket, starts
    //           "waypipe --socket <sock> server -- <cmd>", and bridges
    //           the socket data to SSH channel stdin/stdout.
    //   Bridge: SSH bridge thread connects to local wp.sock and forwards
    //           data to/from the SSH channel.

    // Socket path for local waypipe client
    static char wp_socket_path[512];
    snprintf(wp_socket_path, sizeof(wp_socket_path), "%s/waypipe-bridge.sock",
             xdg_dir ? xdg_dir : "/tmp");
    unlink(wp_socket_path); // remove stale

    const char *rcmd = g_waypipe_config.remote_command[0]
                           ? g_waypipe_config.remote_command
                           : "weston-terminal";

    char compress_arg[128] = "";
    if (g_waypipe_config.compress[0] &&
        strcmp(g_waypipe_config.compress, "none") != 0) {
      snprintf(compress_arg, sizeof(compress_arg), " --compress %s",
               g_waypipe_config.compress);
    }

    // Remote command: Python script that creates a Unix socket for waypipe
    // server to connect to, then bridges the socket to SSH stdin/stdout.
    // Uses heredoc so newlines are preserved correctly.
    static char remote_cmd[4096];
    snprintf(
        remote_cmd, sizeof(remote_cmd),
        "python3 << 'PYEOF'\n"
        "import socket, sys, os, threading\n"
        "sp = '/tmp/waypipe-wawona-' + str(os.getpid()) + '.sock'\n"
        "try: os.unlink(sp)\n"
        "except: pass\n"
        "s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)\n"
        "s.bind(sp)\n"
        "s.listen(1)\n"
        "os.system('waypipe -s ' + sp + '%s -o server -- \"%s\" &')\n"
        "s.settimeout(10)\n"
        "try:\n"
        "  c, _ = s.accept()\n"
        "except:\n"
        "  sys.stderr.write('waypipe server did not connect within 10s\\n')\n"
        "  os.unlink(sp)\n"
        "  sys.exit(1)\n"
        "def tx():\n"
        "  try:\n"
        "    while True:\n"
        "      d = c.recv(65536)\n"
        "      if not d: break\n"
        "      os.write(1, d)\n"
        "  except: pass\n"
        "threading.Thread(target=tx, daemon=True).start()\n"
        "try:\n"
        "  while True:\n"
        "    d = os.read(0, 65536)\n"
        "    if not d: break\n"
        "    c.sendall(d)\n"
        "except: pass\n"
        "c.close()\n"
        "s.close()\n"
        "try: os.unlink(sp)\n"
        "except: pass\n"
        "PYEOF",
        compress_arg, rcmd);

    // Set --socket for local waypipe client
    argv[argc++] = "--socket";
    argv[argc++] = wp_socket_path;
    argv[argc++] = "--debug";
    argv[argc++] = "client";
    argv[argc] = NULL;

    // Verify compositor socket before waypipe starts
    {
      const char *wl_disp = getenv("WAYLAND_DISPLAY");
      if (xdg_dir && wl_disp) {
        char comp_sock[512];
        snprintf(comp_sock, sizeof(comp_sock), "%s/%s", xdg_dir, wl_disp);
        struct stat st;
        if (stat(comp_sock, &st) == 0) {
          LOGI("Compositor socket OK: %s (mode=%o)", comp_sock, st.st_mode);
        } else {
          LOGE("Compositor socket MISSING: %s: %s", comp_sock, strerror(errno));
        }
      }
    }

    // Configure and launch SSH bridge thread
    memset(&g_ssh_bridge, 0, sizeof(g_ssh_bridge));
    g_ssh_bridge.port = 22;
    g_ssh_bridge.stop_flag = &g_waypipe_stop_requested;
    strncpy(g_ssh_bridge.host, g_waypipe_config.ssh_host,
            sizeof(g_ssh_bridge.host) - 1);
    strncpy(g_ssh_bridge.user, g_waypipe_config.ssh_user,
            sizeof(g_ssh_bridge.user) - 1);
    strncpy(g_ssh_bridge.password, g_waypipe_config.ssh_password,
            sizeof(g_ssh_bridge.password) - 1);
    strncpy(g_ssh_bridge.remote_cmd, remote_cmd,
            sizeof(g_ssh_bridge.remote_cmd) - 1);
    strncpy(g_ssh_bridge.local_socket_path, wp_socket_path,
            sizeof(g_ssh_bridge.local_socket_path) - 1);

    pthread_t ssh_tid;
    if (pthread_create(&ssh_tid, NULL, ssh_bridge_thread, &g_ssh_bridge) != 0) {
      LOGE("Failed to create SSH bridge thread");
      g_waypipe_running = 0;
      return NULL;
    }

    LOGI("Calling waypipe_main (client, socket=%s) with %d args:",
         wp_socket_path, argc);
    for (int i = 0; i < argc; i++) {
      LOGI("  argv[%d] = %s", i, argv[i]);
    }

    // Android apps can't access CWD ("/") - waypipe opens "." internally.
    // chdir to XDG_RUNTIME_DIR which the app owns.
    char saved_cwd[512] = "";
    if (xdg_dir) {
      getcwd(saved_cwd, sizeof(saved_cwd));
      if (chdir(xdg_dir) == 0) {
        LOGI("chdir to %s for waypipe", xdg_dir);
      } else {
        LOGE("chdir to %s failed: %s", xdg_dir, strerror(errno));
      }
    }

    setenv("RUST_BACKTRACE", "full", 1);

    // Capture waypipe stderr to a file (safe, non-blocking unlike pipes)
    char stderr_log[512];
    snprintf(stderr_log, sizeof(stderr_log), "%s/waypipe-stderr.log",
             xdg_dir ? xdg_dir : "/tmp");
    int log_fd = open(stderr_log, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    int saved_stderr = -1;
    if (log_fd >= 0) {
      saved_stderr = dup(STDERR_FILENO);
      dup2(log_fd, STDERR_FILENO);
      close(log_fd);
    }

    result = waypipe_main(argc, argv);

    // Restore stderr immediately
    if (saved_stderr >= 0) {
      dup2(saved_stderr, STDERR_FILENO);
      close(saved_stderr);
    }
    LOGI("waypipe_main (client) returned %d", result);

    // Read and log waypipe's stderr output
    {
      int rfd = open(stderr_log, O_RDONLY);
      if (rfd >= 0) {
        char errbuf[4096];
        ssize_t n = read(rfd, errbuf, sizeof(errbuf) - 1);
        if (n > 0) {
          errbuf[n] = '\0';
          LOGI("waypipe stderr:\n%s", errbuf);
        } else {
          LOGI("waypipe produced no stderr output");
        }
        close(rfd);
      }
    }

    // Restore CWD
    if (saved_cwd[0])
      chdir(saved_cwd);

    g_waypipe_stop_requested = 1;
    pthread_join(ssh_tid, NULL);
    unlink(wp_socket_path);

  } else {
    // Non-SSH mode - also needs chdir for the same reason
    char saved_cwd2[512] = "";
    if (xdg_dir) {
      getcwd(saved_cwd2, sizeof(saved_cwd2));
      chdir(xdg_dir);
    }
    argv[argc] = NULL;
    LOGI("Calling waypipe_main with %d args:", argc);
    for (int i = 0; i < argc; i++) {
      LOGI("  argv[%d] = %s", i, argv[i]);
    }
    result = waypipe_main(argc, argv);
    LOGI("waypipe_main returned %d", result);
    if (saved_cwd2[0])
      chdir(saved_cwd2);
  }

  g_waypipe_running = 0;
  return NULL;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWaypipe(
    JNIEnv *env, jobject thiz, jboolean sshEnabled, jstring sshHost,
    jstring sshUser, jstring sshPassword, jstring remoteCommand,
    jstring compress, jint threads, jstring video, jboolean debug,
    jboolean oneshot, jboolean noGpu, jboolean loginShell, jstring titlePrefix,
    jstring secCtx) {
  (void)thiz;

  if (g_waypipe_running) {
    LOGE("Waypipe is already running");
    return JNI_FALSE;
  }

  memset(&g_waypipe_config, 0, sizeof(g_waypipe_config));
  g_waypipe_config.ssh_enabled = sshEnabled;
  g_waypipe_config.threads = threads;
  g_waypipe_config.debug = debug;
  g_waypipe_config.oneshot = oneshot;
  g_waypipe_config.no_gpu = noGpu;
  g_waypipe_config.login_shell = loginShell;

  const char *str;

  str = (*env)->GetStringUTFChars(env, sshHost, NULL);
  if (str) {
    strncpy(g_waypipe_config.ssh_host, str,
            sizeof(g_waypipe_config.ssh_host) - 1);
    (*env)->ReleaseStringUTFChars(env, sshHost, str);
  }

  str = (*env)->GetStringUTFChars(env, sshUser, NULL);
  if (str) {
    strncpy(g_waypipe_config.ssh_user, str,
            sizeof(g_waypipe_config.ssh_user) - 1);
    (*env)->ReleaseStringUTFChars(env, sshUser, str);
  }

  str = (*env)->GetStringUTFChars(env, sshPassword, NULL);
  if (str) {
    strncpy(g_waypipe_config.ssh_password, str,
            sizeof(g_waypipe_config.ssh_password) - 1);
    (*env)->ReleaseStringUTFChars(env, sshPassword, str);
  }

  str = (*env)->GetStringUTFChars(env, remoteCommand, NULL);
  if (str) {
    strncpy(g_waypipe_config.remote_command, str,
            sizeof(g_waypipe_config.remote_command) - 1);
    (*env)->ReleaseStringUTFChars(env, remoteCommand, str);
  }

  str = (*env)->GetStringUTFChars(env, compress, NULL);
  if (str) {
    strncpy(g_waypipe_config.compress, str,
            sizeof(g_waypipe_config.compress) - 1);
    (*env)->ReleaseStringUTFChars(env, compress, str);
  }

  str = (*env)->GetStringUTFChars(env, video, NULL);
  if (str) {
    strncpy(g_waypipe_config.video, str, sizeof(g_waypipe_config.video) - 1);
    (*env)->ReleaseStringUTFChars(env, video, str);
  }

  str = (*env)->GetStringUTFChars(env, titlePrefix, NULL);
  if (str) {
    strncpy(g_waypipe_config.title_prefix, str,
            sizeof(g_waypipe_config.title_prefix) - 1);
    (*env)->ReleaseStringUTFChars(env, titlePrefix, str);
  }

  str = (*env)->GetStringUTFChars(env, secCtx, NULL);
  if (str) {
    strncpy(g_waypipe_config.sec_ctx, str,
            sizeof(g_waypipe_config.sec_ctx) - 1);
    (*env)->ReleaseStringUTFChars(env, secCtx, str);
  }

  g_waypipe_stop_requested = 0;
  g_waypipe_running = 1;

  int result =
      pthread_create(&g_waypipe_thread, NULL, waypipe_thread_func, NULL);
  if (result != 0) {
    LOGE("Failed to create waypipe thread: %d", result);
    g_waypipe_running = 0;
    return JNI_FALSE;
  }

  LOGI("Waypipe launched successfully");
  return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWaypipe(JNIEnv *env,
                                                              jobject thiz) {
  (void)env;
  (void)thiz;

  if (!g_waypipe_running) {
    LOGI("Waypipe is not running");
    return;
  }

  LOGI("Stopping waypipe...");
  g_waypipe_stop_requested = 1;

  if (g_waypipe_thread) {
    pthread_join(g_waypipe_thread, NULL);
    g_waypipe_thread = 0;
  }

  g_waypipe_running = 0;
  LOGI("Waypipe stopped");
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWaypipeRunning(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  return g_waypipe_running ? JNI_TRUE : JNI_FALSE;
}

// ============================================================================
// Weston Simple SHM execution
// ============================================================================

static int g_weston_shm_running = 0;
static pthread_t g_weston_shm_thread = 0;

static void *weston_simple_shm_thread_func(void *arg) {
  (void)arg;
  LOGI("Starting weston-simple-shm background thread");

  const char *argv[] = {"weston-simple-shm", NULL};
  int argc = 1;

  char saved_cwd[512] = "";
  const char *xdg_dir = getenv("XDG_RUNTIME_DIR");
  if (xdg_dir) {
    getcwd(saved_cwd, sizeof(saved_cwd));
    chdir(xdg_dir);
  }

  int result = weston_simple_shm_main(argc, argv);
  LOGI("weston-simple-shm returned %d", result);

  if (saved_cwd[0])
    chdir(saved_cwd);

  g_weston_shm_running = 0;
  return NULL;
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeRunWestonSimpleSHM(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;

  if (g_weston_shm_running) {
    LOGE("weston-simple-shm is already running");
    return JNI_FALSE;
  }

  g_weston_shm_running = 1;

  int result = pthread_create(&g_weston_shm_thread, NULL,
                              weston_simple_shm_thread_func, NULL);
  if (result != 0) {
    LOGE("Failed to create weston-simple-shm thread: %d", result);
    g_weston_shm_running = 0;
    return JNI_FALSE;
  }

  LOGI("weston-simple-shm launched successfully");
  return JNI_TRUE;
}

JNIEXPORT void JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeStopWestonSimpleSHM(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;

  if (!g_weston_shm_running) {
    LOGI("weston-simple-shm is not running");
    return;
  }

  LOGI("Stopping weston-simple-shm...");

  // There is no clean way to stop it currently, as it runs wl_display_dispatch
  // forever. In a future update, we can implement a stop signal, but for now we
  // let it detach or fail.
  if (g_weston_shm_thread) {
    g_weston_shm_thread = 0;
  }

  g_weston_shm_running = 0;
  LOGI("weston-simple-shm stopped");
}

JNIEXPORT jboolean JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeIsWestonSimpleSHMRunning(
    JNIEnv *env, jobject thiz) {
  (void)env;
  (void)thiz;
  return g_weston_shm_running ? JNI_TRUE : JNI_FALSE;
}

// ---------------------------------------------------------------------------
// Test Ping: TCP connect to host:port, measure latency
// ---------------------------------------------------------------------------
#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <sys/time.h>

JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTestPing(JNIEnv *, jobject,
                                                           jstring, jint, jint);
JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTestPing(
    JNIEnv *env, jobject thiz, jstring host, jint port, jint timeoutMs) {
  (void)thiz;
  const char *host_str = (*env)->GetStringUTFChars(env, host, NULL);
  char result[1024];
  char port_str[16];
  snprintf(port_str, sizeof(port_str), "%d", port);

  LOGI("Testing TCP connectivity to %s:%d (timeout %dms)", host_str, port,
       timeoutMs);

  struct addrinfo hints = {0}, *res = NULL;
  hints.ai_family = AF_UNSPEC;
  hints.ai_socktype = SOCK_STREAM;

  int rc = getaddrinfo(host_str, port_str, &hints, &res);
  if (rc != 0) {
    snprintf(result, sizeof(result), "FAIL: DNS resolution failed for '%s': %s",
             host_str, gai_strerror(rc));
    LOGE("Ping test failed: %s", result);
    (*env)->ReleaseStringUTFChars(env, host, host_str);
    return (*env)->NewStringUTF(env, result);
  }

  int sock = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
  if (sock < 0) {
    snprintf(result, sizeof(result), "FAIL: Could not create socket: %s",
             strerror(errno));
    freeaddrinfo(res);
    (*env)->ReleaseStringUTFChars(env, host, host_str);
    return (*env)->NewStringUTF(env, result);
  }

  struct timeval tv;
  tv.tv_sec = timeoutMs / 1000;
  tv.tv_usec = (timeoutMs % 1000) * 1000;
  setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
  setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));

  struct timeval t_start, t_end;
  gettimeofday(&t_start, NULL);
  rc = connect(sock, res->ai_addr, res->ai_addrlen);
  gettimeofday(&t_end, NULL);

  long latency_ms = (t_end.tv_sec - t_start.tv_sec) * 1000 +
                    (t_end.tv_usec - t_start.tv_usec) / 1000;

  if (rc != 0) {
    snprintf(result, sizeof(result), "FAIL: TCP connect to %s:%d failed: %s",
             host_str, port, strerror(errno));
    LOGE("Ping test: %s", result);
    close(sock);
    freeaddrinfo(res);
    (*env)->ReleaseStringUTFChars(env, host, host_str);
    return (*env)->NewStringUTF(env, result);
  }

  char banner[256] = {0};
  ssize_t n = recv(sock, banner, sizeof(banner) - 1, 0);
  if (n > 0) {
    banner[n] = '\0';
    char *nl = strchr(banner, '\n');
    if (nl)
      *nl = '\0';
    char *cr = strchr(banner, '\r');
    if (cr)
      *cr = '\0';
  }

  close(sock);
  freeaddrinfo(res);

  if (n > 0 && banner[0]) {
    snprintf(result, sizeof(result), "OK: %s:%d reachable (%ldms)\nServer: %s",
             host_str, port, latency_ms, banner);
  } else {
    snprintf(result, sizeof(result), "OK: %s:%d reachable (%ldms)", host_str,
             port, latency_ms);
  }
  LOGI("Ping test: %s", result);
  (*env)->ReleaseStringUTFChars(env, host, host_str);
  return (*env)->NewStringUTF(env, result);
}

// ---------------------------------------------------------------------------
// Test SSH: OpenSSH-based connection + auth test via fork/exec
// ---------------------------------------------------------------------------
#include <poll.h>

JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTestSSH(JNIEnv *, jobject,
                                                          jstring, jstring,
                                                          jstring, jint);
JNIEXPORT jstring JNICALL
Java_com_aspauldingcode_wawona_WawonaNative_nativeTestSSH(
    JNIEnv *env, jobject thiz, jstring host, jstring user, jstring password,
    jint port) {
  (void)thiz;
  const char *host_str = (*env)->GetStringUTFChars(env, host, NULL);
  const char *user_str = (*env)->GetStringUTFChars(env, user, NULL);
  const char *pass_str = (*env)->GetStringUTFChars(env, password, NULL);
  char result[2048];
  char port_str[16];
  snprintf(port_str, sizeof(port_str), "%d", port);

  LOGI("Testing SSH connection to %s@%s:%d (OpenSSH)", user_str, host_str,
       port);

  resolve_ssh_binary_paths();

  if (!g_ssh_bin_path[0]) {
    snprintf(result, sizeof(result),
             "FAIL: SSH binary not found in native lib directory");
    goto cleanup_strings;
  }

  struct timeval t_start, t_end;
  gettimeofday(&t_start, NULL);

  int out_pipe[2];
  if (pipe(out_pipe) < 0) {
    snprintf(result, sizeof(result), "FAIL: pipe() failed: %s",
             strerror(errno));
    goto cleanup_strings;
  }

  pid_t pid = fork();
  if (pid < 0) {
    snprintf(result, sizeof(result), "FAIL: fork() failed: %s",
             strerror(errno));
    close(out_pipe[0]);
    close(out_pipe[1]);
    goto cleanup_strings;
  }

  if (pid == 0) {
    close(out_pipe[0]);
    dup2(out_pipe[1], STDOUT_FILENO);
    dup2(out_pipe[1], STDERR_FILENO);
    close(out_pipe[1]);

    if (pass_str[0] != '\0') {
      setenv("SSHPASS", pass_str, 1);
    }

    /* Dropbear (dbclient) bundled as ssh: -y auto-accept host key */
    execl(g_ssh_bin_path, "ssh", "-y", "-T", "-p", port_str, "-l", user_str,
          host_str, "uname -a", (char *)NULL);

    fprintf(stderr, "exec failed: %s (path=%s)\n", strerror(errno),
            g_ssh_bin_path);
    _exit(127);
  }

  close(out_pipe[1]);

  char uname_buf[512] = {0};
  int total = 0;
  struct pollfd pf = {out_pipe[0], POLLIN, 0};
  while (total < (int)sizeof(uname_buf) - 1) {
    int pr = poll(&pf, 1, 15000);
    if (pr <= 0)
      break;
    ssize_t n =
        read(out_pipe[0], uname_buf + total, sizeof(uname_buf) - 1 - total);
    if (n <= 0)
      break;
    total += (int)n;
  }
  close(out_pipe[0]);
  uname_buf[total] = '\0';

  int status;
  waitpid(pid, &status, 0);

  gettimeofday(&t_end, NULL);
  long latency_ms = (t_end.tv_sec - t_start.tv_sec) * 1000 +
                    (t_end.tv_usec - t_start.tv_usec) / 1000;

  if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
    char *nl = strchr(uname_buf, '\n');
    if (nl)
      *nl = '\0';
    snprintf(result, sizeof(result),
             "OK: SSH connected and authenticated (OpenSSH)\nRemote: "
             "%s\nLatency: %ldms",
             uname_buf, latency_ms);
  } else {
    snprintf(result, sizeof(result),
             "FAIL: SSH failed (exit %d)\nOutput: %s\nLatency: %ldms",
             WIFEXITED(status) ? WEXITSTATUS(status) : -1, uname_buf,
             latency_ms);
  }

cleanup_strings:
  LOGI("SSH test result: %s", result);
  (*env)->ReleaseStringUTFChars(env, host, host_str);
  (*env)->ReleaseStringUTFChars(env, user, user_str);
  (*env)->ReleaseStringUTFChars(env, password, pass_str);
  return (*env)->NewStringUTF(env, result);
}

// ---------------------------------------------------------------------------

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM *vm, void *reserved) {
  // Redirect stdout/stderr to logcat
  setvbuf(stdout, 0, _IOLBF, 0);
  setvbuf(stderr, 0, _IONBF, 0);
  pipe(pfd);
  dup2(pfd[1], 1);
  dup2(pfd[1], 2);
  if (pthread_create(&thr, 0, thread_func, 0) == -1)
    return -1;
  pthread_detach(thr);

  return JNI_VERSION_1_6;
}
