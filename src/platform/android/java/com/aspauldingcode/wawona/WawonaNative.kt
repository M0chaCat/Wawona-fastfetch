package com.aspauldingcode.wawona

import android.view.Surface

object WawonaNative {
    init {
        try {
            WLog.d("NATIVE", "Loading native library 'wawona'")
            System.loadLibrary("wawona")
            WLog.d("NATIVE", "Native library 'wawona' loaded successfully")
        } catch (e: UnsatisfiedLinkError) {
            WLog.e("NATIVE", "Failed to load native library 'wawona': ${e.message}")
            throw e
        } catch (e: Exception) {
            WLog.e("NATIVE", "Unexpected error loading native library: ${e.message}")
            throw e
        }
    }

    external fun nativeInit()
    external fun nativeSetSurface(surface: Surface)
    external fun nativeDestroySurface()
    external fun nativeUpdateSafeArea(left: Int, top: Int, right: Int, bottom: Int)
    external fun nativeApplySettings(
        forceServerSideDecorations: Boolean,
        autoRetinaScaling: Boolean,
        renderingBackend: Int,
        respectSafeArea: Boolean,
        renderMacOSPointer: Boolean,
        swapCmdAsCtrl: Boolean,
        universalClipboard: Boolean,
        colorSyncSupport: Boolean,
        nestedCompositorsSupport: Boolean,
        useMetal4ForNested: Boolean,
        multipleClients: Boolean,
        waypipeRSSupport: Boolean,
        enableTCPListener: Boolean,
        tcpPort: Int,
        vulkanDriver: String,
        openglDriver: String
    )

    external fun nativeSetCore(corePtr: Long)

    external fun nativeCommitText(text: String)
    external fun nativePreeditText(text: String, cursorBegin: Int, cursorEnd: Int)
    external fun nativeDeleteSurroundingText(beforeLength: Int, afterLength: Int)

    external fun nativeGetCursorRect(outRect: IntArray)

    external fun nativeTouchDown(id: Int, x: Float, y: Float, timestampMs: Int)
    external fun nativeTouchUp(id: Int, timestampMs: Int)
    external fun nativeTouchMotion(id: Int, x: Float, y: Float, timestampMs: Int)
    external fun nativeTouchCancel()
    external fun nativeTouchFrame()

    external fun nativeKeyEvent(keycode: Int, state: Int, timestampMs: Int)
    external fun nativePointerAxis(axis: Int, value: Float, timestampMs: Int)
    external fun nativePointerMotion(x: Double, y: Double, timestampMs: Int)
    external fun nativePointerButton(buttonCode: Int, state: Int, timestampMs: Int)
    external fun nativePointerEnter(x: Double, y: Double, timestampMs: Int)
    external fun nativePointerLeave(timestampMs: Int)
    external fun nativeKeyboardFocus(hasFocus: Boolean)
    external fun nativeGetFocusedWindowTitle(): String
    /** Returns capture_id if pending, else 0. Fills outWidthHeight with [width, height]. */
    external fun nativeGetPendingScreencopy(outWidthHeight: IntArray): Long
    external fun nativeScreencopyComplete(captureId: Long, pixels: ByteArray)
    external fun nativeScreencopyFailed(captureId: Long)
    external fun nativeGetPendingImageCopyCapture(outWidthHeight: IntArray): Long
    external fun nativeImageCopyCaptureComplete(captureId: Long, pixels: ByteArray)
    external fun nativeImageCopyCaptureFailed(captureId: Long)

    external fun nativeRunWaypipe(
        sshEnabled: Boolean,
        sshHost: String,
        sshUser: String,
        sshPassword: String,
        remoteCommand: String,
        compress: String,
        threads: Int,
        video: String,
        debug: Boolean,
        oneshot: Boolean,
        noGpu: Boolean,
        loginShell: Boolean,
        titlePrefix: String,
        secCtx: String
    ): Boolean

    external fun nativeStopWaypipe()
    external fun nativeIsWaypipeRunning(): Boolean

    external fun nativeRunWestonSimpleSHM(): Boolean
    external fun nativeStopWestonSimpleSHM()
    external fun nativeIsWestonSimpleSHMRunning(): Boolean

    external fun nativeTestPing(host: String, port: Int, timeoutMs: Int): String
    external fun nativeTestSSH(host: String, user: String, password: String, port: Int): String
}
