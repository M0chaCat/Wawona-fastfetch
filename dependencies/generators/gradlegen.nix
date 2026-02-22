{ pkgs, stdenv, lib, wawonaAndroidProject ? null, wawonaSrc ? null }:

let
  buildGradle = pkgs.writeText "build.gradle.kts" ''
    buildscript {
        repositories {
            google()
            mavenCentral()
            maven { url = uri("https://dl.google.com/dl/android/maven2/") }
        }
        dependencies {
            classpath("com.android.tools.build:gradle:8.10.0")
            classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.0.21")
        }
    }

    plugins {
        id("com.android.application") version "8.10.0"
        id("org.jetbrains.kotlin.android") version "2.0.21"
        id("org.jetbrains.kotlin.plugin.compose") version "2.0.21"
    }

    android {
            namespace = "com.aspauldingcode.wawona"
            compileSdk = 36
            buildToolsVersion = "36.0.0"

            defaultConfig {
                applicationId = "com.aspauldingcode.wawona"
                minSdk = 36
                targetSdk = 36
                versionCode = 1
                versionName = "1.0"
            }

        buildTypes {
            release {
                isMinifyEnabled = false
                proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            }
            debug {
                isMinifyEnabled = false
                isJniDebuggable = true
                isDebuggable = true
            }
        }
        
        compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
        
        kotlinOptions {
            jvmTarget = "17"
        }
        
        buildFeatures {
            compose = true
        }
        
        sourceSets {
            getByName("main") {
                manifest.srcFile("AndroidManifest.xml")
                java.srcDirs("java")
                res.srcDirs("res")
                jniLibs.srcDirs("jniLibs")
            }
        }
    }

    dependencies {
        implementation("androidx.core:core-ktx:1.15.0")
        implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
        implementation("androidx.activity:activity-compose:1.9.3")
        implementation(platform("androidx.compose:compose-bom:2024.10.01"))
        implementation("androidx.compose.ui:ui")
        implementation("androidx.compose.ui:ui-graphics")
        implementation("androidx.compose.ui:ui-tooling-preview")
        implementation("androidx.compose.foundation:foundation")
        implementation("androidx.compose.material3:material3:1.3.1")
        implementation("androidx.compose.material3:material3-window-size-class")
        implementation("androidx.compose.material:material-icons-extended")
        implementation("androidx.compose.animation:animation")
        
        implementation("androidx.appcompat:appcompat:1.7.0")
        implementation("androidx.fragment:fragment-ktx:1.8.9")
    }
  '';

  settingsGradle = pkgs.writeText "settings.gradle.kts" ''
    pluginManagement {
        println("Settings: offline mode is ''${gradle.startParameter.isOffline}")
        gradle.startParameter.isOffline = false
        println("Settings: forced offline mode to ''${gradle.startParameter.isOffline}")

        resolutionStrategy {
            eachPlugin {
                if (requested.id.id == "com.android.application") {
                useModule("com.android.tools.build:gradle:8.10.0")
            }
            }
        }
        repositories {
            maven {
                url = uri("https://dl.google.com/dl/android/maven2/")
            }
            google()
            mavenCentral()
            gradlePluginPortal()
        }
    }
    dependencyResolutionManagement {
        repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
        repositories {
            google()
            mavenCentral()
        }
    }
    rootProject.name = "Wawona"
  '';

  # Script to copy project to current directory.
  # When wawonaAndroidProject is available (pre-built Android project with jniLibs),
  # copies the full project for Android Studio. Otherwise falls back to gradle files only.
  generateScript = pkgs.writeShellScriptBin "gradlegen" ''
    set -e
    if [ -n "${toString wawonaAndroidProject}" ] && [ -d "${wawonaAndroidProject}" ]; then
      echo "Copying full Android project (backend + native libs) to current directory..."
      cp -r ${wawonaAndroidProject}/* .
      chmod -R u+w build.gradle.kts settings.gradle.kts 2>/dev/null || true
      echo "Project ready. Open this directory in Android Studio and select device/emulator."
    else
      cp ${buildGradle} build.gradle.kts
      cp ${settingsGradle} settings.gradle.kts
      chmod u+w build.gradle.kts settings.gradle.kts
      if [ -n "${toString wawonaSrc}" ] && [ -d "${wawonaSrc}/src/platform/android" ]; then
        mkdir -p java res
        cp -r ${wawonaSrc}/src/platform/android/java/* java/ 2>/dev/null || true
        cp -r ${wawonaSrc}/src/platform/android/res/* res/ 2>/dev/null || true
        cp ${wawonaSrc}/src/platform/android/AndroidManifest.xml . 2>/dev/null || true
        echo "Generated gradle files + Android sources (no jniLibs - run nix build .#wawona-android first for full project)"
      else
        echo "Generated build.gradle.kts and settings.gradle.kts"
      fi
    fi
  '';

in {
  inherit buildGradle settingsGradle generateScript;
}
