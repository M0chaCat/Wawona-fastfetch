#!/bin/bash

set -e
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${ROOT_DIR}/build/android-app"
PKG="com.aspauldingcode.wawona"
PKG_PATH=$(echo "${PKG}" | tr . /)

mkdir -p "${APP_DIR}"

cat > "${APP_DIR}/settings.gradle" <<EOF
include ':app'
EOF

cat > "${APP_DIR}/build.gradle" <<EOF
buildscript {
    repositories { google(); mavenCentral() }
    dependencies { classpath 'com.android.tools.build:gradle:8.5.2' }
}
allprojects { repositories { google(); mavenCentral() } }
EOF

mkdir -p "${APP_DIR}/app/src/main/java/${PKG_PATH}" "${APP_DIR}/app/src/main/cpp" "${APP_DIR}/app/src/main/res/layout" "${APP_DIR}/app/src/main"

cat > "${APP_DIR}/app/build.gradle" <<EOF
plugins { id 'com.android.application' }
android {
    namespace '${PKG}'
    compileSdk 35
    defaultConfig {
        applicationId '${PKG}'
        minSdk 26
        targetSdk 35
        versionCode 1
        versionName '1.0'
        ndk { abiFilters 'arm64-v8a' }
        externalNativeBuild { cmake { cppFlags '-std=c++17' } }
    }
    buildTypes {
        debug { debuggable true }
        release { minifyEnabled false }
    }
    externalNativeBuild { cmake { path 'src/main/cpp/CMakeLists.txt' } }
}
dependencies { }
EOF

cat > "${APP_DIR}/app/src/main/AndroidManifest.xml" <<EOF
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
  <application android:label="Wawona">
    <activity android:name=".MainActivity" android:exported="true">
      <intent-filter>
        <action android:name="android.intent.action.MAIN" />
        <category android:name="android.intent.category.LAUNCHER" />
      </intent-filter>
    </activity>
  </application>
</manifest>
EOF

cat > "${APP_DIR}/app/src/main/java/${PKG_PATH}/MainActivity.java" <<'EOF'
package com.aspauldingcode.wawona;
import android.app.Activity;
import android.os.Bundle;
import android.view.SurfaceView;
import android.view.SurfaceHolder;
public class MainActivity extends Activity {
  static { System.loadLibrary("wawona"); }
  private native void nativeInit();
  private native void nativeSetSurface(Object surface);
  @Override protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    SurfaceView sv = new SurfaceView(this);
    sv.getHolder().addCallback(new SurfaceHolder.Callback() {
      public void surfaceCreated(SurfaceHolder h) { nativeSetSurface(h.getSurface()); }
      public void surfaceChanged(SurfaceHolder h,int f,int w,int h2) {}
      public void surfaceDestroyed(SurfaceHolder h) {}
    });
    setContentView(sv);
    nativeInit();
  }
}
EOF

cat > "${APP_DIR}/app/src/main/cpp/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.22.1)
project(wawona_native)
add_library(wawona SHARED ${CMAKE_SOURCE_DIR}/android_jni.c)
find_library(vulkan-lib vulkan)
target_link_libraries(wawona android log ${vulkan-lib})
EOF

cp "${ROOT_DIR}/src/android_jni.c" "${APP_DIR}/app/src/main/cpp/android_jni.c"

cat > "${APP_DIR}/gradle.properties" <<EOF
org.gradle.warning.mode=none
android.suppressUnsupportedCompileSdk=35
org.gradle.configuration-cache=true
org.gradle.configuration-cache.problems=warn
org.gradle.configuration-cache.parallel=true
EOF

cat > "${APP_DIR}/local.properties" <<EOF
sdk.dir=${HOME}/Library/Android/sdk
EOF

if [ ! -f "${APP_DIR}/gradlew" ]; then (cd "${APP_DIR}" && gradle wrapper); fi
echo "Android app created under ${APP_DIR}"
