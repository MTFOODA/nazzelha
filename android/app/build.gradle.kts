plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.chaquo.python")
}

val chaquopyBuildPython = providers.gradleProperty("chaquopy.buildPython")
    .orElse(providers.environmentVariable("CHAQUOPY_BUILD_PYTHON"))
    .orElse("python")

android {
    namespace = "com.example.nazzelha"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.nazzelha"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    packaging {
        // Extract native libraries to nativeLibraryDir at install time instead of
        // loading them directly from the APK. The bundled FFmpeg executables
        // (libffmpeg.so / libffprobe.so) must exist as real executable files on
        // disk so yt-dlp can spawn them for stream merging on Android.
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

chaquopy {
    defaultConfig {
        version = "3.11"
        // Set CHAQUOPY_BUILD_PYTHON or -Pchaquopy.buildPython to a host Python
        // 3.11 executable when it is not available as `python` on PATH.
        buildPython(chaquopyBuildPython.get())
        pip {
            // MUST stay >= 2026.8.19: older releases (e.g. 2026.07.04, which the
            // unpinned spec used to resolve to) fall back to YouTube player
            // clients whose media URLs return HTTP 403 during download
            // ("unable to download video data: HTTP Error 403: Forbidden") for
            // normal videos and Shorts alike. This pin controls the yt-dlp that
            // is ACTUALLY executed inside the APK via Chaquopy - the Windows
            // .venv requirements.txt pin does not affect Android.
            install("yt-dlp==2026.8.19")
            // certifi is a pure-Python package that ships a complete Mozilla CA
            // bundle and is the ONE dependency yt-dlp prefers to use for TLS
            // verification. Chaquopy's embedded CPython does not inherit the
            // desktop/system CA store the way Windows Python does, and without a
            // reliable CA store every HTTPS request from the app can fail with an
            // SSL error - which surfaces as a generic "could not extract" for ANY
            // site (YouTube, TikTok...) while Windows works. certifi guarantees a
            // working CA bundle on-device regardless of the Android image.
            install("certifi")
            // NOTE: curl-cffi is NOT installed on Android. Chaquopy ships only a
            // pure-Python shim with NO Android native libs (staging tree has zero
            // arm64-v8a/armeabi-v7a .so files), so `import curl_cffi` fails at
            // runtime and yt-dlp's chrome impersonator (required by the TikTok
            // extractor here) cannot be used. The TikTok fallback cascade
            // detects this at runtime and falls back to a desktop-browser User-Agent
            // strategy (no impersonation) so extraction still has a chance.
        }
        pyc {
            src = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Native OkHttp stack used by the TikTok Android extraction adapter so the
    // web request goes over the device's own TLS provider instead of relying on
    // Python's (absent) impersonation support. OkHttp 4.x pulls okio + a
    // Kotlin stdlib; it needs no native .so so all ABIs remain supported.
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
