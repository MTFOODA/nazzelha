package com.example.nazzelha

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.provider.MediaStore
import android.util.Log
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Paths
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipFile
import org.json.JSONArray
import org.json.JSONObject

/**
 * Durable foreground download service.
 *
 * Owns the download from start to terminal state so it does NOT depend on the
 * Flutter activity, screen, or Dart timers remaining alive. While work is
 * active it holds a foreground notification + a partial wake lock, persists
 * the task state, and broadcasts progress / terminal results so a recreated
 * activity can reconnect and restore the real download state.
 */
class DownloadForegroundService : Service() {

    companion object {
        const val TAG = "NazzelhaDownload"

        const val ACTION_START = "com.example.nazzelha.action.DOWNLOAD_START"
        const val ACTION_CANCEL = "com.example.nazzelha.action.DOWNLOAD_CANCEL"
        const val ACTION_PROGRESS = "com.example.nazzelha.action.DOWNLOAD_PROGRESS"
        const val ACTION_RESULT = "com.example.nazzelha.action.DOWNLOAD_RESULT"

        const val EXTRA_TASK_ID = "task_id"
        const val EXTRA_URL = "url"
        const val EXTRA_PLATFORM = "platform"
        const val EXTRA_QUALITY = "quality"
        const val EXTRA_MODE = "mode"
        const val EXTRA_OUTPUT_PATH = "output_path"
        const val EXTRA_FILENAME = "filename"
        const val EXTRA_JSON = "json"

        const val CHANNEL_ID = "nazzelha_downloads"
        const val NOTIFICATION_ID = 1001

        private const val PREFS = "nazzelha_download_state"
        private const val KEY_STATE = "current_task"
        private const val KEY_QUEUE = "queue"

        /** Authoritative, process-surviving task state (also persisted). */
        @Volatile
        var currentState: MutableMap<String, Any?>? = null
            private set

        fun saveState(context: Context, state: Map<String, Any?>) {
            currentState = state.toMutableMap()
            val json = JSONObject()
            state.forEach { (k, v) -> json.put(k, v) }
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY_STATE, json.toString()).apply()
        }

        fun loadState(context: Context): MutableMap<String, Any?>? {
            currentState?.let { return it.toMutableMap() }
            val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_STATE, null) ?: return null
            return try {
                jsonToMap(raw).also { currentState = it }
            } catch (e: Exception) {
                Log.w(TAG, "Could not parse persisted download state", e)
                null
            }
        }

        fun clearState(context: Context) {
            currentState = null
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().remove(KEY_STATE).apply()
        }

        /** Persist the complete Nazzelha Sawa queue snapshot (JSON array). */
        fun saveQueue(context: Context, queueJson: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY_QUEUE, queueJson).apply()
        }

        /** Read the persisted Nazzelha Sawa queue snapshot, or null. */
        fun loadQueue(context: Context): String? {
            return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .getString(KEY_QUEUE, null)
        }

        /** Stable sanitized platform subfolder under the Nazzelha root. */
        fun platformFolder(platform: String): String {
            return when (platform.lowercase()) {
                "youtube", "youtu.be" -> "YouTube"
                "facebook", "fb.watch" -> "Facebook"
                "instagram", "instagr.am" -> "Instagram"
                "tiktok", "vt.tiktok.com", "vm.tiktok.com" -> "TikTok"
                else -> "Other"
            }
        }

        fun startIntent(
            context: Context, taskId: String, url: String, platform: String,
            quality: Int, mode: String, outputPath: String,
            filename: String? = null
        ): Intent = Intent(context, DownloadForegroundService::class.java).apply {
            action = ACTION_START
            putExtra(EXTRA_TASK_ID, taskId)
            putExtra(EXTRA_URL, url)
            putExtra(EXTRA_PLATFORM, platform)
            putExtra(EXTRA_QUALITY, quality)
            putExtra(EXTRA_MODE, mode)
            putExtra(EXTRA_OUTPUT_PATH, outputPath)
            putExtra(EXTRA_FILENAME, filename ?: "")
        }

        private fun jsonToMap(json: String): MutableMap<String, Any?> {
            val obj = JSONObject(json)
            val result: MutableMap<String, Any?> = LinkedHashMap()
            val keys = obj.keys()
            while (keys.hasNext()) {
                val key = keys.next()
                result[key] = jsonValue(obj.get(key))
            }
            return result
        }

        private fun jsonValue(v: Any?): Any? = when (v) {
            is JSONObject -> {
                val m: MutableMap<String, Any?> = LinkedHashMap()
                val keys = v.keys()
                while (keys.hasNext()) { val k = keys.next(); m[k] = jsonValue(v.get(k)) }
                m
            }
            is JSONArray -> {
                val l = ArrayList<Any?>()
                for (i in 0 until v.length()) l.add(jsonValue(v.get(i)))
                l
            }
            else -> v
        }
    }

    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val cancelled = AtomicBoolean(false)
    private val running = AtomicBoolean(false)
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val taskId = intent.getStringExtra(EXTRA_TASK_ID)
                    ?: System.currentTimeMillis().toString()
                val url = intent.getStringExtra(EXTRA_URL) ?: ""
                val platform = intent.getStringExtra(EXTRA_PLATFORM) ?: "youtube"
                val quality = intent.getIntExtra(EXTRA_QUALITY, 720)
                val mode = intent.getStringExtra(EXTRA_MODE) ?: "video"
                val outputPath = intent.getStringExtra(EXTRA_OUTPUT_PATH) ?: ""
                val filename = intent.getStringExtra(EXTRA_FILENAME)?.takeIf { it.isNotBlank() }
                if (running.compareAndSet(false, true)) {
                    cancelled.set(false)
                    startForegroundWithNotification("Downloading\u2026")
                    acquireWakeLock()
                    saveState(applicationContext, mapOf(
                        "task_id" to taskId,
                        "url" to url,
                        "platform" to platform,
                        "quality" to quality,
                        "mode" to mode,
                        "output_path" to outputPath,
                        "phase" to "downloading",
                        "percent" to 0,
                        "filename" to filename,
                        "file" to null,
                        "error" to null
                    ))
                    executor.execute { runDownload(taskId, url, platform, quality, mode, outputPath, filename) }
                }
            }
            ACTION_CANCEL -> {
                Log.i(TAG, "Cancel requested")
                cancelled.set(true)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        running.set(false)
        super.onDestroy()
    }

    private fun startForegroundWithNotification(title: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val cancelIntent = PendingIntent.getService(
            this, 1,
            Intent(this, DownloadForegroundService::class.java).apply { action = ACTION_CANCEL },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
        }
            .setContentTitle("Nazzelha")
            .setContentText(title)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelIntent)
            .setCategory(android.app.Notification.CATEGORY_PROGRESS)
            .setProgress(100, 0, true)
            .build()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(NOTIFICATION_ID, notification,
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun acquireWakeLock() {
        try {
            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "nazzelha:download").apply {
                setReferenceCounted(false)
                acquire(12 * 60 * 60 * 1000L)
            }
            Log.i(TAG, "Wake lock acquired")
        } catch (e: Exception) {
            Log.w(TAG, "Could not acquire wake lock", e)
        }
    }

    private fun releaseWakeLock() {
        try {
            wakeLock?.takeIf { it.isHeld }?.release()
        } catch (e: Exception) {
            Log.w(TAG, "Wake lock release failed", e)
        }
        wakeLock = null
    }

    private fun runDownload(taskId: String, url: String, platform: String,
                            quality: Int, mode: String, outputPath: String,
                            filename: String?) {
        val sink = object : ProgressSink {
            override fun send(json: String) {
                val payload = try { jsonToMap(json) } catch (e: Exception) { null }
                val percent = ((payload?.get("percent") as? Number)?.toDouble() ?: 0.0)
                currentState?.let { it["phase"] = "downloading"; it["percent"] = percent }
                broadcast(ACTION_PROGRESS, json)
            }
        }

        val result: Map<String, Any?> = try {
            Log.i(TAG, "Download started task=$taskId url=$url quality=$quality mode=$mode")
            val response = downloadVideo(url, platform, quality, outputPath, sink, mode)
            persistDownload(response, platform, filename).also {
                Log.i(TAG, "Download terminal result: $it")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Download failed", e)
            mapOf(
                "success" to false,
                "error" to (e.message ?: "Download failed"),
                "cancelled" to cancelled.get()
            )
        }

        val cancelledFlag = cancelled.get() || result["cancelled"] == true
        val phase = when {
            cancelledFlag -> "cancelled"
            result["success"] == true -> "completed"
            else -> "failed"
        }
        val terminal = mutableMapOf<String, Any?>()
        terminal["task_id"] = taskId
        terminal["url"] = url
        terminal["platform"] = platform
        terminal["quality"] = quality
        terminal["mode"] = mode
        terminal["output_path"] = outputPath
        terminal["phase"] = phase
        terminal.putAll(result)
        saveState(applicationContext, terminal)

        broadcast(ACTION_RESULT, JSONObject(terminal).toString())
        mainHandler.post { notifyTerminal(phase, (result["error"] as? String).orEmpty()) }

        releaseWakeLock()
        running.set(false)
        stopSelf()
    }

    private fun notifyTerminal(phase: String, error: String) {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW)
            )
        }
        val text = when (phase) {
            "completed" -> "Download complete"
            "cancelled" -> "Download cancelled"
            else -> if (error.isNotBlank()) error else "Download failed"
        }
        val notification = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            android.app.Notification.Builder(this)
        }
            .setContentTitle("Nazzelha")
            .setContentText(text)
            .setSmallIcon(
                if (phase == "completed") android.R.drawable.stat_sys_download_done
                else android.R.drawable.stat_sys_warning
            )
            .setAutoCancel(true)
            .build()
        try {
            nm.notify(NOTIFICATION_ID + 1, notification)
        } catch (e: Exception) {
            Log.w(TAG, "Could not post terminal notification", e)
        }
    }

    private fun broadcast(action: String, json: String) {
        val intent = Intent(action).setPackage(packageName)
        intent.putExtra(EXTRA_JSON, json)
        try {
            sendBroadcast(intent)
        } catch (e: Exception) {
            Log.w(TAG, "Broadcast failed", e)
        }
    }

    private fun ensureInitialized() {
        if (!Python.isStarted()) {
            Log.i(TAG, "Starting Chaquopy Python runtime from service")
            Python.start(AndroidPlatform(applicationContext))
        }
        val module = Python.getInstance().getModule("android_backend")
        val ffmpeg = prepareFFmpegRuntime()
        val pyTempDir = File(cacheDir, "pytmp")
        if (!pyTempDir.exists()) pyTempDir.mkdirs()
        module.callAttr(
            "initialize",
            ffmpeg["nativeLibDir"], ffmpeg["binDir"], ffmpeg["libDir"],
            ffmpeg["abi"], pyTempDir.absolutePath
        )
    }

    private fun prepareFFmpegRuntime(): Map<String, Any> {
        val nativeLibDir = applicationInfo.nativeLibraryDir
        val nativeDir = File(nativeLibDir)
        val abi = Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"
        val baseDir = File(noBackupFilesDir, "nazzelha_ffmpeg")
        val ffmpegPkgDir = File(baseDir, "ffmpeg")
        val libDir = File(ffmpegPkgDir, "usr/lib")
        val binDir = File(baseDir, "bin")

        var extractionError: String? = null
        val zipFile = File(nativeDir, "libffmpeg.zip.so")
        if (zipFile.exists()) {
            val marker = File(libDir, ".extracted_${abi}_v2")
            if (!marker.exists()) {
                try {
                    libDir.deleteRecursively()
                    libDir.mkdirs()
                    ZipFile(zipFile).use { zip ->
                        val entries = zip.entries()
                        while (entries.hasMoreElements()) {
                            val entry = entries.nextElement()
                            if (entry.name.endsWith(".so") && entry.name.startsWith("usr/lib/")) {
                                val out = File(libDir, File(entry.name).name)
                                zip.getInputStream(entry).use { input ->
                                    out.outputStream().use { output -> input.copyTo(output) }
                                }
                            }
                        }
                    }
                    marker.writeText("v2")
                    Log.i(TAG, "FFmpeg shared libraries extracted to ${libDir.absolutePath}")
                } catch (e: Exception) {
                    extractionError = e.message ?: e.javaClass.simpleName
                    Log.e(TAG, "Failed to extract FFmpeg shared libraries", e)
                }
            } else {
                Log.i(TAG, "FFmpeg shared libraries already extracted")
            }
        } else {
            extractionError = "libffmpeg.zip.so not found in $nativeLibDir"
            Log.w(TAG, extractionError)
        }

        binDir.mkdirs()
        val ffmpegPath = createEntryPoint(binDir, nativeDir, "ffmpeg", "libffmpeg.so")
        val ffprobePath = createEntryPoint(binDir, nativeDir, "ffprobe", "libffprobe.so")
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

    private fun createEntryPoint(binDir: File, nativeDir: File, linkName: String, targetName: String): String? {
        val target = File(nativeDir, targetName)
        if (!target.exists()) return null
        val link = File(binDir, linkName)
        try {
            if (link.exists() || Files.isSymbolicLink(Paths.get(link.absolutePath))) link.delete()
            try {
                Files.createSymbolicLink(Paths.get(link.absolutePath), Paths.get(target.absolutePath))
            } catch (e: Exception) {
                target.copyTo(link, overwrite = true)
                link.setExecutable(true, false)
            }
            return link.absolutePath
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create FFmpeg entry point $linkName", e)
            return null
        }
    }

    private fun ffmpegExecutable(): String? {
        return try {
            val binDir = File(cacheDir, "ffmpegbin")
            if (!binDir.exists()) binDir.mkdirs()
            createEntryPoint(binDir, File(applicationInfo.nativeLibraryDir), "ffmpeg", "libffmpeg.so")
        } catch (e: Exception) {
            Log.e(TAG, "ffmpegExecutable() failed", e)
            null
        }
    }

    private fun stagingDir(): File {
        val dir = File(getExternalFilesDir(null), "downloads")
        if (!dir.exists()) dir.mkdirs()
        return dir
    }

    private fun downloadVideo(url: String, platform: String, quality: Int,
                              outputPath: String, sink: ProgressSink, mode: String): String {
        ensureInitialized()
        // Always write yt-dlp output into the app-private staging directory.
        // `outputPath` is an informational public destination only; the finished
        // file is persisted to the correct public platform folder by
        // persistDownload() via MediaStore (Android 10+) or a direct copy
        // (Android 9-). Using the passed public path here would fail under
        // scoped storage on Android 10+, which is why this mirrors the
        // app-private staging used by the debug path in MainActivity.
        val staging = stagingDir()
        Log.i(TAG, "Download staging directory: ${staging.absolutePath}")

        if (TikTokExtractor.isTikTok(platform, url)) {
            try {
                val nativeJson = TikTokExtractor(sink)
                    .download(url, quality, staging, mode, ffmpegExecutable())
                val nativeObj = JSONObject(nativeJson)
                if (nativeObj.optBoolean("success")) return nativeJson
                Log.w(TAG, "Native TikTok download failed; falling back to Python: $nativeJson")
            } catch (e: Exception) {
                Log.w(TAG, "Native TikTok download threw; falling back to Python: ${e.message}")
            }
        }

        val module = Python.getInstance().getModule("android_backend")
        val pyResult = module.callAttr(
            "download_video", url, platform, quality,
            staging.absolutePath, PyObject.fromJava(sink), mode
        ) ?: return JSONObject().apply {
            put("success", false)
            put("error", "Python download_video() returned None")
        }.toString()
        return pyResult.toString()
    }

    private fun persistDownload(responseJson: String, platform: String,
                                filename: String?): Map<String, Any?> {
        val obj = JSONObject(responseJson)
        if (obj.optBoolean("success") != true) return jsonToMap(responseJson)
        val srcPath = obj.optString("file")
        val titleName = obj.optString("filename").ifEmpty { "video.mp4" }
        val displayName = safeDisplayName(filename) ?: safeDisplayName(titleName) ?: "video.mp4"
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
                persistViaMediaStore(src, displayName, platform)
            } else {
                persistLegacy(src, displayName, platform)
            }
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

    /** Safety-net sanitization: a user-supplied name is never a path. */
    private fun safeDisplayName(name: String?): String? {
        if (name.isNullOrBlank()) return null
        val cleaned = name
            .substringAfterLast('/')
            .substringAfterLast('\\')
            .replace(Regex("[\\x00-\\x1f\\x7f<>:\"|?*]"), " ")
            .trim()
            .trimEnd('.')
        return cleaned.ifBlank { null }
    }

    private fun persistViaMediaStore(src: File, displayName: String, platform: String): Pair<String, String> {
        val resolver = contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val mime = mimeFor(displayName)
        val subfolder = "Nazzelha/${platformFolder(platform)}"
        fun valuesFor(name: String) = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, name)
            put(MediaStore.MediaColumns.MIME_TYPE, mime)
            put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS + "/$subfolder")
            put(MediaStore.MediaColumns.IS_PENDING, 1)
        }
        var uri = resolver.insert(collection, valuesFor(displayName))
        if (uri == null) {
            uri = resolver.insert(collection, valuesFor("Nazzelha_${System.currentTimeMillis()}_$displayName"))
        }
        if (uri == null) throw IOException("MediaStore insert failed")
        resolver.openOutputStream(uri)!!.use { out ->
            src.inputStream().use { input -> input.copyTo(out) }
        }
        val done = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
        resolver.update(uri, done, null, null)
        var relativePath = Environment.DIRECTORY_DOWNLOADS + "/$subfolder"
        var name = displayName
        resolver.query(uri, arrayOf(MediaStore.MediaColumns.RELATIVE_PATH, MediaStore.MediaColumns.DISPLAY_NAME),
            null, null, null)?.use { c ->
            if (c.moveToFirst()) {
                c.getString(0)?.let { relativePath = it.trimEnd('/') }
                c.getString(1)?.let { name = it }
            }
        }
        return Pair("$relativePath/$name", uri.toString())
    }

    private fun persistLegacy(src: File, displayName: String, platform: String): Pair<String, String> {
        val destDir = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
            "Nazzelha/${platformFolder(platform)}"
        )
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
        src.inputStream().use { input -> dest.outputStream().use { output -> input.copyTo(output) } }
        MediaScannerConnection.scanFile(this, arrayOf(dest.absolutePath), arrayOf(mimeFor(dest.name)), null)
        return Pair("Downloads/Nazzelha/${platformFolder(platform)}/${dest.name}", dest.absolutePath)
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
}
