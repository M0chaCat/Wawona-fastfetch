package com.aspauldingcode.wawona;

import android.app.Activity;
import android.os.Bundle;
import android.view.Surface;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.WindowManager;

public class MainActivity extends Activity implements SurfaceHolder.Callback {

    static {
        System.loadLibrary("wawona");
    }

    private native void nativeInit();
    private native void nativeSetSurface(Surface surface);
    private native void nativeDestroySurface();
    // Optional settings API
    private native void nativeApplySettings(boolean forceServerSideDecorations,
                                          boolean autoRetinaScaling,
                                          int renderingBackend,
                                          boolean respectSafeArea,
                                          boolean renderMacOSPointer,
                                          boolean swapCmdAsCtrl,
                                          boolean universalClipboard,
                                          boolean colorSyncSupport,
                                          boolean nestedCompositorsSupport,
                                          boolean useMetal4ForNested,
                                          boolean multipleClients,
                                          boolean waypipeRSSupport,
                                          boolean enableTCPListener,
                                          int tcpPort);

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Fullscreen mode
        getWindow().setFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN,
                WindowManager.LayoutParams.FLAG_FULLSCREEN);
        
        // Hide navigation bar (immersive sticky)
        getWindow().getDecorView().setSystemUiVisibility(
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                | View.SYSTEM_UI_FLAG_FULLSCREEN
                | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);

        SurfaceView surfaceView = new SurfaceView(this);
        surfaceView.getHolder().addCallback(this);
        setContentView(surfaceView);

        nativeInit();
    }

    @Override
    public void surfaceCreated(SurfaceHolder holder) {
        // Native code handles surface creation
    }

    @Override
    public void surfaceChanged(SurfaceHolder holder, int format, int width, int height) {
        nativeSetSurface(holder.getSurface());
    }

    @Override
    public void surfaceDestroyed(SurfaceHolder holder) {
        nativeDestroySurface();
    }
}
