pluginManagement {
    println("Settings: offline mode is ${gradle.startParameter.isOffline}")
    gradle.startParameter.isOffline = false
    println("Settings: forced offline mode to ${gradle.startParameter.isOffline}")

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
