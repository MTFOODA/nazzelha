"""
Video downloader module using yt-dlp and FFmpeg.
Handles YouTube, Facebook, Instagram, TikTok, and X video downloads.
"""

import json
import os
import shutil
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import List, Dict, Any, Callable, Optional

try:
    import yt_dlp
except ImportError:
    yt_dlp = None


# --------------------------------------------------------------------------- #
# TikTok-specific helpers (Windows aware). These are used ONLY for TikTok
# requests and are deliberately NOT applied to YouTube/Facebook/Instagram.
# --------------------------------------------------------------------------- #
# Current desktop-browser User-Agent used only while resolving TikTok short
# links and for the "browser request context" fallback attempt.
_TIKTOK_WEBPAGE_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)

_TIKTOK_HOSTS = ("tiktok.com", "vt.tiktok.com", "vm.tiktok.com")

# Browser-name / executable-path pairs used only to decide whether a real
# browser exists for the optional cookie fallback. Never hard-coded to a
# single browser; the first installed browser is preferred.
_TIKTOK_BROWSER_CHECKS = (
    (
        "edge",
        (
            r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
            r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
        ),
    ),
    (
        "chrome",
        (
            r"C:\Program Files\Google\Chrome\Application\chrome.exe",
            r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        ),
    ),
    ("firefox", (r"C:\Program Files\Mozilla Firefox\firefox.exe",)),
    (
        "brave",
        (r"C:\Program Files\BraveSoftware\Brave Browser\Application\brave.exe",),
    ),
    ("opera", (r"C:\Program Files\Opera\opera.exe",)),
)

# Cross-request TikTok lifecycle tracking (single threaded backend process).
# Used ONLY for pacing/diagnostics of consecutive TikTok extractions; holds
# no cookies, URLs or metadata, so requests stay isolated from each other.
_tiktok_request_counter = 0
_last_tiktok_finish_monotonic = 0.0
_tiktok_consecutive_failures = 0

# Minimum seconds between the END of one TikTok extraction and the START of
# the next. TikTok's anti-bot engine heavily penalises rapid consecutive
# session creation (observed: immediate second requests get risk-blocked
# while spaced ones succeed), so rapid-fire Submits are gently spaced out.
_TIKTOK_MIN_REQUEST_GAP_SECONDS = 6.0


# --------------------------------------------------------------------------- #
# Shared error classification (mirrors android_backend.classify_error).
#
# Extraction failures and media-download failures are different things and
# must be reported differently. Codes:
#   EXTRACTION_FAILED / AUTHENTICATION_REQUIRED / FORMAT_UNAVAILABLE /
#   NETWORK_ERROR / MEDIA_DOWNLOAD_FAILED
#
# SECURITY NOTE: never include cookies, authorization headers, session tokens
# or passwords in messages or logs - only short public yt-dlp error summaries.
# --------------------------------------------------------------------------- #

_AUTH_KEYWORDS = (
    'login', 'log in', 'authentication', 'private video', 'private content',
    'sign in', 'sign-in', 'requires authentication', 'not logged in',
    'unauthorized', 'account required', 'members-only', 'members only',
    'this video is available to', 'confirm your age', 'age-restricted',
    'inappropriate for some users', 'cookies'
)

_FORMAT_KEYWORDS = (
    'requested format is not available', 'no video formats',
    'requested format not available'
)

_NETWORK_KEYWORDS = (
    'timed out', 'timeout', 'connectionreset', 'connection reset',
    'getaddrinfo failed', 'name or service not known',
    'temporary failure in name resolution', 'network is unreachable',
    'no internet', 'connection refused', 'ssl:', 'certificate verify failed'
)

_MEDIA_DOWNLOAD_KEYWORDS = (
    'unable to download video data',
    'unable to download webpage',
    'http error 403', 'http error 410', 'http error 404',
)

_EXTRACTION_KEYWORDS = (
    'unable to extract', 'cannot parse data', 'failed to parse',
    'no video found', 'unsupported url', 'not a valid url', 'invalid url',
    'does not pass filter', 'video unavailable', 'this video is unavailable',
    'not found', 'empty media response', 'sent an empty',
)


def classify_error(error_msg: str, phase: str = "extraction") -> str:
    """Map raw yt-dlp error text to a stable machine-readable code."""
    m = (error_msg or "").lower()

    if any(k in m for k in _FORMAT_KEYWORDS):
        return "FORMAT_UNAVAILABLE"

    if any(k in m for k in _AUTH_KEYWORDS):
        return "AUTHENTICATION_REQUIRED"

    if any(k in m for k in _MEDIA_DOWNLOAD_KEYWORDS) or "http error 403" in m:
        if "unable to download webpage" in m and phase == "extraction":
            if any(k in m for k in _NETWORK_KEYWORDS):
                return "NETWORK_ERROR"
            return "EXTRACTION_FAILED"
        return "MEDIA_DOWNLOAD_FAILED"

    if any(k in m for k in _NETWORK_KEYWORDS):
        return "NETWORK_ERROR"

    if any(k in m for k in _EXTRACTION_KEYWORDS):
        return "EXTRACTION_FAILED"

    # Bare 403/forbidden/429 WITHOUT login/private wording is a refused
    # request (bot protection/geo-block), NOT an authentication problem.
    if '403' in m or 'forbidden' in m or '429' in m or 'too many requests' in m:
        return ("MEDIA_DOWNLOAD_FAILED" if phase == "download"
                else "EXTRACTION_FAILED")

    return "EXTRACTION_FAILED"


_USER_MESSAGES = {
    "EXTRACTION_FAILED": (
        "Could not extract this media. It may be unavailable, deleted, "
        "region-blocked, or temporarily blocked by the platform's automated "
        "protection. Please verify the URL and try again shortly."
    ),
    "AUTHENTICATION_REQUIRED": (
        "This content requires authentication or is private. Logging in via "
        "cookies would be needed to access it."
    ),
    "FORMAT_UNAVAILABLE": (
        "The selected quality is not available for this video. Press SUBMIT "
        "to refresh the available qualities and pick another one."
    ),
    "NETWORK_ERROR": (
        "Network or connection error while contacting the platform. Please "
        "check your internet connection and try again."
    ),
    "MEDIA_DOWNLOAD_FAILED": (
        "The media was found but downloading its data failed. The temporary "
        "stream link may have expired or been refused - please try again."
    ),
}


class VideoDownloader:
    """Handles video extraction and downloading."""

    def __init__(self, progress_callback: Optional[Callable] = None):
        """
        Initialize the downloader.

        Args:
            progress_callback: Optional callback function for download progress.
                              Will be called with progress dict.
        """
        self.progress_callback = progress_callback
        self._download_thread = None
        self._stop_download = False

    def get_available_qualities(self, url: str, platform: str = "youtube") -> Dict[str, Any]:
        """
        Extract available video qualities from a URL.

        Args:
            url: Video URL
            platform: Platform identifier ("youtube", "facebook", "instagram", "tiktok", "x")

        Returns:
            Dict with success status and available qualities (heights as ints)
        """
        if not yt_dlp:
            return {
                "success": False,
                "error": "yt-dlp is not installed. Please run: pip install yt-dlp"
            }

        try:
            if self._is_tiktok(platform, url):
                res = self._extract_tiktok(
                    url,
                    download=False,
                    quality=1080,
                    output_dir=self.get_downloads_directory(),
                )
                if not res["success"]:
                    return {"success": False, "error": res["error"]}
                info = res["info"]
            else:
                with yt_dlp.YoutubeDL({
                    "quiet": True,
                    "no_warnings": True,
                    "socket_timeout": 30
                }) as ydl:
                    info = ydl.extract_info(url, download=False)

            available_heights = set()

            for fmt in info.get("formats", []):
                height = fmt.get("height")
                if height and height > 0:
                    available_heights.add(height)

            qualities = sorted(available_heights)

            if not qualities:
                return {
                    "success": False,
                    "error": "No downloadable video qualities found for this URL."
                }

            return {
                "success": True,
                "qualities": qualities,
                "title": info.get("title", "Video")
            }

        except yt_dlp.utils.DownloadError as e:
            error_msg = str(e)
            code = classify_error(error_msg, phase="extraction")
            return {
                "success": False,
                "error_code": code,
                "error": _USER_MESSAGES[code],
                "technical": error_msg[:300],
            }
        except Exception as e:
            error_msg = str(e)
            code = classify_error(error_msg, phase="extraction")
            return {
                "success": False,
                "error_code": code,
                "error": f"{_USER_MESSAGES[code]} (Details: {error_msg[:200]})",
                "technical": error_msg[:300],
            }

    def download_video(
        self,
        url: str,
        platform: str,
        quality: int,
        output_path: str,
        mode: str = "video"
    ) -> Dict[str, Any]:
        """
        Download a video at specified quality, or audio-only when mode='audio'.

        Args:
            url: Video URL
            platform: Platform identifier
            quality: Desired quality (height in pixels; ignored in audio mode)
            output_path: Directory to save the video
            mode: "video" (default, current behavior) or "audio".

        Returns:
            Dict with success status and file path or error message
        """
        if not yt_dlp:
            return {
                "success": False,
                "error": "yt-dlp is not installed. Please run: pip install yt-dlp"
            }

        try:
            # Ensure output directory exists
            output_dir = Path(output_path)
            output_dir.mkdir(parents=True, exist_ok=True)

            # Check if FFmpeg is available (required for merging AND for
            # audio-only extraction/conversion).
            self._check_ffmpeg()

            if mode == "audio":
                # Audio-only path: download the best audio stream and extract a
                # real MP3 with FFmpeg. NEVER renames an MP4 to MP3.
                if self._is_tiktok(platform, url):
                    # Keep the TikTok fallback cascade for audio too so an
                    # intermittent anti-bot page does not fail audio extraction.
                    res = self._extract_tiktok(
                        url,
                        download=True,
                        quality=quality,
                        output_dir=output_dir,
                        mode="audio",
                    )
                    if not res["success"]:
                        return {"success": False, "error": res["error"]}
                    return {
                        "success": True,
                        "file": res["filepath"],
                        "title": res["info"].get("title", "Audio"),
                    }
                ydl_opts = self._get_yt_dlp_opts(platform, quality, output_dir, mode="audio")
                ydl_opts["progress_hooks"] = [self._progress_hook] if self.progress_callback else []
                with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                    info = ydl.extract_info(url, download=True)
                    filepath = str(Path(ydl.prepare_filename(info)).with_suffix(".mp3"))
                    if not os.path.isfile(filepath) or os.path.getsize(filepath) <= 0:
                        raise RuntimeError("Audio extraction finished but the MP3 is missing or empty")
                    return {
                        "success": True,
                        "file": filepath,
                        "title": info.get("title", "Audio"),
                    }

            # Configure download options based on platform (video mode)
            ydl_opts = self._get_yt_dlp_opts(platform, quality, output_dir)
            ydl_opts["progress_hooks"] = [self._progress_hook] if self.progress_callback else []

            if self._is_tiktok(platform, url):
                res = self._extract_tiktok(
                    url,
                    download=True,
                    quality=quality,
                    output_dir=output_dir,
                )
                if not res["success"]:
                    return {"success": False, "error": res["error"]}
                return {
                    "success": True,
                    "file": res["filepath"],
                    "title": res["info"].get("title", "Video"),
                }

            with yt_dlp.YoutubeDL(ydl_opts) as ydl:
                info = ydl.extract_info(url, download=True)
                filepath = ydl.prepare_filename(info)

                return {
                    "success": True,
                    "file": filepath,
                    "title": info.get("title", "Video")
                }

        except yt_dlp.utils.DownloadError as e:
            # Can be either an extraction failure or a media-download failure;
            # classify_error() distinguishes them and phase="download" makes
            # bare HTTP statuses attribute to the media transfer.
            error_msg = str(e)
            code = classify_error(error_msg, phase="download")
            return {
                "success": False,
                "error_code": code,
                "error": _USER_MESSAGES[code],
                "technical": error_msg[:300],
            }

        except Exception as e:
            error_msg = str(e)
            code = classify_error(error_msg, phase="download")

            # Give actionable feedback when the merge step cannot run.
            if ("ffmpeg" in error_msg.lower()
                    and ("not installed" in error_msg.lower()
                         or "not found" in error_msg.lower()
                         or "aborting" in error_msg.lower())):
                return {
                    "success": False,
                    "error_code": "MEDIA_DOWNLOAD_FAILED",
                    "error": (
                        "The video streams were downloaded but could not be "
                        "merged because FFmpeg is not available. Please install "
                        "FFmpeg and make sure it is on your PATH."
                    )
                }

            return {
                "success": False,
                "error_code": code,
                "error": f"Download failed: {_USER_MESSAGES[code]}",
                "technical": error_msg[:300],
            }

    def _progress_hook(self, d: Dict[str, Any]) -> None:
        """
        Hook for yt-dlp progress updates.

        Args:
            d: Progress dictionary from yt-dlp
        """
        if self.progress_callback:
            if d['status'] == 'downloading':
                percent_text = str(d.get('_percent_str', '0%')).strip().replace('%', '').strip()
                try:
                    percent_value = int(float(percent_text))
                except (TypeError, ValueError):
                    percent_value = 0

                progress = {
                    "event": "progress",
                    "percent": percent_value,
                    "speed": d.get('_speed_str', 'N/A').strip(),
                    "eta": d.get('_eta_str', 'N/A').strip(),
                    "total_bytes": d.get('total_bytes', 0),
                    "downloaded_bytes": d.get('downloaded_bytes', 0),
                }
                self.progress_callback(progress)
            elif d['status'] == 'finished':
                self.progress_callback({
                    "event": "finished",
                    "filename": d.get('filename', '')
                })

    @staticmethod
    def _check_ffmpeg() -> bool:
        """
        Check if FFmpeg is installed.

        Raises:
            RuntimeError: If FFmpeg is not found
        """
        import shutil
        if not shutil.which("ffmpeg"):
            raise RuntimeError(
                "FFmpeg is not installed. Please install FFmpeg from "
                "https://ffmpeg.org/download.html or via package manager."
            )
        return True

    @staticmethod
    def get_downloads_directory() -> str:
        """
        Get the standard Downloads directory for the current OS.

        Returns:
            Path to the Downloads/Nazzelha directory
        """
        if os.name == 'nt':  # Windows
            downloads_dir = Path.home() / "Downloads"
        else:  # Linux/Mac
            downloads_dir = Path.home() / "Downloads"

        nazzelha_dir = downloads_dir / "Nazzelha"
        return str(nazzelha_dir)

    # ------------------------------------------------------------------ #
    # TikTok-specific extraction with progressive fallbacks.
    #
    # TikTok can intermittently serve an anti-bot / "rehydration" challenge
    # page that does NOT contain the __UNIVERSAL_DATA_FOR_REHYDRATION__ script
    # the extractor needs. When that happens yt-dlp raises:
    #   [TikTok] <id>: Unable to extract universal data for rehydration
    #
    # Rather than fail permanently we try several DISTINCT strategies in order
    # (each differs in request context), pausing briefly between attempts.
    # None of these options are applied to YouTube/Facebook/Instagram.
    # ------------------------------------------------------------------ #
    @staticmethod
    def _is_tiktok(platform, url=None):
        """True when the platform/host resolves to a TikTok target."""
        plat = (platform or "").lower()
        if plat in ("tiktok", "vt.tiktok.com", "vm.tiktok.com"):
            return True
        if url:
            low = url.lower()
            return any(host in low for host in _TIKTOK_HOSTS)
        return False

    @staticmethod
    def _impersonation_available() -> bool:
        """True when the optional impersonation dependency is present."""
        try:
            import curl_cffi  # noqa: F401
            return True
        except Exception:
            return False

    @staticmethod
    def _resolve_tiktok_url(url: str) -> str:
        """Resolve vt.tiktok.com / vm.tiktok.com short links to the canonical
        www.tiktok.com URL, preserving any query parameters. Returns the
        original URL unchanged on any network/parse failure so extraction can
        still proceed (yt-dlp itself understands short links)."""
        low = url.lower()
        if "vt.tiktok.com" not in low and "vm.tiktok.com" not in low:
            return url
        try:
            req = urllib.request.Request(
                url,
                headers={
                    "User-Agent": _TIKTOK_WEBPAGE_UA,
                    "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                },
            )
            handler = urllib.request.HTTPRedirectHandler()
            resp = urllib.request.build_opener(handler).open(req, timeout=25)
            final = resp.geturl() or url
            resp.close()
            return final
        except Exception:
            return url

    @staticmethod
    def _detect_browser():
        """Return the name of an installed Windows browser whose cookies could
        optionally be used for a TikTok extraction retry, or None. Paths are
        checked on disk so we never hard-code a browser that is not present."""
        if os.name != "nt":
            return None
        for name, paths in _TIKTOK_BROWSER_CHECKS:
            for candidate in paths:
                try:
                    if os.path.isfile(candidate):
                        return name
                except Exception:
                    continue
        return None

# ------------------------------------------------------------------ #
    # TikTok extraction with a progressive fallback cascade.
    #
    # TikTok can intermittently serve an anti-bot / "rehydration" challenge
    # page that does NOT contain the __UNIVERSAL_DATA_FOR_REHYDRATION__ script
    # the extractor needs, so yt-dlp fails with:
    #   [TikTok] <id>: Unable to extract universal data for rehydration
    #
    # We therefore attempt several DISTINCT strategies in order. Each attempt
    # changes the request context and pauses briefly, so this is never an
    # identical blind retry. Every option below is TikTok-specific and never
    # applied to YouTube/Facebook/Instagram.
    # ------------------------------------------------------------------ #
    def _extract_tiktok(
        self,
        url: str,
        download: bool,
        quality: int = 720,
        output_dir: Optional[str] = None,
        mode: str = "video",
    ) -> Dict[str, Any]:
        """
        TikTok extraction/download using a fallback cascade.

        Attempt A - standard yt-dlp configuration.
        Attempt B - desktop-browser-like request headers (TikTok request only).
        Attempt C - cookies from an installed browser, if one exists.
        Attempt D - impersonation when the optional dependency is available.

        Returns:
            {'success': True, 'info': ..., 'filepath': ...} on success
            {'success': False, 'error': <clean message>} if all attempts fail
        """
        resolved = self._resolve_tiktok_url(url) or url

        global _tiktok_request_counter, _last_tiktok_finish_monotonic
        global _tiktok_consecutive_failures
        _tiktok_request_counter += 1
        req_no = _tiktok_request_counter
        print(f"[TikTok] Request #{req_no} started (pid {os.getpid()})",
              file=sys.stderr)

        # Adaptive inter-request pacing: guarantee a minimum gap since the
        # previous TikTok extraction FINISHED before starting a new one.
        # Rapid-fire Submits are the strongest trigger for TikTok's risk
        # engine (trace evidence: immediate 2nd/3rd requests fail while the
        # same requests succeed when spaced). After a FAILURE the gap
        # escalates (8s + 5s per consecutive failure, capped at 25s) because
        # an active risk-block wave needs longer to clear. Human-paced
        # requests with a natural large gap are never delayed.
        if _last_tiktok_finish_monotonic > 0:
            since_last = time.monotonic() - _last_tiktok_finish_monotonic
            if _tiktok_consecutive_failures > 0:
                required_gap = min(
                    8.0 + 5.0 * _tiktok_consecutive_failures, 25.0)
            else:
                required_gap = _TIKTOK_MIN_REQUEST_GAP_SECONDS
            if since_last < required_gap:
                gap_pause = required_gap - since_last
                print(f"[TikTok] Request #{req_no} pacing {gap_pause:.1f}s "
                      f"since previous request "
                      f"(consecutive failures: {_tiktok_consecutive_failures})",
                      file=sys.stderr)
                time.sleep(gap_pause)

        print("[TikTok] URL detected", file=sys.stderr)
        if resolved != url:
            print(f"[TikTok] Resolved short URL -> {resolved}", file=sys.stderr)

        out_dir = Path(output_dir) if output_dir else Path(self.get_downloads_directory())

        def base_opts() -> dict:
            opts = {
                # TikTok exposes progressive (muxed) formats whose lowest
                # height can exceed the requested one, so end with a plain
                # "/best" guard instead of failing when nothing matches
                # "[height<=quality]".
                "format": (
                    f"bestvideo[height<={quality}]"
                    f"+bestaudio/best[height<={quality}]/best"
                ),
                "merge_output_format": "mp4",
                "outtmpl": str(out_dir / "%(title)s.%(ext)s"),
                "noplaylist": True,
                "quiet": True,
                "no_warnings": True,
                "noprogress": True,
                "referer": "https://www.tiktok.com/",
            }
            if mode == "audio":
                opts["format"] = "bestaudio/best"
                opts.pop("merge_output_format", None)
                opts["postprocessors"] = [{
                    "key": "FFmpegExtractAudio",
                    "preferredcodec": "mp3",
                    "preferredquality": "192",
                }]
            return opts

        # Attempt A: normal yt-dlp configuration.
        attempts = [("standard", base_opts())]

        # Attempt B: TikTok's modern mobile API path (iid-first app_info selects
        # api16-normal-*.tiktokv.com, which does NOT require TLS impersonation).
        import random as _random
        app_api = base_opts()
        _tt_device_id = str(_random.randint(7250000000000000000, 7325099899999994577))
        _tt_iid = str(_random.randint(7250000000000000000, 7325099898989999999))
        app_api["extractor_args"] = {
            "TikTok": {
                "device_id": [_tt_device_id],
                "app_info": [_tt_iid + "/musical_ly/35.1.3/2023501030/0"],
                "api_hostname": ["api16-normal-c-useast1a.tiktokv.com"],
            }
        }
        attempts.append(("app_api", app_api))

        # Attempt C: cookies from an installed Windows browser (if present).
        browser = self._detect_browser()
        if browser is not None:
            try:
                cookie_opts = base_opts()
                cookie_opts["cookiesfrombrowser"] = (browser, None, None, None)
                attempts.append(("browser_cookies", cookie_opts))
            except Exception:
                pass

        # Attempt D: impersonation when the optional dependency is available.
        if self._impersonation_available():
            try:
                # NOTE: this yt-dlp build asserts inside is_supported_target when
                # the option is a plain string, so pass a real target object.
                from yt_dlp.networking.impersonate import ImpersonateTarget
                imp_opts = base_opts()
                imp_opts["impersonate"] = ImpersonateTarget.from_str("chrome")
                attempts.append(("impersonation", imp_opts))
            except Exception:
                pass

        last_error = None
        # Hard overall deadline for METADATA extraction. Downloads are exempt
        # from the deadline (merging long videos legitimately takes minutes)
        # but get their own bounded cool-off below. The cascade budget (55s)
        # leaves room for the cool-off rescue, and everything is capped so
        # the JSON response always reaches Flutter inside its 170s timeout.
        hard_deadline = None if download else time.monotonic() + 140
        deadline = None if download else time.monotonic() + 55
        for attempt_no, (name, opts) in enumerate(attempts, start=1):
            if deadline is not None and attempt_no > 1 and time.monotonic() >= deadline:
                print("[TikTok] Extraction time budget exhausted; stopping fallbacks",
                      file=sys.stderr)
                break
            if download:
                opts["progress_hooks"] = (
                    [self._progress_hook] if self.progress_callback else []
                )
            try:
                print(f"[TikTok] Attempting {name} extraction", file=sys.stderr)
                with yt_dlp.YoutubeDL(opts) as ydl:
                    info = ydl.extract_info(resolved, download=download)
                    if download:
                        filepath = ydl.prepare_filename(info)
                        if mode == "audio":
                            filepath = str(Path(filepath).with_suffix(".mp3"))
                if download:
                    fp = Path(filepath)
                    if not fp.exists() or fp.stat().st_size <= 0:
                        raise RuntimeError("Downloaded file is missing or empty")
                print(f"[TikTok] Extraction successful via {name}", file=sys.stderr)
                _last_tiktok_finish_monotonic = time.monotonic()
                _tiktok_consecutive_failures = 0
                print(f"[TikTok] Request #{req_no} success (method: {name})",
                      file=sys.stderr)
                return {"success": True, "info": info, "filepath": filepath}
            except yt_dlp.utils.DownloadError as e:
                last_error = f"DownloadError: {e}"
                print(f"[TikTok] {name} failed: {str(e)[:180]}", file=sys.stderr)
            except Exception as e:
                last_error = f"{type(e).__name__}: {e}"
                print(f"[TikTok] {name} failed: {type(e).__name__}: {str(e)[:180]}",
                      file=sys.stderr)
            # Progressive pause between DISTINCT attempts (1s, 2s, 3s ...),
            # clamped so we never sleep past the overall deadline.
            pause = min(1.0 * attempt_no, 4.0)
            if deadline is not None:
                pause = min(pause, max(0.0, deadline - time.monotonic()))
            if pause > 0:
                time.sleep(pause)

        # NOTE (Phase 17): the old "cool-off rescue" (25-30s sleep + one more
        # identical request) was REMOVED. It never changed the HTTP response -
        # the challenge is served deterministically without TLS impersonation on
        # Android. This Python cascade is a bounded last-resort fallback only.

        _last_tiktok_finish_monotonic = time.monotonic()
        _tiktok_consecutive_failures += 1
        print(f"[TikTok] Request #{req_no} failed all attempts "
              f"(consecutive failures: {_tiktok_consecutive_failures})",
              file=sys.stderr)
        print(f"[TikTok] Last technical error: {last_error}", file=sys.stderr)

        classified = self._classify_tiktok_error(last_error or "")
        return {"success": False, "error": classified}

    @staticmethod
    def _classify_tiktok_error(technical: str) -> str:
        """Map raw yt-dlp error text to a precise user-facing message."""
        m = (technical or "").lower()
        if "ip address is blocked" in m or "10204" in m:
            return (
                "TikTok has temporarily blocked this network from its servers. "
                "Please wait a few minutes before trying again."
            )
        if "universal data" in m or "rehydration" in m or "unexpected response" in m:
            return (
                "TikTok's bot protection blocked this request. This is usually "
                "temporary - please try again in a moment. If it keeps failing, "
                "wait a couple of minutes between attempts."
            )
        if "requested format" in m:
            return (
                "The selected quality is no longer available for this video. "
                "Please press SUBMIT to refresh the available qualities."
            )
        if ("video unavailable" in m or "deleted" in m or "private" in m
                or "login" in m or "10216" in m or "10222" in m):
            return (
                "This TikTok video is unavailable, private, or requires login."
            )
        if any(k in m for k in ("timed out", "timeout", "connection",
                                "network", "unable to download")):
            return (
                "Network problem while contacting TikTok. Please check your "
                "internet connection and try again."
            )
        if "invalid url" in m or "not a valid url" in m or "unsupported url" in m:
            return "This doesn't look like a supported TikTok URL."
        return (
            f"TikTok extraction failed. Please try again in a moment. "
            f"(Details: {technical[:160]})"
        )


    def _get_yt_dlp_opts(self, platform: str, quality: int, output_dir: Path,
                        mode: str = "video") -> dict:
        """
        Get yt-dlp options configured for the specific platform and mode.

        Args:
            platform: Platform identifier
            quality: Desired quality height
            output_dir: Output directory path
            mode: "video" (default) or "audio" (best audio -> MP3)

        Returns:
            Configured yt-dlp options dictionary
        """
        # Platform-specific extractor arguments and URL handling
        platform = platform.lower()

        # Common options
        base_opts = {
            # Quality selection: cap video height at the user's choice. The
            # trailing fallbacks only fire when the capped selectors match
            # NOTHING - e.g. Instagram reels expose progressive MP4s without
            # height metadata and DASH video without a separate audio track -
            # so normal YouTube/Facebook quality selection is unchanged.
            "format": (
                f"bestvideo[height<={quality}]"
                f"+bestaudio/"
                f"best[height<={quality}]"
                f"/bestvideo+bestaudio"
                f"/best"
            ),
            "merge_output_format": "mp4",
            "outtmpl": str(output_dir / "%(title)s.%(ext)s"),
            "noplaylist": True,
            "quiet": True,
            "no_warnings": True,
            "noprogress": True,
        }

        if mode == "audio":
            # Audio-only: select the best audio stream (falling back to any
            # media whose audio can be extracted), then have FFmpeg convert it
            # to a real MP3. yt-dlp's FFmpegExtractAudio postprocessor writes
            # "<title>.mp3" and removes the original stream file.
            base_opts["format"] = "bestaudio/best"
            base_opts.pop("merge_output_format", None)
            base_opts["postprocessors"] = [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "192",
            }]

        # Platform-specific configurations
        if platform == "youtube" or platform == "youtu.be":
            # yt-dlp requires a JavaScript runtime to solve YouTube's JS
            # challenges. Without one it falls back to player clients whose
            # media URLs return HTTP 403 during download ("unable to download
            # video data: HTTP Error 403: Forbidden"). Deno is yt-dlp's only
            # default-enabled runtime but is rarely installed on Windows;
            # enable Node.js when it is available (Windows-only, matching the
            # desktop backend environment).
            if os.name == "nt" and shutil.which("node"):
                base_opts["js_runtimes"] = {"node": {}}

        elif platform in ("facebook", "fb.watch"):
            base_opts.update({
                # Facebook often needs referer and user-agent
                "referer": "https://www.facebook.com/",
                "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            })

        elif platform in ("instagram", "instagr.am"):
            base_opts.update({
                "geo_bypass": True,
                "geo_bypass_country": "US",
                "referer": "https://www.instagram.com/",
                "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                # Instagram may need extra settings for private content
            })

        elif platform in ("tiktok", "vt.tiktok.com", "vm.tiktok.com"):
            base_opts.update({
                "referer": "https://www.tiktok.com/",
                "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
                # TikTok may need cookies or additional headers
            })

        else:
            # Default options for unknown platforms
            base_opts.update({
                "user_agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            })

        return base_opts


def validate_url(url: str, platform: Optional[str] = None) -> bool:
    """
    Basic URL validation.

    Args:
        url: URL to validate
        platform: Optional platform to validate against

    Returns:
        True if URL is valid
    """
    url = url.strip()
    
    if not url:
        return False

    # Check if URL starts with http or https
    if not url.lower().startswith(('http://', 'https://')):
        return False

    # Basic platform validation
    if platform:
        platform_lower = platform.lower()
        if platform_lower in ("youtube", "youtu.be"):
            return any(host in url.lower() for host in ['youtube.com', 'youtu.be'])
        elif platform_lower in ("facebook", "fb.watch"):
            return 'facebook.com' in url.lower() or 'fb.watch' in url.lower()
        elif platform_lower in ("instagram", "instagr.am"):
            return 'instagram.com' in url.lower() or 'instagr.am' in url.lower()
        elif platform_lower in ("tiktok", "vt.tiktok.com", "vm.tiktok.com"):
            return any(host in url.lower() for host in ['tiktok.com', 'vt.tiktok.com', 'vm.tiktok.com'])

    return True
