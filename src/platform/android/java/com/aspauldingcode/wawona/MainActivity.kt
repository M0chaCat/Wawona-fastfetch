package com.aspauldingcode.wawona

import android.content.Context
import android.content.SharedPreferences
import android.os.Bundle
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowInsetsController
import android.widget.Toast
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity(), SurfaceHolder.Callback {

    private lateinit var prefs: SharedPreferences

    companion object {
        val CompositorBackground = Color(0xFF0F1018)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        WLog.d("ACTIVITY", "onCreate started")

        try {
            WindowCompat.setDecorFitsSystemWindows(window, false)

            ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { _, insets ->
                val displayCutout = insets.displayCutout
                val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())

                val left = maxOf(displayCutout?.safeInsetLeft ?: 0, systemBars.left)
                val top = maxOf(displayCutout?.safeInsetTop ?: 0, systemBars.top)
                val right = maxOf(displayCutout?.safeInsetRight ?: 0, systemBars.right)
                val bottom = maxOf(displayCutout?.safeInsetBottom ?: 0, systemBars.bottom)

                try {
                    WawonaNative.nativeUpdateSafeArea(left, top, right, bottom)
                } catch (e: Exception) {
                    WLog.e("ACTIVITY", "Error updating native safe area: ${e.message}")
                }

                insets
            }

            val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
            windowInsetsController.let { controller ->
                controller.hide(WindowInsetsCompat.Type.systemBars())
                controller.systemBarsBehavior =
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }

            prefs = getSharedPreferences("wawona_prefs", Context.MODE_PRIVATE)

            setContent {
                WawonaTheme(darkTheme = true) {
                    WawonaApp(
                        prefs = prefs,
                        surfaceCallback = this@MainActivity
                    )
                }
            }

            WawonaNative.nativeInit()
            WLog.d("ACTIVITY", "nativeInit completed successfully")
        } catch (e: Exception) {
            WLog.e("ACTIVITY", "Fatal error in onCreate: ${e.message}")
            throw e
        }
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        WLog.d("SURFACE", "surfaceCreated")
        try {
            WawonaNative.nativeSetSurface(holder.surface)
            WawonaSettings.apply(prefs)
        } catch (e: Exception) {
            WLog.e("SURFACE", "Error in surfaceCreated: ${e.message}")
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        WLog.d("SURFACE", "surfaceChanged: format=$format, width=$width, height=$height")
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        WLog.d("SURFACE", "surfaceDestroyed")
        try {
            WawonaNative.nativeDestroySurface()
        } catch (e: Exception) {
            WLog.e("SURFACE", "Error in surfaceDestroyed: ${e.message}")
        }
    }
}

@Composable
fun WawonaApp(
    prefs: SharedPreferences,
    surfaceCallback: SurfaceHolder.Callback
) {
    var showSettings by remember { mutableStateOf(false) }
    var isWaypipeRunning by remember { mutableStateOf(false) }
    var windowTitle by remember { mutableStateOf("") }
    val respectSafeArea = prefs.getBoolean("respectSafeArea", true)
    val context = LocalContext.current

    val activity = context as? ComponentActivity
    
    val westonEnabled = prefs.getBoolean("westonSimpleSHMEnabled", false)
    LaunchedEffect(westonEnabled) {
        if (westonEnabled && !WawonaNative.nativeIsWestonSimpleSHMRunning()) {
            WawonaNative.nativeRunWestonSimpleSHM()
        } else if (!westonEnabled && WawonaNative.nativeIsWestonSimpleSHMRunning()) {
            WawonaNative.nativeStopWestonSimpleSHM()
        }
    }

    LaunchedEffect(Unit) {
        while (true) {
            try {
                isWaypipeRunning = WawonaNative.nativeIsWaypipeRunning()
                windowTitle = WawonaNative.nativeGetFocusedWindowTitle()
                ScreencopyHelper.pollAndCapture(activity?.window)
            } catch (_: Exception) { }
            delay(500)
        }
    }

    val wpSshEnabled = prefs.getBoolean("waypipeSSHEnabled", true)
    val wpSshHost = prefs.getString("waypipeSSHHost", "") ?: ""
    val wpSshUser = prefs.getString("waypipeSSHUser", "") ?: ""
    val wpRemoteCommand = prefs.getString("waypipeRemoteCommand", "") ?: ""

    fun launchWaypipe() {
        val sshPassword = prefs.getString("waypipeSSHPassword", "") ?: ""
        val remoteCmd = wpRemoteCommand.ifEmpty { "weston-terminal" }
        val compress = prefs.getString("waypipeCompress", "lz4") ?: "lz4"
        val threads = (prefs.getString("waypipeThreads", "0") ?: "0").toIntOrNull() ?: 0
        val video = prefs.getString("waypipeVideo", "none") ?: "none"
        val debug = prefs.getBoolean("waypipeDebug", false)
        val oneshot = prefs.getBoolean("waypipeOneshot", false)
        val noGpu = prefs.getBoolean("waypipeDisableGpu", false)
        val loginShell = prefs.getBoolean("waypipeLoginShell", false)
        val titlePrefix = prefs.getString("waypipeTitlePrefix", "") ?: ""
        val secCtx = prefs.getString("waypipeSecCtx", "") ?: ""

        try {
            val launched = WawonaNative.nativeRunWaypipe(
                wpSshEnabled, wpSshHost, wpSshUser, sshPassword,
                remoteCmd, compress, threads, video,
                debug, oneshot || wpSshEnabled, noGpu,
                loginShell, titlePrefix, secCtx
            )
            if (launched) {
                isWaypipeRunning = true
                WLog.i("WAYPIPE", "Waypipe launched (ssh=$wpSshEnabled, host=$wpSshHost)")
            } else {
                Toast.makeText(context, "Waypipe is already running", Toast.LENGTH_SHORT).show()
            }
        } catch (e: Exception) {
            WLog.e("WAYPIPE", "Error starting waypipe: ${e.message}")
            Toast.makeText(context, "Error: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    fun stopWaypipe() {
        try {
            WawonaNative.nativeStopWaypipe()
            isWaypipeRunning = false
            WLog.i("WAYPIPE", "Waypipe stopped")
        } catch (e: Exception) {
            WLog.e("WAYPIPE", "Error stopping waypipe: ${e.message}")
            Toast.makeText(context, "Error: ${e.message}", Toast.LENGTH_SHORT).show()
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MainActivity.CompositorBackground)
    ) {
        AndroidView(
            factory = { ctx: Context ->
                WawonaSurfaceView(ctx).apply {
                    holder.addCallback(surfaceCallback)
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .then(
                    if (respectSafeArea) {
                        Modifier.windowInsetsPadding(WindowInsets.safeDrawing)
                    } else {
                        Modifier
                    }
                )
        )

        WaypipeStatusBanner(
            isRunning = isWaypipeRunning,
            sshEnabled = wpSshEnabled,
            sshHost = wpSshHost,
            sshUser = wpSshUser,
            remoteCommand = wpRemoteCommand,
            windowTitle = windowTitle,
            onStopClick = { stopWaypipe() },
            modifier = Modifier
                .align(Alignment.TopCenter)
                .windowInsetsPadding(WindowInsets.safeDrawing)
        )

        ExpressiveFabMenu(
            modifier = Modifier
                .align(Alignment.BottomEnd)
                .windowInsetsPadding(WindowInsets.safeDrawing)
                .padding(24.dp),
            isWaypipeRunning = isWaypipeRunning,
            onSettingsClick = { showSettings = true },
            onRunWaypipeClick = { launchWaypipe() },
            onStopWaypipeClick = { stopWaypipe() }
        )

        if (showSettings) {
            SettingsDialog(
                prefs = prefs,
                onDismiss = { showSettings = false },
                onApply = { WawonaSettings.apply(prefs) }
            )
        }
    }
}
