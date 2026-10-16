package com.example.nazzelha

import android.util.Log
import java.io.File
import java.io.IOException
import java.util.concurrent.TimeUnit
import org.json.JSONObject
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Native Android TikTok extraction adapter (embed-v1 strategy).
 *
 * WHY THIS EXISTS
 * ---------------
 * The Python (yt-dlp) TikTok extractor always fetches the webpage with
 * `impersonate=True`. On Android no TLS-impersonation provider exists
 * (curl_cffi ships no Android native wheels and Chaquopy has no libcurl), so
 * yt-dlp silently drops impersonation and every webpage request lands on
 * TikTok's anti-bot challenge:
 *
 *     [TikTok] Solving JS challenge ...
 *     ERROR: Unable to extract universal data for rehydration
 *
 * Verified on-device: retries, User-Agent swaps and app_api extractor args do
 * NOT change the HTTP response because the block is TLS-fingerprint based.
 *
 * STRATEGY (Option B/C - native networking; yt-dlp untouched for other sites)
 * TikTok's public EMBED page (https://www.tiktok.com/embed/<id>) is served to
 * plain browser clients WITHOUT the bot challenge. It contains the real item
 * JSON: title, videoMeta (width/height/duration) and signed progressive MP4
 * URLs. Validated end-to-end: short-URL resolve -> embed JSON -> HTTP 206
 * video/mp4 download with a valid ftyp header.
 *
 * The endpoint rate-limits per IP (HTTP 503 "overload-protect"), so we use a
 * small bounded backoff (3 attempts max) - NOT retry spam.
 *
 * SECURITY: never logs cookies, tokens, signed URLs or page bodies - only
 * short status labels. All traffic is plain public GETs over HTTPS.
 */
class TikTokExtractor(private val progressSink: ProgressSink?) {

    private val TAG = "NazzelhaTikTok"

    data class Video(
        val id: String,
        val title: String,
        val durationSec: Double?,
        val width: Int?,
        val height: Int?,
        val urls: List<String>,
    )

    companion object {
        private val HOSTS = listOf("tiktok.com", "vt.tiktok.com", "vm.tiktok.com")

        fun isTikTok(platform: String, url: String): Boolean {
            val p = platform.lowercase()
            if (p == "tiktok" || p == "vt.tiktok.com" || p == "vm.tiktok.com") return true
            val u = url.lowercase()
            return u.startsWith("https://") && HOSTS.any { u.contains(it) }
        }

        // Single stable Android Chrome UA (NOT random rotation).
        private const val UA =
            "Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/131.0.0.0 Mobile Safari/537.36"

        // Bounded embed fetch: 3 attempts max with fixed backoffs. This exists
        // only because the endpoint answers 503 "overload-protect" when the
        // same IP queries it repeatedly within seconds.
        private val EMBED_BACKOFF_MS = longArrayOf(0, 5_000, 15_000)
    }

    private fun client(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(25, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    private fun pageRequest(url: String): Request = Request.Builder()
        .url(url)
        .header("User-Agent", UA)
        .header("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
        .header("Accept-Language", "en-US,en;q=0.9")
        .header("Referer", "https://www.tiktok.com/")
        .build()
    // ------------------------------------------------------------------ #
    // Public API (same JSON contract as the Python backend)
    // ------------------------------------------------------------------ #

    /** Extract metadata + real qualities. Returns a JSON string. */
    fun extractQualitiesJson(url: String): String {
        return try {
            val video = fetchVideo(url)
            val height = video.height
            if (height == null || video.urls.isEmpty()) {
                JSONObject().apply {
                    put("success", false)
                    put("error_code", "EXTRACTION_FAILED")
                    put("error", "This TikTok post has no downloadable video stream.")
                }.toString()
            } else {
                JSONObject().apply {
                    put("success", true)
                    // REAL height from videoMeta - never a fabricated list.
                    put("qualities", org.json.JSONArray(listOf(height)))
                    put("title", video.title)
                    put("duration", video.durationSec ?: 0.0)
                }.toString()
            }
        } catch (e: Exception) {
            failureJson(e, "extraction")
        }
    }

    /** Download the real progressive MP4 into stagingDir. Returns a JSON string.
     *
     * mode="video" preserves the existing behavior exactly.
     * mode="audio" downloads the progressive MP4 (the only source TikTok
     * exposes) and extracts a real MP3 track from it with the bundled FFmpeg,
     * so the result is an actual audio file - never a renamed MP4.
     */
    fun download(url: String, quality: Int, stagingDir: File,
                 mode: String = "video", ffmpegPath: String? = null): String {
        return try {
            val video = fetchVideo(url)
            if (video.urls.isEmpty()) {
                return JSONObject().apply {
                    put("success", false)
                    put("error_code", "EXTRACTION_FAILED")
                    put("error", "This TikTok post has no downloadable media stream.")
                }.toString()
            }
            if (mode == "audio") {
                return downloadAudio(video, stagingDir, ffmpegPath)
            }
            val out = File(stagingDir, "TikTok_${video.id}.mp4")
            downloadToFile(video.urls.first(), out, video.title)
            if (!out.exists() || out.length() <= 0L) {
                throw IOException("downloaded file is missing or empty")
            }
            JSONObject().apply {
                put("success", true)
                put("mode", "video")
                // Match the Python download_video() JSON contract consumed by
                // MainActivity.persistDownload(): "file" (staged path),
                // "filename", "title", "size".
                put("file", out.absolutePath)
                put("filename", out.name)
                put("title", video.title)
                put("size", out.length())
                put("diagnostics", JSONObject().apply {
                    put("strategy", "native_embed")
                    put("video_id", video.id)
                })
            }.toString()
        } catch (e: Exception) {
            failureJson(e, "download")
        }
    }

    /** Audio-only: download the progressive MP4, then extract MP3 with FFmpeg. */
    private fun downloadAudio(video: Video, stagingDir: File, ffmpegPath: String?): String {
        val exe = ffmpegPath
        if (exe.isNullOrEmpty() || !File(exe).exists()) {
            return JSONObject().apply {
                put("success", false)
                put("error_code", "AUDIO_EXTRACTION_FAILED")
                put("error",
                    "Audio extraction requires FFmpeg, which is not available on this device.")
            }.toString()
        }
        val mp4 = File(stagingDir, "TikTok_${video.id}_src.mp4")
        val out = File(stagingDir, "TikTok_${video.id}.mp3")
        try {
            downloadToFile(video.urls.first(), mp4, video.title)
            if (!extractMp3(exe, mp4, out)) {
                throw IOException("FFmpeg audio extraction produced no MP3")
            }
            mp4.delete() // staging intermediate only
            return JSONObject().apply {
                put("success", true)
                put("mode", "audio")
                put("file", out.absolutePath)
                put("filename", out.name)
                put("title", video.title)
                put("size", out.length())
                put("diagnostics", JSONObject().apply {
                    put("strategy", "native_embed_ffmpeg_audio")
                    put("video_id", video.id)
                })
            }.toString()
        } catch (e: Exception) {
            out.delete()
            mp4.delete()
            return failureJson(e, "download")
        }
    }

    /**
     * Convert [input] to an MP3 at [output] with the bundled FFmpeg binary.
     * Prefers libmp3lame and falls back to FFmpeg's native MP3 encoder so the
     * conversion works across builds that ship different codec configurations.
     */
    private fun extractMp3(exe: String, input: File, output: File): Boolean {
        for (codec in listOf("libmp3lame", "mp3")) {
            val process = ProcessBuilder(
                exe, "-y", "-loglevel", "error",
                "-i", input.absolutePath,
                "-vn", "-c:a", codec, "-b:a", "192k", "-id3v2_version", "3",
                output.absolutePath
            ).redirectErrorStream(true).start()
            val detail = StringBuilder()
            Thread {
                try {
                    process.inputStream.bufferedReader().useLines { lines ->
                        lines.forEach { line -> if (line.isNotBlank()) detail.append(line).append('\n') }
                    }
                } catch (_: Exception) {
                    // stream closed on timeout - ignore
                }
            }.start()
            val done = process.waitFor(300, TimeUnit.SECONDS)
            process.destroy()
            if (!done) throw IOException("FFmpeg timed out extracting audio")
            if (process.exitValue() == 0 && output.exists() && output.length() > 0L) {
                return true
            }
            output.delete()
        }
        return false
    }

    // ------------------------------------------------------------------ #
    // Core: resolve id -> embed page -> item JSON
    // ------------------------------------------------------------------ #

    private fun fetchVideo(url: String): Video {
        val id = resolveVideoId(url)
            ?: throw IOException("could not resolve a TikTok video id from the URL")
        Log.i(TAG, "video id resolved: $id")
        val html = fetchEmbedHtml(id)
        return parseEmbedItem(html, id)
            ?: throw IOException("embed page did not contain the video item")
    }

    /** Follow short links (vt/vm.tiktok.com) and pull the numeric video id. */
    private fun resolveVideoId(url: String): String? {
        val direct = Regex("/(?:video|photo|v)/(\\d+)").find(url)?.groupValues?.get(1)
        if (direct != null) return direct
        return try {
            client().newCall(pageRequest(url)).execute().use { resp ->
                if (!resp.isSuccessful) {
                    Log.w(TAG, "short-URL resolve status=${resp.code}")
                    return null
                }
                val finalUrl = resp.request.url.toString()
                Log.i(TAG, "resolved short URL host=${resp.request.url.host}")
                Regex("/(?:video|photo|v)/(\\d+)").find(finalUrl)?.groupValues?.get(1)
            }
        } catch (e: Exception) {
            Log.w(TAG, "short-URL resolve failed: ${e.message}")
            null
        }
    }

    /**
     * Fetch the public embed page with bounded backoff. Raises TikTokChallenge
     * only if every attempt fails, so the UI gets an honest, retryable state.
     */
    private fun fetchEmbedHtml(videoId: String): String {
        var lastCode = 0
        var lastBody = ""
        for ((idx, backoff) in EMBED_BACKOFF_MS.withIndex()) {
            if (backoff > 0) {
                Log.i(TAG, "embed attempt ${idx + 1} backing off ${backoff / 1000}s")
                Thread.sleep(backoff)
            }
            try {
                client().newCall(pageRequest("https://www.tiktok.com/embed/$videoId"))
                    .execute().use { resp ->
                        val body = resp.body?.string().orEmpty()
                        lastCode = resp.code
                        lastBody = body
                        Log.i(TAG, "embed attempt ${idx + 1}: status=${resp.code} len=${body.length}")
                        if (resp.isSuccessful && looksLikeItemPage(body, videoId)) {
                            return body
                        }
                    }
            } catch (e: Exception) {
                Log.w(TAG, "embed attempt ${idx + 1} network error: ${e.message}")
            }
        }
        return if (lastCode == 503 || lastCode == 429 || isChallenge(lastBody)) {
            throw TikTokChallenge()
        } else {
            throw IOException("embed endpoint returned HTTP $lastCode")
        }
    }

    // ------------------------------------------------------------------ #
    // Embed-page item parsing (mirrors the validated Windows probe)
    // ------------------------------------------------------------------ #

    /** Quick check that the fetched page really contains the video item. */
    private fun looksLikeItemPage(body: String, videoId: String): Boolean =
        body.contains("\"id\":\"$videoId\"")

    /**
     * True when a body is TikTok's anti-bot/rate-limit interstitial rather
     * than the real embed page. Conservative: only obvious markers count, so
     * a valid page is never misclassified as a challenge.
     */
    private fun isChallenge(body: String): Boolean {
        val b = body.lowercase()
        return "captcha" in b || "verify to continue" in b || "ray id" in b
    }

    /**
     * Pull the item JSON object containing `"id":"<videoId>"` out of the embed
     * page (brace-depth matching with string awareness, identical to the
     * validated probe) and map it to a [Video]. Returns null when the page
     * carries no item for this id.
     */
    private fun parseEmbedItem(html: String, videoId: String): Video? {
        val marker = "\"id\":\"$videoId\""
        val markerStart = html.indexOf(marker)
        if (markerStart < 0) return null
        val objStart = html.lastIndexOf('{', markerStart)
        if (objStart < 0) return null

        var depth = 0
        var inStr = false
        var esc = false
        var objEnd = -1
        for (i in objStart until html.length) {
            val c = html[i]
            if (esc) { esc = false; continue }
            when {
                c == '\\' && inStr -> esc = true
                c == '"' -> inStr = !inStr
                !inStr && c == '{' -> depth++
                !inStr && c == '}' -> {
                    depth--
                    if (depth == 0) { objEnd = i + 1; break }
                }
            }
        }
        if (objEnd < 0) return null

        return try {
            val item = JSONObject(html.substring(objStart, objEnd))
            val video = item.optJSONObject("video") ?: JSONObject()
            val meta = video.optJSONObject("videoMeta") ?: JSONObject()
            val urls = mutableListOf<String>()
            video.optJSONArray("urls")?.let { arr ->
                for (i in 0 until arr.length()) {
                    val u = arr.optString(i, "")
                    if (u.isNotEmpty()) urls.add(u)
                }
            }
            val duration: Double? =
                if (meta.has("duration"))
                    meta.optDouble("duration").takeIf { !it.isNaN() } else null
            Video(
                id = videoId,
                title = item.optString("text", "").ifEmpty { "TikTok $videoId" },
                durationSec = duration,
                width = if (meta.has("width"))
                    meta.optInt("width", -1).takeIf { it > 0 } else null,
                height = if (meta.has("height"))
                    meta.optInt("height", -1).takeIf { it > 0 } else null,
                urls = urls,
            )
        } catch (e: Exception) {
            Log.w(TAG, "embed item parse failed: ${e.message}")
            null
        }
    }

    // ------------------------------------------------------------------ #
    // Media download (progressive MP4, throttled progress events)
    // ------------------------------------------------------------------ #

    /**
     * Stream the progressive MP4 to [out] and forward progress events in the
     * same JSON shape the Python yt-dlp hook emits, so Flutter needs no
     * platform-specific handling. Throttled to one event per 400 ms / change
     * of integer percentage.
     */
    private fun downloadToFile(url: String, out: File, title: String) {
        val req = Request.Builder()
            .url(url)
            .header("User-Agent", UA)
            .header("Referer", "https://www.tiktok.com/")
            .build()
        client().newCall(req).execute().use { resp ->
            if (!resp.isSuccessful) {
                throw IOException("media request returned HTTP ${resp.code}")
            }
                        val body = resp.body ?: throw IOException("empty media response body")
            val total = body.contentLength()
            out.parentFile?.mkdirs()
            var written = 0L
            var lastPercent = -1
            var lastEmit = 0L
            // Speed measurement (monotonic clock): instantaneous rate over the
            // window since the previous EMITTED sample, smoothed with a light
            // EMA so the displayed value stays realistic (no wild spikes).
            var windowStart = android.os.SystemClock.elapsedRealtime()
            var windowBytes = 0L
            var smoothSpeed = 0.0
            body.byteStream().use { input ->
                java.io.FileOutputStream(out).use { output ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        output.write(buf, 0, n)
                        written += n
                        if (progressSink != null && total > 0) {
                            val pct = (written * 100.0 / total).toInt()
                            val now = android.os.SystemClock.elapsedRealtime()
                            if (pct != lastPercent && now - lastEmit >= 400) {
                                val windowMs = now - windowStart
                                if (windowMs >= 250) {
                                    val inst = (written - windowBytes) * 1000.0 / windowMs
                                    smoothSpeed =
                                        if (smoothSpeed <= 0.0) inst
                                        else 0.5 * inst + 0.5 * smoothSpeed
                                    windowStart = now
                                    windowBytes = written
                                }
                                val speedStr =
                                    if (smoothSpeed > 0.0) formatBytes(smoothSpeed) + "/s" else "N/A"
                                val remaining = (total - written).coerceAtLeast(0L)
                                val etaStr =
                                    if (smoothSpeed > 0.0) formatSeconds((remaining / smoothSpeed).toLong())
                                    else "N/A"
                                Log.i(TAG, "[TikTokProgress] downloaded=$written " +
                                        "total=$total progress=$pct " +
                                        "speed=${smoothSpeed.toLong()} B/s eta=$etaStr")
                                lastPercent = pct
                                lastEmit = now
                                progressSink.send(progressJson(
                                    "downloading", pct.toDouble(), written, total,
                                    out.name, speedStr, etaStr))
                            }
                        }
                    }
                }
            }
            // Finished event matches the Python hook contract exactly
            // (speed "N/A", eta "00:00").
            progressSink?.send(progressJson(
                "finished", 100.0, written, total, out.name, "N/A", "00:00"))
        }
    }

    private fun progressJson(status: String, percent: Double, done: Long,
                             total: Long, filename: String,
                             speed: String = "N/A",
                             eta: String = if (status == "finished") "00:00" else "N/A"): String =
        JSONObject().apply {
            put("event", "progress")
            put("status", status)
            put("percent", percent)
            put("downloaded_bytes", done)
            put("total_bytes", total)
            put("speed", speed)
            put("eta", eta)
            put("filename", filename)
        }.toString()

    /** yt-dlp-style human-readable size, e.g. "2.40MiB" (matches the strings
     *  the Python `_speed_str` hook emits, which the Flutter UI formats). */
    private fun formatBytes(bytesPerSecond: Double): String {
        val units = arrayOf("B", "KiB", "MiB", "GiB")
        var v = bytesPerSecond
        var u = 0
        while (v >= 1024.0 && u < units.size - 1) {
            v /= 1024.0
            u++
        }
        return if (u == 0) "${v.toLong()}${units[u]}" else String.format("%.2f%s", v, units[u])
    }

    /** yt-dlp-style ETA: seconds -> "00:08" / "01:05:32" (or "00:00" when 0). */
    private fun formatSeconds(totalSeconds: Long): String {
        val s = totalSeconds.coerceAtLeast(0L)
        val h = s / 3600
        val m = (s % 3600) / 60
        val sec = s % 60
        return if (h > 0) String.format("%02d:%02d:%02d", h, m, sec)
        else String.format("%02d:%02d", m, sec)
    }

    // ------------------------------------------------------------------ #
    // Structured failure (same contract as the Python backend)
    // ------------------------------------------------------------------ #

    private fun failureJson(e: Exception, phase: String): String {
        val challenge = e is TikTokChallenge
        val code = if (challenge) "TIKTOK_CHALLENGE" else "EXTRACTION_FAILED"
        Log.w(TAG, "failure[$phase]: code=$code msg=${e.message}")
        return JSONObject().apply {
            put("success", false)
            put("error_code", code)
            put("error", if (challenge)
                "TikTok is temporarily rate-limiting this network. " +
                    "Please wait a moment and try again."
            else
                "Could not extract this TikTok video. It may be unavailable, " +
                    "deleted, or region-blocked.")
            put("technical", ("${e.javaClass.simpleName}: ${e.message ?: ""}").take(300))
            put("diagnostics", JSONObject().put("phase", phase))
        }.toString()
    }
}

/** Raised when TikTok answers every bounded attempt with its anti-bot page. */
class TikTokChallenge : IOException("TikTok served an anti-bot challenge page")

