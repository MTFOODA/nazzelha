pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
        maven { url = uri("https://chaquo.com/maven") }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    // 17.0.0 is REQUIRED for devices/emulators using a 16 KB page size
    // (Android 15+ on some devices, API 36 emulator images): 16.1.0's
    // libchaquopy_java.so is only 4 KB-aligned and dies at startup with
    // "UnsatisfiedLinkError: program alignment (4096) cannot be smaller than
    // system page size (16384)". See chaquo/chaquopy issue #1447 (the only
    // remaining gap there is armeabi-v7a; our ABIs are unaffected).
    id("com.chaquo.python") version "17.0.0" apply false
}

include(":app")
