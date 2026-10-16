package com.example.nazzelha

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.provider.MediaStore
import android.util.Log
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Paths
import java.util.concurrent.Executors
import java.util.zip.ZipFile
import org.json.JSONObject
import org.json.JSONArray

/**
 * Implemented by the Kotlin side and passed into Python so yt-dlp progress
 * hooks can push REAL download progress events to Flutter while the download
 * is still running.
 */
interface ProgressSink {
    fun send(json: String)
}

class MainActivity : FlutterActivity() {
    private val CHANNEL = "nazzelha/python"
    private val TAG = "NazzelhaPython"
    private val STORAGE_PERMISSION_REQUEST = 4101

    private lateinit var pythonChannel: MethodChannel
    private val mainHandler = Handler(Looper.getMainLooper())

    // Long-running work (quality extraction, downloads) must never run on the
    // main thread — doing so blocks the UI and triggers ANRs on long videos.
    private val executor = Executors.newSingleThreadExecutor()

    private var pendingPermissionResult: MethodChannel.Result? = null

    private var debugReceiver: android.content.BroadcastReceiver? = null
    private var downloadReceiver: BroadcastReceiver? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        registerDownloadReceiver()
        // Debug-build-only adb test hooks: let an automated acceptance test
        // trigger the FULL TikTok pipeline (initialize -> qualities -> download)
        // without fragile UI automation, and log the JSON result to logcat.
        //
        // Two trigger mechanisms (both work on any Android version):
        //   A) Intent extras (most reliable):
        //      adb shell am start -n com.example.nazzelha/.MainActivity \
        //          --es url https://vt.tiktok.com/ZSVSKN6bS/ --es mode qualities
        //      --es mode download  (--es downloadMode audio for MP3)
        //   B) Broadcast (dynamic receiver):
        //      adb shell am broadcast -a com.example.nazzelha.DEBUG_TIKTOK \
        //          --es url https://vt.tiktok.com/ZSVSKN6bS/ --es mode download
        val isDebug = (applicationInfo.flags and
            android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (isDebug) {
            // A) intent-extras trigger fires when the activity is launched with
            // a "url" extra (survives config changes; the extra is only consumed
            // once so a normal UI launch is unaffected).
            val extraUrl = intent.getStringExtra("url")
            if (!extraUrl.isNullOrBlank()) {
                val extraMode = intent.getStringExtra("mode") ?: "qualities"
                val extraDlMode = intent.getStringExtra("downloadMode") ?: "video"
                val extraQuality = intent.getIntExtra("quality", 1080)
                Log.i(TAG, "DEBUG_TIKTOK intent-trigger url=$extraUrl mode=$extraMode")
                runDebugTikTokTest(extraUrl, extraMode, extraDlMode, extraQuality)
            } else {
                registerDebugTestHook() // B) broadcast receiver
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val isDebug = (applicationInfo.flags and
            android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!isDebug) return
        val url = intent.getStringExtra("url")
        if (url.isNullOrBlank()) return
        val mode = intent.getStringExtra("mode") ?: "qualities"
        val dlMode = intent.getStringExtra("downloadMode") ?: "video"
        val quality = intent.getIntExtra("quality", 1080)
        Log.i(TAG, "DEBUG_TIKTOK onNewIntent url=$url mode=$mode")
        runDebugTikTokTest(url, mode, dlMode, quality)
    }

    private fun registerDebugTestHook() {
        val action = "com.example.nazzelha.DEBUG_TIKTOK"
        debugReceiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(context: android.content.Context, intent: Intent) {
                if (intent.action != action) return
                val url = intent.getStringExtra("url")
                    ?: "https://vt.tiktok.com/ZSVSKN6bS/"
                val mode = intent.getStringExtra("mode") ?: "qualities"
                // "audio" -> audio-only download; used for on-device testing.
                val downloadMode = intent.getStringExtra("downloadMode") ?: "video"
                val quality = intent.getIntExtra("quality", 1080)
                Log.i(TAG, "DEBUG_TIKTOK received url=$url mode=$mode downloadMode=$downloadMode quality=$quality")
                runDebugTikTokTest(url, mode, downloadMode, quality)
            }
        }
        val filter = android.content.IntentFilter(action)
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(debugReceiver, filter, android.content.Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(debugReceiver, filter)
        }
        Log.i(TAG, "DEBUG_TIKTOK test hook registered")
    }

    /**
     * Forwards foreground-service progress/result broadcasts to the Dart side so
     * a background download keeps its progress flowing and its terminal state is
     * delivered even if the activity was recreated while the service kept running.
     */
    private fun registerDownloadReceiver() {
        if (downloadReceiver != null) return
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val json = intent.getStringExtra(DownloadForegroundService.EXTRA_JSON) ?: return
                if (!::pythonChannel.isInitialized) return
                val map = jsonToMap(json)
                when (intent.action) {
                    DownloadForegroundService.ACTION_PROGRESS ->
                        mainHandler.post {
                            try { pythonChannel.invokeMethod("onDownloadProgress", map) }
                            catch (e: Exception) { Log.w(TAG, "progress forward failed", e) }
                        }
                    DownloadForegroundService.ACTION_RESULT ->
                        mainHandler.post {
                            try { pythonChannel.invokeMethod("onDownloadResult", map) }
                            catch (e: Exception) { Log.w(TAG, "result forward failed", e) }
                        }
                }
            }
        }
        downloadReceiver = receiver
        val filter = IntentFilter().apply {
            addAction(DownloadForegroundService.ACTION_PROGRESS)
            addAction(DownloadForegroundService.ACTION_RESULT)
        }
        if (Build.VERSION.SDK_INT >= 33) {
            registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(receiver, filter)
        }
        Log.i(TAG, "download receiver registered")
    }

    override fun onDestroy() {
        downloadReceiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }
        downloadReceiver = null
        debugReceiver?.let { try { unregisterReceiver(it) } catch (_: Exception) {} }
        debugReceiver = null
        super.onDestroy()
    }

    /** Shared body of the adb TikTok acceptance test (shared by the intent-extra
     *  and broadcast triggers). Runs on the background executor. */
    private fun runDebugTikTokTest(url: String, mode: String,
                                   downloadMode: String, quality: Int) {
        executor.execute {
            try {
                initializePython()
                if (mode == "download") {
                    val sink = object : ProgressSink {
                        override fun send(json: String) {
                            Log.i(TAG, "DEBUG_TIKTOK progress: $json")
                        }
                    }
                    val resp = downloadVideo(url, "tiktok", quality, "", sink, downloadMode)
                    val persisted = persistDownload(resp)
                    Log.i(TAG, "DEBUG_TIKTOK DOWNLOAD RESULT: $persisted")
                } else {
                    val q = getQualities(url, "tiktok")
                    Log.i(TAG, "DEBUG_TIKTOK QUALITIES RESULT: $q")
                }
            } catch (e: Exception) {
                Log.e(TAG, "DEBUG_TIKTOK FAILED", e)
            }
        }
    }

        @SuppressLint("InlinedApi")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        pythonChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        pythonChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    try {
                        val response = initializePython()
                        // Phase 1: emit the Android runtime diagnostic (yt-dlp/curl_cffi/
                        // impersonation) to stderr/logcat right after Python is up, so the
                        // real capability of the on-device Python environment is recorded
                        // before any extraction runs. Wrapped in try/catch so a flaky Python
                        // probe can never regress app startup.
                        try {
                            runtimeDiagnostics()
                        } catch (e: Exception) {
                            Log.w(TAG, "post-init runtime diagnostics emitted failure: ${e.message}")
                        }
                        result.success(response)
                    } catch (e: Exception) {
                        Log.e(TAG, "Python init failed", e)
                        result.error("INIT_ERROR", e.message ?: "Python initialization failed", null)
                    }
                }
                "get_qualities" -> {
                    val url = call.argument<String>("url") ?: ""
                    val platform = call.argument<String>("platform") ?: "youtube"
                    executor.execute {
                        try {
                            result.success(getQualities(url, platform))
                        } catch (e: Exception) {
                            Log.e(TAG, "get_qualities failed", e)
                            result.error("QUALITIES_ERROR", e.message ?: "Failed to get qualities", null)
                        }
                    }
                }
                "runtime_diag" -> {
                    executor.execute {
                        try {
                            result.success(runtimeDiagnostics())
                        } catch (e: Exception) {
                            Log.e(TAG, "runtime_diag failed", e)
                            result.error("DIAG_ERROR", e.message ?: "Diagnostics failed", null)
                        }
                    }
                }
                "download", "start_download" -> {
                    val url = call.argument<String>("url") ?: ""
                    val platform = call.argument<String>("platform") ?: "youtube"
                    val quality = call.argument<Int>("quality") ?: 720
                    val outputPath = call.argument<String>("output_path") ?: ""
                    val mode = call.argument<String>("mode") ?: "video"
                    val filename = call.argument<String>("filename")
                    val taskId = System.currentTimeMillis().toString()
                    val intent = DownloadForegroundService.startIntent(
                        this, taskId, url, platform, quality, mode, outputPath,
                        filename
                    )
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "startForegroundService failed", e)
                        result.error("DOWNLOAD_START_ERROR", e.message ?: "Could not start download", null)
                        return@setMethodCallHandler
                    }
                    Log.i(TAG, "Download delegated to foreground service task=$taskId")
                    result.success(mapOf(
                        "task_id" to taskId,
                        "url" to url,
                        "platform" to platform,
                        "quality" to quality,
                        "mode" to mode,
                        "phase" to "downloading",
                        "percent" to 0
                    ))
                }
                "get_active_download" -> {
                    result.success(DownloadForegroundService.loadState(applicationContext))
                }
                "save_queue" -> {
                    val queue = call.argument<String>("queue") ?: ""
                    DownloadForegroundService.saveQueue(applicationContext, queue)
                    result.success(true)
                }
                "get_queue" -> {
                    val raw = DownloadForegroundService.loadQueue(applicationContext)
                    if (raw.isNullOrBlank()) {
                        result.success(emptyList<Any?>())
                    } else {
                        try {
                            val arr = JSONArray(raw)
                            result.success(jsonStringToAnyList(arr))
                        } catch (e: Exception) {
                            Log.w(TAG, "get_queue parse failed", e)
                            result.success(emptyList<Any?>())
                        }
                    }
                }
                "cancel_download" -> {
                    val cancel = Intent(this, DownloadForegroundService::class.java).apply {
                        action = DownloadForegroundService.ACTION_CANCEL
                    }
                    try {
                        startService(cancel)
                    } catch (_: Exception) {}
                    result.success(true)
                }
                "diagnose" -> {
                    val url = call.argument<String>("url") ?: ""
                    val platform = call.argument<String>("platform") ?: "youtube"
                    executor.execute {
                        try {
                            result.success(diagnose(url, platform))
                        } catch (e: Exception) {
                            Log.e(TAG, "diagnose failed", e)
                            result.error("DIAGNOSE_ERROR", e.message ?: "Diagnose failed", null)
                        }
                    }
                }
                "get_download_dir" -> {
                    try {
                        result.success(mapOf("success" to true, "download_dir" to publicDownloadsDir()))
                    } catch (e: Exception) {
                        Log.e(TAG, "get_download_dir failed", e)
                        result.error("DIR_ERROR", e.message ?: "Failed to get download dir", null)
                    }
                }
                "ensure_storage_permission" -> {
                    ensureStoragePermission(result)
                }
                "open_media" -> {
                    try {
                        val uri = Uri.parse(call.argument<String>("uri") ?: "")
                        // Prefer the MediaStore's registered MIME type so audio
                        // (mp3) and video files open with the right app.
                        val resolvedMime = contentResolver.getType(uri)
                            ?: mimeFor(uri.lastPathSegment ?: "media")
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, resolvedMime)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "open_media failed", e)
                        result.error("OPEN_ERROR", e.message ?: "Could not open video", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == STORAGE_PERMISSION_REQUEST) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermissionResult?.success(granted)
            pendingPermissionResult = null
        }
    }

    @SuppressLint("InlinedApi")
    private fun ensureStoragePermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q ||
            checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
                PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(android.Manifest.permission.WRITE_EXTERNAL_STORAGE),
            STORAGE_PERMISSION_REQUEST
        )
    }

    private fun initializePython(): Map<String, Any?> {
        if (!Python.isStarted()) {
            Log.i(TAG, "Starting Chaquopy Python runtime")
            Python.start(AndroidPlatform(this))
        }
        Log.i(TAG, "Chaquopy Python runtime started")

        val py = Python.getInstance()
        val module = py.getModule("android_backend")
        Log.i(TAG, "Python module 'android_backend' loaded")

        // Prepare the bundled FFmpeg runtime so yt-dlp can merge separate
        // video/audio streams on Android. The executables live in
        // nativeLibraryDir (the only location where exec() is permitted);
        // their shared libraries are extracted from libffmpeg.zip.so and
        // resolved at spawn time through LD_LIBRARY_PATH.
        val ffmpegRuntime = prepareFFmpegRuntime()

        // Writable, app-private temp dir for Python/yt-dlp. Android's default
        // Python tempfile location is /tmp which is read-only and crashes with
        // 'OSError: [Errno 30] Read-only file system' (seen on device). The
        // cacheDir is app-private and always writable.
        val pyTempDir = File(cacheDir, "pytmp")
        if (!pyTempDir.exists()) pyTempDir.mkdirs()

        val pyResult = module.callAttr(
            "initialize",
            ffmpegRuntime["nativeLibDir"],
            ffmpegRuntime["binDir"],
            ffmpegRuntime["libDir"],
            ffmpegRuntime["abi"],
            pyTempDir.absolutePath
        )
        if (pyResult == null) {
            throw RuntimeException(
                "Python initialize() returned None. The function must return a JSON string. " +
                    "Verify that android_backend.py is packaged in the APK (src/main/python) " +
                    "and that yt-dlp was installed via Chaquopy pip."
            )
        }

        val jsonStr = pyResult.toString()
        Log.i(TAG, "Python initialize() returned: $jsonStr")

        // Phase 1/2/3/5 evidence: dump the actual Android Python runtime
        // (yt-dlp version+location, curl_cffi presence, impersonation targets,
        // requests/certifi/ffmpeg) to logcat via python.stderr ([NazzelhaPy]).
        // This proves which yt-dlp the APK loads and why impersonation is
        // unavailable - it must NEVER pollute the stdout JSON protocol.
        try {
            module.callAttr("android_runtime_diagnostics")
            Log.i(TAG, "Android runtime diagnostics emitted (see [NazzelhaPy] in logcat)")
        } catch (e: Exception) {
            Log.w(TAG, "Runtime diagnostics failed: ${e.message}")
        }

        return jsonToMap(jsonStr)
    }

    /**
     * Prepare the bundled FFmpeg runtime for the current ABI.
     *
     * - Executables: libffmpeg.so / libffprobe.so are installed by the system
     *   into nativeLibraryDir (extracted because jniLibs.useLegacyPackaging is
     *   enabled). They must be executed from there directly.
     * - Shared libraries: libffmpeg.zip.so contains the libavcodec/libavformat
     *   shared libraries under usr/lib. They are extracted once into a private
     *   directory and made discoverable via LD_LIBRARY_PATH when spawning FFmpeg.
     * - Entry points: yt-dlp expects binaries named "ffmpeg"/"ffprobe" inside
     *   its configured ffmpeg_location directory, so symlinks pointing at the
     *   nativeLibraryDir executables are created in a private bin directory.
     */
    private fun prepareFFmpegRuntime(): Map<String, Any> {
        val nativeLibDir = applicationInfo.nativeLibraryDir
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"
        val nativeDir = File(nativeLibDir)
        val ffmpegZip = File(nativeDir, "libffmpeg.zip.so")

        val baseDir = File(noBackupFilesDir, "nazzelha_ffmpeg")
        val ffmpegPkgDir = File(baseDir, "ffmpeg")
        val libDir = File(ffmpegPkgDir, "usr/lib")
        val binDir = File(baseDir, "bin")

        var extractionError: String? = null
        if (ffmpegZip.exists()) {
            try {
                // Use the zip size as a cheap version stamp, like upstream
                // youtubedl-android does, so we re-extract only when needed.
                val marker = File(baseDir, ".ffmpeg_version")
                val versionStamp = ffmpegZip.length().toString()
                val sentinel = File(libDir, "libavcodec.so")
                if (!marker.exists() || marker.readText() != versionStamp || !sentinel.exists()) {
                    baseDir.deleteRecursively()
                    baseDir.mkdirs()
                    ffmpegPkgDir.mkdirs()
                    ZipFile(ffmpegZip).use { zip ->
                        val entries = zip.entries()
                        while (entries.hasMoreElements()) {
                            val entry = entries.nextElement()
                            if (entry.isDirectory) continue
                            val outFile = File(ffmpegPkgDir, entry.name)
                            outFile.parentFile?.mkdirs()
                            zip.getInputStream(entry).use { input ->
                                outFile.outputStream().use { output ->
                                    input.copyTo(output)
                                }
                            }
                        }
                    }
                    marker.writeText(versionStamp)
                    Log.i(TAG, "FFmpeg shared libraries extracted to ${libDir.absolutePath}")
                } else {
                    Log.i(TAG, "FFmpeg shared libraries already extracted")
                }
            } catch (e: Exception) {
                extractionError = e.message ?: e.javaClass.simpleName
                Log.e(TAG, "Failed to extract FFmpeg shared libraries", e)
            }
        } else {
            extractionError = "libffmpeg.zip.so not found in $nativeLibDir"
            Log.w(TAG, extractionError)
        }

        binDir.mkdirs()
        val ffmpegPath = createEntryPoint(binDir, nativeDir, "ffmpeg", "libffmpeg.so")
        val ffprobePath = createEntryPoint(binDir, nativeDir, "ffprobe", "libffprobe.so")
        Log.i(TAG, "FFmpeg entry point: $ffmpegPath (ffprobe: $ffprobePath)")

        return mapOf(
            "nativeLibDir" to nativeLibDir,
            "binDir" to binDir.absolutePath,
            "libDir" to libDir.absolutePath,
            "abi" to abi,
            "ffmpegPath" to (ffmpegPath ?: ""),
            "ffprobePath" to (ffprobePath ?: ""),
            "extractionError" to (extractionError ?: "")
        )
    }

    /**
     * Create an executable entry point named [linkName] inside [binDir] that
     * resolves to the real executable [targetName] in nativeLibraryDir.
     *
     * A symlink is preferred because Android blocks execve() of files written
     * into app data directories (W^X policy, targetSdk >= 29), while executing
     * through a symlink that resolves back into nativeLibraryDir is allowed.
     * If symlink creation fails, fall back to copying the binary and marking
     * it executable (works on older devices).
     */
    private fun createEntryPoint(binDir: File, nativeDir: File, linkName: String, targetName: String): String? {
        val target = File(nativeDir, targetName)
        if (!target.exists()) {
            Log.w(TAG, "$targetName not found in $nativeDir")
            return null
        }
        val link = File(binDir, linkName)
        try {
            if (link.exists() || Files.isSymbolicLink(Paths.get(link.absolutePath))) {
                link.delete()
            }
            try {
                Files.createSymbolicLink(
                    Paths.get(link.absolutePath),
                    Paths.get(target.absolutePath)
                )
            } catch (e: Exception) {
                Log.w(TAG, "Symlink creation failed for $linkName, falling back to copy", e)
                target.copyTo(link, overwrite = true)
                link.setExecutable(true, false)
            }
            return link.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create FFmpeg entry point $linkName", e)
            return null
        }
    }

    private fun getQualities(url: String, platform: String): Map<String, Any?> {
        // Native Android TikTok adapter: uses the device's own TLS stack (OkHttp
        // over the OS provider) to fetch the real media metadata, bypassing the
        // missing Python/yt-dlp impersonation dependency. If that cannot obtain
        // a real page we fall back to the Python yt-dlp cascade (unchanged).
                if (TikTokExtractor.isTikTok(platform, url)) {
            try {
                val nativeJson = TikTokExtractor(null).extractQualitiesJson(url)
                val nativeObj = JSONObject(nativeJson)
                if (nativeObj.optBoolean("success")) {
                    Log.i(TAG, "Native TikTok quality extraction OK")
                    return jsonToMap(nativeObj.toString())
                }
                Log.w(TAG, "Native TikTok quality failed; falling back to Python: $nativeJson")
            } catch (e: Exception) {
                Log.w(TAG, "Native TikTok quality threw; falling back to Python: ${e.message}")
            }
        }

        val py = Python.getInstance()
        val module = py.getModule("android_backend")
        val pyResult = module.callAttr("get_qualities", url, platform)
        if (pyResult == null) {
            return mapOf(
                "success" to false,
                "error" to "Python get_qualities() returned None for url=$url platform=$platform"
            )
        }
        val jsonStr = pyResult.toString()
        // Development tracing: mirror the FULL failure payload (technical,
        // diagnostics, verbose yt-dlp tail) into logcat so the real root
        // cause of a Submit failure is never hidden behind the UI message.
        if (jsonStr.contains("\"success\": false") || jsonStr.contains("\"success\":false")) {
            Log.w(TAG, "get_qualities FAILURE payload: $jsonStr")
        } else {
            Log.i(TAG, "get_qualities ok (${jsonStr.length} chars)")
        }
        return jsonToMap(jsonStr)
    }

    /**
     * Internal extraction diagnostic. Calls android_backend.diagnose() and
     * returns its structured JSON report (runtime identity, matching
     * extractors, exact failure reason). Not used by the production UI.
     */
    private fun diagnose(url: String, platform: String): Map<String, Any?> {
        val py = Python.getInstance()
        val module = py.getModule("android_backend")
        val pyResult = module.callAttr("diagnose", url, platform)
            ?: return mapOf(
                "success" to false,
                "error" to "Python diagnose() returned None"
            )
        val jsonStr = pyResult.toString()
        Log.i(TAG, "diagnose report: $jsonStr")
        return jsonToMap(jsonStr)
    }

    /**
     * Full Android runtime diagnostic (Phase 1): reports Python/yt-dlp/curl_cffi
     * versions + locations, the device ABI and every impersonation target. The
     * Python side writes the full human-readable block to stderr (logcat) and
     * returns a structured JSON for the UI/shell. Never touches stdout JSON
     * protocol responses.
     */
    private fun runtimeDiagnostics(): Map<String, Any?> {
        val report = try {
            val py = Python.getInstance()
            val module = py.getModule("android_backend")
            val res = module.callAttr("android_runtime_diagnostics")
                ?: throw RuntimeException("android_runtime_diagnostics returned None")
            jsonToMap(res.toString())
        } catch (e: Exception) {
            Log.e(TAG, "Python runtime diagnostics failed", e)
            return mapOf(
                "success" to false,
                "error" to (e.message ?: "Runtime diagnostics unavailable"),
                "abi" to (Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown")
            )
        }
        Log.i(TAG, "ANDROID RUNTIME REPORT: $report")
        return report
    }

    private fun downloadVideo(
        url: String,
        platform: String,
        quality: Int,
        outputPath: String,
        sink: ProgressSink,
        mode: String = "video"
    ): String {
        val stagingDir = stagingDir()
        Log.i(TAG, "Download staging directory: ${stagingDir.absolutePath}")

        // Native Android TikTok download: stream the real direct media URL
        // (from the parsed universal-data) with the device's own TLS stack.
        // Falls back to the Python yt-dlp download when unavailable. In audio
        // mode the progressive MP4 is extracted to a real MP3 with FFmpeg.
        if (TikTokExtractor.isTikTok(platform, url)) {
            try {
                val nativeJson = TikTokExtractor(sink)
                    .download(url, quality, stagingDir, mode, ffmpegExecutable())
                val nativeObj = JSONObject(nativeJson)
                if (nativeObj.optBoolean("success")) {
                    Log.i(TAG, "Native TikTok download OK (mode=$mode)")
                    return nativeJson
                }
                Log.w(TAG, "Native TikTok download failed; falling back to Python: $nativeJson")
            } catch (e: Exception) {
                Log.w(TAG, "Native TikTok download threw; falling back to Python: ${e.message}")
            }
        }

        val py = Python.getInstance()
        val module = py.getModule("android_backend")

        // yt-dlp always writes into a private staging directory that is
        // guaranteed writable; the finished file is then persisted to the
        // public Downloads/Nazzelha location by persistDownload().
        val pyResult = module.callAttr(
            "download_video",
            url,
            platform,
            quality,
            stagingDir.absolutePath,
            PyObject.fromJava(sink),
            mode
        )
        if (pyResult == null) {
            return JSONObject().apply {
                put("success", false)
                put("error", "Python download_video() returned None for url=$url platform=$platform quality=$quality")
            }.toString()
        }
        val jsonStr = pyResult.toString()
        if (jsonStr.contains("\"success\": false") || jsonStr.contains("\"success\":false")) {
            Log.w(TAG, "download FAILURE payload: $jsonStr")
        }
        return jsonStr
    }

    /**
     * Persist the finished download into the user-visible public storage:
     * Downloads/Nazzelha/.
     *
     * - Android 10+ (API 29+): MediaStore Downloads collection with
     *   RELATIVE_PATH=Download/Nazzelha (no permission required).
     * - Android 9 and below: direct write to the public Downloads directory
     *   (WRITE_EXTERNAL_STORAGE runtime permission is requested by
     *   ensure_storage_permission before the download starts), followed by a
     *   media scan so the file appears immediately.
     *
     * Internal diagnostics are logged but never returned to the UI.
     */
    private fun persistDownload(responseJson: String): Map<String, Any?> {
        val obj = JSONObject(responseJson)
        if (obj.optBoolean("success") != true) {
            return jsonToMap(responseJson)
        }

        val srcPath = obj.optString("file")
        val displayName = obj.optString("filename").ifEmpty { "video.mp4" }
        val title = obj.optString("title")
        val size = obj.optLong("size")
        val diagnostics = obj.optJSONObject("diagnostics")
        Log.i(TAG, "Download diagnostics: $diagnostics")

        val src = File(srcPath)
        if (!src.exists() || src.length() <= 0L) {
            Log.e(TAG, "Staged file missing or empty: $srcPath")
            return mapOf(
                "success" to false,
                "error" to "The download did not produce a valid media file. Please try again."
            )
        }

        return try {
            val persisted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                persistViaMediaStore(src, displayName)
            } else {
                persistLegacy(src, displayName)
            }
            // Remove the private staging copy now that the file lives in the
            // public Downloads location.
            src.delete()
            Log.i(TAG, "Download persisted to: ${persisted.first} (${persisted.second})")
            mapOf(
                "success" to true,
                "file" to persisted.second,
                "display_path" to persisted.first,
                "filename" to persisted.first.substringAfterLast('/'),
                "title" to title,
                "size" to size
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to persist download to public storage", e)
            mapOf(
                "success" to false,
                "error" to "The video was downloaded but could not be saved to your Downloads folder. Please try again."
            )
        }
    }

    /** Android 10+: insert into the MediaStore Downloads collection. */
    private fun persistViaMediaStore(src: File, displayName: String): Pair<String, String> {
        val resolver = contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val mime = mimeFor(displayName)

        fun valuesFor(name: String) = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/Nazzelha")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }

        var uri = resolver.insert(collection, valuesFor(displayName))
        if (uri == null) {
            uri = resolver.insert(
                collection,
                valuesFor("Nazzelha_${System.currentTimeMillis()}_$displayName")
            )
        }
        if (uri == null) throw IOException("MediaStore insert failed")

        resolver.openOutputStream(uri)!!.use { out ->
            src.inputStream().use { input -> input.copyTo(out) }
        }
        val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
        resolver.update(uri, done, null, null)

        // Resolve the friendly public location for display purposes.
        var relativePath = Environment.DIRECTORY_DOWNLOADS + "/Nazzelha"
        var name = displayName
        resolver.query(
            uri,
            arrayOf(MediaStore.MediaColumns.RELATIVE_PATH, MediaStore.MediaColumns.DISPLAY_NAME),
            null, null, null
        )?.use { c ->
            if (c.moveToFirst()) {
                c.getString(0)?.let { relativePath = it.trimEnd('/') }
                c.getString(1)?.let { name = it }
            }
        }
        return Pair("$relativePath/$name", uri.toString())
    }

    /** Android 9 and below: direct write into the public Downloads directory. */
    private fun persistLegacy(src: File, displayName: String): Pair<String, String> {
        val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
        val destDir = File(downloadsDir, "Nazzelha")
        if (!destDir.exists()) destDir.mkdirs()

        var dest = File(destDir, displayName)
        var counter = 1
        while (dest.exists()) {
            val dot = displayName.lastIndexOf('.')
            val base = if (dot > 0) displayName.substring(0, dot) else displayName
            val ext = if (dot > 0) displayName.substring(dot) else ""
            dest = File(destDir, "$base($counter)$ext")
            counter++
        }

        src.inputStream().use { input ->
            dest.outputStream().use { output -> input.copyTo(output) }
        }
        MediaScannerConnection.scanFile(
            this,
            arrayOf(dest.absolutePath),
            arrayOf(mimeFor(dest.name)),
            null
        )
        return Pair("Downloads/Nazzelha/${dest.name}", dest.absolutePath)
    }

    private fun mimeFor(fileName: String): String {
        val ext = fileName.substringAfterLast('.', "").lowercase()
        return when (ext) {
            "mp4", "m4v" -> "video/mp4"
            "webm" -> "video/webm"
            "mkv" -> "video/x-matroska"
            "m4a" -> "audio/mp4"
            "mp3" -> "audio/mpeg"
            "opus" -> "audio/opus"
            else -> "video/mp4"
        }
    }

    /** Locate the bundled FFmpeg executable entry point (same mechanism used by
     * prepareFFmpegRuntime). Returns null when the ABI's FFmpeg is unavailable.
     * Used by the native TikTok audio path to extract MP3 from the progressive
     * MP4. */
    private fun ffmpegExecutable(): String? {
        return try {
            val nativeDir = applicationInfo.nativeLibraryDir
            val binDir = File(cacheDir, "ffmpegbin")
            if (!binDir.exists()) binDir.mkdirs()
            createEntryPoint(binDir, File(nativeDir), "ffmpeg", "libffmpeg.so")
        } catch (e: Exception) {
            Log.e(TAG, "ffmpegExecutable() failed", e)
            null
        }
    }

    /** Private, always-writable staging area for in-progress downloads. */
    private fun stagingDir(): File {
        val dir = File(getExternalFilesDir(null), "downloads")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    /** The public Downloads/Nazzelha location (informational). */
    private fun publicDownloadsDir(): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            Environment.DIRECTORY_DOWNLOADS + "/Nazzelha"
        } else {
            val downloadsDir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val dir = File(downloadsDir, "Nazzelha")
            if (!dir.exists()) dir.mkdirs()
            dir.absolutePath
        }
    }

    /**
     * Recursively convert a JSON string into Java collections that
     * Flutter's MethodChannel can serialize (Map<String, Any?>, List<Any?>, etc.).
     * This avoids the Chaquopy "Cannot convert dict object to java.util.Map"
     * TypeError by never passing Python dicts through the bridge directly.
     */
    private fun jsonToMap(jsonString: String): Map<String, Any?> {
        val obj = JSONObject(jsonString)
        val keys = obj.keys()
        val result: MutableMap<String, Any?> = LinkedHashMap()
        while (keys.hasNext()) {
            val key = keys.next()
            result[key] = jsonStringAny(obj.get(key))
        }
        return result
    }

    private fun jsonStringToAnyList(jsonArray: JSONArray): List<Any?> {
        val result: MutableList<Any?> = ArrayList()
        for (i in 0 until jsonArray.length()) {
            result.add(jsonStringAny(jsonArray.get(i)))
        }
        return result
    }

    private fun jsonStringAny(value: Any?): Any? {
        return when (value) {
            is JSONObject -> {
                val keys = value.keys()
                val map: MutableMap<String, Any?> = LinkedHashMap()
                while (keys.hasNext()) {
                    val key = keys.next()
                    map[key] = jsonStringAny(value.get(key))
                }
                map
            }
            is JSONArray -> jsonStringToAnyList(value)
            JSONObject.NULL -> null
            else -> value
        }
    }
}