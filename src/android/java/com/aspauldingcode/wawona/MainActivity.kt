package com.aspauldingcode.wawona

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.WindowInsetsController
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.core.view.ViewCompat
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

class MainActivity : ComponentActivity(), SurfaceHolder.Callback {

    private lateinit var prefs: SharedPreferences
    
    companion object {
        private const val TAG = "Wawona"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "onCreate started")
        
        try {
        
            // Hide UI using modern WindowInsetsController API (API 30+)
            Log.d(TAG, "Setting up window insets")
            WindowCompat.setDecorFitsSystemWindows(window, false)

            // Listen for safe area insets (cutouts, notches, system bars)
            ViewCompat.setOnApplyWindowInsetsListener(window.decorView) { _, insets ->
                val displayCutout = insets.displayCutout
                val systemBars = insets.getInsets(WindowInsetsCompat.Type.systemBars())
                
                // Calculate max insets from cutout and system bars to ensure we respect all safe areas
                val left = maxOf(displayCutout?.safeInsetLeft ?: 0, systemBars.left)
                val top = maxOf(displayCutout?.safeInsetTop ?: 0, systemBars.top)
                val right = maxOf(displayCutout?.safeInsetRight ?: 0, systemBars.right)
                val bottom = maxOf(displayCutout?.safeInsetBottom ?: 0, systemBars.bottom)
                
                Log.d(TAG, "Updating native safe area: L=$left, T=$top, R=$right, B=$bottom")
                try {
                    WawonaNative.nativeUpdateSafeArea(left, top, right, bottom)
                } catch (e: Exception) {
                    Log.e(TAG, "Error updating native safe area", e)
                }
                
                insets
            }

            val windowInsetsController = WindowCompat.getInsetsController(window, window.decorView)
            windowInsetsController?.let { controller ->
                controller.hide(androidx.core.view.WindowInsetsCompat.Type.systemBars())
                controller.systemBarsBehavior = 
                    WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
            
            // Fallback for older APIs (though we target API 36, this is defensive)
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = (
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                    android.view.View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    android.view.View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                    android.view.View.SYSTEM_UI_FLAG_FULLSCREEN or
                    android.view.View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                )
            }

            Log.d(TAG, "Loading preferences")
            prefs = getSharedPreferences("wawona_prefs", Context.MODE_PRIVATE)

            Log.d(TAG, "Setting up Compose content")
            setContent {
                // Material 3 Expressive: Use dynamic colors on Android 12+ (API 31+)
                val colorScheme = remember {
                    try {
                        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                            Log.d(TAG, "Using dynamic color scheme")
                            dynamicLightColorScheme(this@MainActivity)
                        } else {
                            Log.d(TAG, "Using fallback color scheme")
                            // Fallback to seed-based light color scheme
                            lightColorScheme(
                                primary = Color(0xFF6750A4),
                                secondary = Color(0xFF625B71),
                                tertiary = Color(0xFF7D5260),
                                primaryContainer = Color(0xFFEADDFF),
                                onPrimaryContainer = Color(0xFF21005D)
                            )
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error creating color scheme", e)
                        lightColorScheme(
                            primary = Color(0xFF6750A4),
                            secondary = Color(0xFF625B71),
                            tertiary = Color(0xFF7D5260),
                            primaryContainer = Color(0xFFEADDFF),
                            onPrimaryContainer = Color(0xFF21005D)
                        )
                    }
                }
            
            // Material 3 Expressive typography: tighter letter spacing for expressive design
            val expressiveTypography = MaterialTheme.typography.copy(
                displayLarge = MaterialTheme.typography.displayLarge.copy(
                    letterSpacing = (-0.01).sp
                ),
                displayMedium = MaterialTheme.typography.displayMedium.copy(
                    letterSpacing = (-0.01).sp
                ),
                displaySmall = MaterialTheme.typography.displaySmall.copy(
                    letterSpacing = (-0.01).sp
                ),
                headlineLarge = MaterialTheme.typography.headlineLarge.copy(
                    letterSpacing = (-0.01).sp
                ),
                headlineMedium = MaterialTheme.typography.headlineMedium.copy(
                    letterSpacing = (-0.01).sp
                ),
                headlineSmall = MaterialTheme.typography.headlineSmall.copy(
                    letterSpacing = (-0.01).sp
                )
            )
            
            MaterialTheme(
                colorScheme = colorScheme,
                typography = expressiveTypography
            ) {
                // Background container with specific color for safe area letterboxing
                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .background(Color(24, 24, 49)) // rgb(24, 24, 49)
                ) {
                    // Wawona Rendering Surface
                    // Respect Safe Area logic: Apply padding if enabled
                    val respectSafeArea = prefs.getBoolean("respectSafeArea", true)
                    
                    AndroidView(
                        factory = { context ->
                            SurfaceView(context).apply {
                                holder.addCallback(this@MainActivity)
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
                    
                    // Expressive FAB Menu
                    var showSettings by remember { mutableStateOf(false) }
                    
                    ExpressiveFabMenu(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .padding(24.dp),
                        onSettingsClick = { showSettings = true }
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
            }
            
            Log.d(TAG, "Calling nativeInit")
            try {
                WawonaNative.nativeInit()
                Log.d(TAG, "nativeInit completed successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Error in nativeInit", e)
                throw e
            }
        } catch (e: Exception) {
            Log.e(TAG, "Fatal error in onCreate", e)
            throw e
        }
        Log.d(TAG, "onCreate completed")
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
        Log.d(TAG, "surfaceCreated")
        try {
            WawonaNative.nativeSetSurface(holder.surface)
            Log.d(TAG, "nativeSetSurface completed")
            WawonaSettings.apply(prefs)
            Log.d(TAG, "Settings applied")
        } catch (e: Exception) {
            Log.e(TAG, "Error in surfaceCreated", e)
        }
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        Log.d(TAG, "surfaceChanged: format=$format, width=$width, height=$height")
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        Log.d(TAG, "surfaceDestroyed")
        try {
            WawonaNative.nativeDestroySurface()
            Log.d(TAG, "nativeDestroySurface completed")
        } catch (e: Exception) {
            Log.e(TAG, "Error in surfaceDestroyed", e)
        }
    }
}
