"""
Android backend for Nazzelha video downloader.
Uses yt-dlp via Chaquopy to provide video extraction and downloading on Android.

All public functions return JSON-encoded strings instead of Python dicts.
This is critical because Chaquopy's PyObject.toJava() cannot convert
Python dict/list objects to java.util.Map/java.util.List — it throws
"TypeError: Cannot convert dict object to java.util.Map".
By returning JSON strings, the Kotlin bridge layer parses them safely
with org.json.JSONObject / org.json.JSONArray, which produces proper
Java collections that Flutter's MethodChannel can serialize.
"""

import json
import os
import platform
import subprocess
import sys
import tempfile
import time
import traceback
import urllib.request
import urllib.error
from pathlib import Path
from typing import Dict, Any, Optional, List

try:
    import yt_dlp
except ImportError:
    yt_dlp = None

# FFmpeg runtime configuration, populated by initialize() from values passed
# by MainActivity (see prepareFFmpegRuntime there).
_FFMPEG_BIN_DIR: Optional[str] = None   # directory containing "ffmpeg"/"ffprobe"
_FFMPEG_LIB_DIR: Optional[str] = None   # directory containing libav*.so
_ANDROID_ABI: str = "unknown"


def _configure_ffmpeg_environment() -> None:
    """Make the bundled FFmpeg shared libraries discoverable at spawn time.

    The executables live in nativeLibraryDir but link against libav*.so files
    that are extracted into a private app directory. Setting LD_LIBRARY_PATH on
    the process environment means every child process spawned by yt-dlp
    inherits it and the dynamic linker can resolve those libraries.
    """
    if _FFMPEG_LIB_DIR and os.path.isdir(_FFMPEG_LIB_DIR):
        existing = os.environ.get("LD_LIBRARY_PATH", "")
        parts = [_FFMPEG_LIB_DIR]
        if existing and _FFMPEG_LIB_DIR not in existing.split(":"):
            parts.append(existing)
        os.environ["LD_LIBRARY_PATH"] = ":".join(parts)


def _verify_ffmpeg(ffmpeg_path: str) -> Dict[str, Any]:
    """Test-execute the bundled FFmpeg binary and report the result."""
    result: Dict[str, Any] = {
        "exists": os.path.isfile(ffmpeg_path),
        "executable": False,
        "run_ok": False,
        "version_line": "",
        "error": ""
    }
    if not result["exists"]:
        result["error"] = "FFmpeg binary not found at expected path"
        return result

    result["executable"] = os.access(ffmpeg_path, os.X_OK)
    try:
        proc = subprocess.run(
            [ffmpeg_path, "-version"],
            capture_output=True,
            text=True,
            timeout=30,
        )
        first_line = (proc.stdout or "").strip().splitlines()
        result["version_line"] = first_line[0] if first_line else ""
        if proc.returncode == 0:
            result["run_ok"] = True
        else:
            result["error"] = f"exit code {proc.returncode}: {(proc.stderr or '').strip()[:300]}"
    except Exception as exc:
        result["error"] = f"{type(exc).__name__}: {exc}"
    return result


_TEMP_DIR: Optional[str] = None


def _setup_writable_temp(temp_dir: str) -> Dict[str, Any]:
    """Ensure Python/yt-dlp use a WRITABLE, app-private temp directory.

    On Android the default tempfile location is /tmp which does not exist or is
    read-only, so any code that calls tempfile (yt-dlp internals, HTTP spooling,
    etc.) crashes with 'OSError: [Errno 30] Read-only file system'. MainActivity
    supplies context.cacheDir/.../pytmp (writable, app-private); here we point
    Python's tempfile and the TMPDIR/TEMP/TMP env vars at it and verify with a
    real write/read/delete round-trip (existence alone is not sufficient).
    """
    global _TEMP_DIR
    candidate = temp_dir or ""
    if not candidate:
        try:
            candidate = os.path.join(str(Path.home()), ".nazzelha_tmp")
        except Exception:
            candidate = ""

    result = {"path": candidate, "writable": False, "error": ""}
    try:
        if not candidate:
            raise ValueError("no usable temp directory candidate")
        os.makedirs(candidate, exist_ok=True)
        os.environ["TMPDIR"] = candidate
        os.environ["TEMP"] = candidate
        os.environ["TMP"] = candidate
        tempfile.tempdir = candidate
        probe_name = os.path.join(candidate, "nazzelha_tmp_probe.bin")
        with open(probe_name, "wb") as fh:
            fh.write(b"probe")
        with open(probe_name, "rb") as fh:
            data = fh.read()
        if data != b"probe":
            raise IOError("write/read mismatch in temp dir")
        os.remove(probe_name)
        result["writable"] = True
        _TEMP_DIR = candidate
    except Exception as exc:
        result["writable"] = False
        result["error"] = f"{type(exc).__name__}: {exc}"
    _diag_log(f"temp_dir={candidate} writable={result['writable']}")
    if result["error"]:
        _diag_log(f"temp_dir error={result['error']}")
    return result


def _ensure_app_temp() -> Dict[str, Any]:
    """Force Python's tempfile layer onto a writable, app-private directory.

    On Android `tempfile.gettempdir()` is lazily cached on first use; if that
    first use happens before (or instead of) initialize()'s setup, it caches the
    read-only `/tmp` default and every later tempfile.mkstemp /
    NamedTemporaryFile call crashes with `OSError: [Errno 30] Read-only file
    system: '/tmpXXXX.tmp'`. yt-dlp triggers such a call (cache/part files,
    cookie-DB copies, curl_cffi cache path on Windows) and the crash is then
    misreported as "Could not extract this media".

    Idempotent and cheap: re-asserts env vars AND `tempfile.tempdir` (which
    overrides the cached default) at every extraction entry point, then proves
    writability with a real write/read/delete probe.
    """
    global _TEMP_DIR
    candidate = _TEMP_DIR
    if not candidate:
        for cand in (
            os.environ.get("TMPDIR"),
            os.environ.get("TEMP"),
            os.environ.get("TMP"),
        ):
            if cand and os.path.isdir(cand):
                candidate = cand
                break
        if not candidate:
            candidate = os.path.join(str(Path.home()), ".nazzelha_tmp")
    try:
        os.makedirs(candidate, exist_ok=True)
        os.environ["TMPDIR"] = candidate
        os.environ["TEMP"] = candidate
        os.environ["TMP"] = candidate
        tempfile.tempdir = candidate  # overrides any cached gettempdir() default
        probe = os.path.join(candidate, f".probe_{os.getpid()}.bin")
        with open(probe, "wb") as fh:
            fh.write(b"probe")
        with open(probe, "rb") as fh:
            data = fh.read()
        if data != b"probe":
            raise IOError("temp dir write/read mismatch")
        os.remove(probe)
        _TEMP_DIR = candidate
        _diag_log(f"temp_dir={candidate} writable=True")
        return {"path": candidate, "writable": True, "error": ""}
    except Exception as exc:
        msg = f"{type(exc).__name__}: {exc}"
        _diag_log(f"temp_dir writable=False: {msg}")
        return {"path": candidate or "", "writable": False, "error": msg}


_LAST_TIKTOK_PROBE: Dict[str, Any] = {}


def _probe_tikTok_page(url: str, headers: Optional[Dict[str, str]] = None) -> Dict[str, Any]:
    """Safe, credential-free HTTP probe of what TikTok actually returns.

    Returns ONLY safe diagnostic fields (status, final url, content-type,
    content-length, presence of the universal-data script, anti-bot markers).
    NEVER logs cookies, tokens, authorization headers or bodies.
    """
    out: Dict[str, Any] = {
        "status": None, "final_url": "", "content_type": "",
        "content_length": None, "is_html": False,
        "has_universal_data": False, "has_login_redirect": False,
        "has_challenge": False, "error": "",
    }
    hdrs = {"User-Agent": _TIKTOK_WEBPAGE_UA, "Accept": "*/*"}
    if headers:
        hdrs.update(headers)
    try:
        req = urllib.request.Request(url, headers=hdrs)
        with urllib.request.urlopen(req, timeout=25) as resp:
            out["status"] = resp.getcode()
            out["final_url"] = resp.geturl()
            ct = resp.headers.get("Content-Type", "")
            out["content_type"] = ct[:80]
            cl = resp.headers.get("Content-Length")
            if cl:
                out["content_length"] = int(cl)
            out["is_html"] = "text/html" in ct
            body = resp.read(512 * 1024)  # cap: never log full bodies
    except urllib.error.HTTPError as e:
        out["status"] = e.code
        out["final_url"] = url
        out["is_html"] = True
        try:
            body = e.read(512 * 1024)
        except Exception:
            body = b""
    except Exception as exc:
        out["error"] = f"{type(exc).__name__}: {exc}"
        return out
    try:
        text = body.decode("utf-8", "replace")
    except Exception:
        text = ""
    out["has_universal_data"] = "__UNIVERSAL_DATA_FOR_REHYDRATION__" in text
    out["has_login_redirect"] = (
        urllib.parse.urlparse(out.get("final_url") or "").path == "/login"
    )
    out["has_challenge"] = any(m in text for m in (
        "Please wait", "captcha", "verification", "cf-captcha",
        "Just a moment", "checking your browser",
    ))
    return out


def initialize(native_lib_dir: str = "", ffmpeg_bin_dir: str = "",
               ffmpeg_lib_dir: str = "", abi: str = "unknown",
               temp_dir: str = "") -> str:
    """
    Initialize the Android Python backend and return a JSON status string.

    Args are provided by MainActivity.prepareFFmpegRuntime():
      native_lib_dir: applicationInfo.nativeLibraryDir (holds libffmpeg.so)
      ffmpeg_bin_dir: private dir holding "ffmpeg"/"ffprobe" entry points
      ffmpeg_lib_dir: private dir holding extracted libav*.so shared libraries
      abi: primary Android ABI of the device
    temp_dir is MainActivity's writable app-private cache dir used for
    Python/yt-dlp temporary files (never /tmp on Android).
    """
    global _FFMPEG_BIN_DIR, _FFMPEG_LIB_DIR, _ANDROID_ABI
    _ensure_app_temp()
    try:
        if not yt_dlp:
            return json.dumps({
                "ready": False,
                "error": "yt-dlp is not installed. Please check the Chaquopy pip configuration."
            })

        # Verify yt-dlp is functional
        try:
            ytdlp_version = getattr(yt_dlp.version, "__version__", "unknown")
        except Exception:
            ytdlp_version = "unknown"

        _FFMPEG_BIN_DIR = ffmpeg_bin_dir if ffmpeg_bin_dir else None
        _FFMPEG_LIB_DIR = ffmpeg_lib_dir if ffmpeg_lib_dir else None
        _ANDROID_ABI = abi or "unknown"

        # Establish a writable temp dir FIRST so yt-dlp and Python tempfile
        # never try to write to read-only /tmp on Android.
        _temp_result = _setup_writable_temp(temp_dir)

        _configure_ffmpeg_environment()

        # Diagnostics for the Android logcat (never surfaced in the UI).
        expected_ffmpeg = os.path.join(ffmpeg_bin_dir, "ffmpeg") if ffmpeg_bin_dir else ""
        ffmpeg_check = _verify_ffmpeg(expected_ffmpeg) if expected_ffmpeg else {
            "exists": False, "executable": False, "run_ok": False,
            "version_line": "", "error": "no ffmpeg bin dir provided"
        }
        diagnostics = {
            "python_version": platform.python_version(),
            "yt_dlp_version": ytdlp_version,
            "android_abi": _ANDROID_ABI,
            "temp_dir": _temp_result["path"],
            "temp_writable": _temp_result["writable"],
            "temp_error": _temp_result["error"],
            "ffmpeg_expected_path": expected_ffmpeg,
            "ffmpeg_exists": ffmpeg_check["exists"],
            "ffmpeg_executable": ffmpeg_check["executable"],
            "ffmpeg_run_ok": ffmpeg_check["run_ok"],
            "ffmpeg_version": ffmpeg_check["version_line"],
            "ffmpeg_error": ffmpeg_check["error"],
        }

        return json.dumps({
            "ready": True,
            "version": ytdlp_version,
            "message": f"yt-dlp version: {ytdlp_version}",
            "diagnostics": diagnostics,
        })
    except Exception as e:
        return json.dumps({
            "ready": False,
            "error": f"Initialization error: {type(e).__name__}: {e}"
        })


# --------------------------------------------------------------------------- #
# Error classification
#
# Extraction failures and media-download failures are fundamentally different:
#   - EXTRACTION_FAILED:      yt-dlp could not understand the page / extract info
#   - AUTHENTICATION_REQUIRED: content genuinely requires login (private post,
#                              members-only, age-gated, etc.)
#   - FORMAT_UNAVAILABLE:     extraction worked but the requested quality does
#                             not exist for this video
#   - NETWORK_ERROR:          DNS/timeout/connection problems
#   - MEDIA_DOWNLOAD_FAILED:  extraction succeeded but fetching the media bytes
#                             failed (e.g. expired/signed URL rejected with 403)
#
# SECURITY NOTE: never include cookies, authorization headers, session tokens
# or passwords in these messages or in logcat output. Only short technical
# summaries of the public yt-dlp error text are propagated.
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
    # The signature yt-dlp emits when the extracted media URL itself is
    # rejected during the actual data transfer phase (e.g. HTTP 403).
    'unable to download video data',
    'unable to download webpage',  # kept last-resort; classified below by phase
    'http error 403', 'http error 410', 'http error 404',
)

_EXTRACTION_KEYWORDS = (
    'unable to extract', 'cannot parse data', 'failed to parse',
    'no video found', 'unsupported url', 'not a valid url', 'invalid url',
    'does not pass filter', 'video unavailable', 'this video is unavailable',
    'not found', 'empty media response', 'sent an empty',
)


def classify_error(error_msg: str, phase: str = "extraction") -> str:
    """Map raw yt-dlp error text to a stable machine-readable code.

    phase: "extraction" or "download" - the same HTTP status can mean different
    things depending on when it happened (a 403 while fetching the watch page
    is bot-blocking; a 403 while streaming the media bytes is a rejected/
    expired signed URL).
    """
    m = (error_msg or "").lower()

    if any(k in m for k in _FORMAT_KEYWORDS):
        return "FORMAT_UNAVAILABLE"

    if any(k in m for k in _AUTH_KEYWORDS):
        return "AUTHENTICATION_REQUIRED"

    if any(k in m for k in _MEDIA_DOWNLOAD_KEYWORDS) or "http error 403" in m:
        if "unable to download webpage" in m and phase == "extraction":
            # Fetching the page itself failed -> treat as extraction problem
            # unless a genuine network keyword says otherwise.
            if any(k in m for k in _NETWORK_KEYWORDS):
                return "NETWORK_ERROR"
            return "EXTRACTION_FAILED"
        return "MEDIA_DOWNLOAD_FAILED"

    if any(k in m for k in _NETWORK_KEYWORDS):
        return "NETWORK_ERROR"

    # TikTok bot-check / "rehydration" challenge: the page returned is an
    # anti-bot interstitial (HTTP 200, text/html, no universal rehydration
    # data) instead of the real video page. This is NOT a generic
    # EXTRACTION_FAILED - it is a distinct, retryable state that the Kotlin
    # TikTokExtractor surfaces as TIKTOK_CHALLENGE with probe diagnostics.
    # NOTE: must be checked BEFORE _EXTRACTION_KEYWORDS because the yt-dlp
    # message "Unable to extract universal data for rehydration" also contains
    # the generic "unable to extract" substring.
    if any(k in m for k in (
            'universal data for rehydration',
            'unable to extract universal data',
            'unexpected response from webpage request')):
        return "TIKTOK_CHALLENGE"

    if any(k in m for k in _EXTRACTION_KEYWORDS):
        return "EXTRACTION_FAILED"

    # Bare "403"/"forbidden"/"401" style statuses WITHOUT any login/private
    # wording are NOT authentication problems - they indicate the platform
    # refused the request (bot protection, geo-block, rejected client).
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
    "TIKTOK_CHALLENGE": (
        "TikTok served an anti-bot verification page instead of the video. "
        "This is temporary - please wait a moment and try again."
    ),
}


# --------------------------------------------------------------------------- #
# Structured diagnostics (development tracing).
#
# The goal is to NEVER hide the real yt-dlp/Python failure behind a generic
# message: every failure response carries the exception type/message plus the
# tail of the captured verbose yt-dlp log, and everything is mirrored to
# stderr (Chaquopy forwards python.stderr to logcat) with the [NazzelhaPy]
# prefix. Secrets are redacted before anything is logged or returned.
# --------------------------------------------------------------------------- #

_SECRET_MARKERS = ("cookie", "authorization", "password", "po_token",
                   "potoken", "session", "token=")


def _diag_log(message: str) -> None:
    """Mirror diagnostics to logcat (python.stderr) without blocking."""
    try:
        print(f"[NazzelhaPy] {message}", file=sys.stderr, flush=True)
    except Exception:
        pass


def _sanitize(text: str) -> str:
    low = text.lower()
    if any(marker in low for marker in _SECRET_MARKERS):
        return "[line redacted: may contain credentials]"
    return text


def runtime_diagnostics() -> Dict[str, Any]:
    """Report exactly which runtime is executing (versions + module paths)."""
    deps = {}
    for dep in ("requests", "urllib3", "brotli", "brotlicffi", "certifi",
                "websockets", "Cryptodome", "mutagen", "curl_cffi",
                "yt_dlp_ejs"):
        try:
            import importlib.util
            deps[dep] = importlib.util.find_spec(dep) is not None
        except Exception:
            deps[dep] = False
    return {
        "python_version": platform.python_version(),
        "python_implementation": platform.python_implementation(),
        "executable": sys.executable,
        "android_abi": _ANDROID_ABI,
        "yt_dlp_version": getattr(yt_dlp.version, "__version__", "unknown"),
        "yt_dlp_module_path": getattr(yt_dlp, "__file__", ""),
        "optional_dependencies": deps,
    }


# --------------------------------------------------------------------------- #
# Phase 1 / 2 / 3 / 5 / 6 - Android runtime diagnostic.
#
# Invoked from the Kotlin `runtime_diag` MethodChannel handler. Prints the full
# human-readable diagnostic block to STDERR (Chaquopy forwards python.stderr to
# logcat as [NazzelhaPy]) so it NEVER pollutes the stdout JSON protocol, and
# returns a structured JSON string for the caller.
# --------------------------------------------------------------------------- #

def _impersonation_targets() -> Dict[str, Any]:
    """Probe whether yt-dlp has any usable TLS impersonation provider."""
    curl_cffi_present = False
    curl_cffi_version = ""
    curl_cffi_location = ""
    try:
        import curl_cffi  # noqa: F401
        curl_cffi_present = True
        curl_cffi_version = getattr(curl_cffi, "__version__", "") or ""
        curl_cffi_location = getattr(curl_cffi, "__file__", "") or ""
    except Exception as exc:
        curl_cffi_present = False
        curl_cffi_version = f"import failed: {type(exc).__name__}"

    targets: List[str] = []
    targets_note = ""
    if yt_dlp and curl_cffi_present:
        try:
            with yt_dlp.YoutubeDL({"quiet": True}) as ydl:
                raw = list(ydl._get_available_impersonate_targets() or [])
            # ImpersonateTarget objects are not JSON serializable; stringify.
            targets = [str(t) if not isinstance(t, str) else t for t in raw]
        except Exception as exc:
            targets_note = f"_get_available_impersonate_targets failed: {type(exc).__name__}: {exc}"
    elif yt_dlp:
        targets_note = "no curl_cffi import on Android -> impersonate targets empty"

    return {
        "curl_cffi_present": curl_cffi_present,
        "curl_cffi_version": curl_cffi_version,
        "curl_cffi_location": curl_cffi_location,
        "impersonation_available": len(targets) > 0,
        "available_targets": targets,
        "note": targets_note,
    }


def _find_module_path(name: str) -> str:
    try:
        import importlib.util
        spec = importlib.util.find_spec(name)
        return getattr(spec, "origin", "") or ""
    except Exception:
        return ""


def android_runtime_diagnostics() -> str:
    """Full Android runtime diagnostic block (mirrors to stderr).

    Answers the Phase 1 questions directly:
    - which yt-dlp is actually loaded and from where;
    - whether curl_cffi is importable on this Android ABI and whether its
      native components are compatible with the device ABI;
    - whether impersonation targets are available;
    - requests / certifi / FFmpeg presence.

    All diagnostics go to STDERR; stdout carries the JSON protocol only.
    """
    import shutil

    ytdlp_version = getattr(yt_dlp.version, "__version__", "unknown") if yt_dlp else "not installed"
    ytdlp_path = getattr(yt_dlp, "__file__", "") if yt_dlp else ""
    ffmpeg_path = shutil.which("ffmpeg") or ""

    requests_present = _find_module_path("requests")
    certifi_present = _find_module_path("certifi")

    imp = _impersonation_targets()

    block_lines = [
        "=== ANDROID PYTHON RUNTIME ===",
        "",
        f"Python version: {platform.python_version()}",
        f"Python executable: {sys.executable}",
        f"Python platform: {platform.platform()}",
        f"Machine: {platform.machine()}",
        f"Architecture: {platform.architecture()}",
        "",
        f"yt-dlp installed: {yt_dlp is not None}",
        f"yt-dlp version: {ytdlp_version}",
        f"yt-dlp location: {ytdlp_path}",
        "",
        f"curl_cffi installed: {imp['curl_cffi_present']}",
        f"curl_cffi version: {imp['curl_cffi_version']}",
        f"curl_cffi location: {imp['curl_cffi_location']}",
        "",
        "impersonation support:",
        f"available impersonation targets: {imp['available_targets'] or 'NONE'}",
        f"  (note: {imp['note']})",
        "",
        f"requests installed: {bool(requests_present)} ({requests_present or 'not found'})",
        f"certifi installed: {bool(certifi_present)} ({certifi_present or 'not found'})",
        "",
        f"FFmpeg available: {bool(ffmpeg_path)}",
        f"FFmpeg path: {ffmpeg_path or 'not found'}",
        "",
        f"Android ABI: {_ANDROID_ABI}",
        f"Android ABI (runtime): {platform.machine()}",
        "================================",
        "",
    ]
    for line in block_lines:
        print(line, file=sys.stderr, flush=True)
    _diag_log("Android runtime diagnostics emitted")

    report: Dict[str, Any] = {
        "success": True,
        "python_version": platform.python_version(),
        "python_executable": sys.executable,
        "android_abi": _ANDROID_ABI,
        "yt_dlp": {
            "installed": yt_dlp is not None,
            "version": ytdlp_version,
            "location": ytdlp_path,
        },
        "curl_cffi": {
            "installed": imp["curl_cffi_present"],
            "version": imp["curl_cffi_version"],
            "location": imp["curl_cffi_location"],
        },
        "impersonation": {
            "available": imp["impersonation_available"],
            "available_targets": imp["available_targets"],
            "note": imp["note"],
        },
        "requests": _find_module_path("requests"),
        "certifi": _find_module_path("certifi"),
        "ffmpeg_path": ffmpeg_path,
    }
    return json.dumps(report)


class _CaptureLogger:
    """yt-dlp logger that keeps a bounded ring buffer of verbose output.

    quiet=True suppresses console noise but the logger still receives every
    debug/warning/error line, which lets us see WHICH extractor/player client/
    challenge path yt-dlp attempted when a Submit fails.
    """

    def __init__(self, capacity: int = 120):
        self._lines: List[str] = []
        self._capacity = capacity

    def debug(self, msg):
        try:
            self._lines.append(_sanitize(str(msg))[:240])
            if len(self._lines) > self._capacity:
                self._lines.pop(0)
        except Exception:
            pass

    def warning(self, msg):
        self.debug("WARNING: " + str(msg))

    def error(self, msg):
        self.debug("ERROR: " + str(msg))

    def tail(self) -> List[str]:
        return list(self._lines)


def _failure_payload(exc: BaseException, code: str, phase: str,
                     logger: Optional[_CaptureLogger],
                     extra: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """Build a failure response that keeps the REAL error visible.

    The user-facing 'error' stays clean; 'technical' carries the exception
    type/message; 'diagnostics' carries the sanitized verbose tail and the
    runtime report. Everything is also written to stderr/logcat.
    """
    tb = traceback.format_exc()
    technical = f"{type(exc).__name__}: {exc}"
    diag: Dict[str, Any] = {
        "stage": phase,
        "exception_type": type(exc).__name__,
        "exception_message": str(exc)[:500],
        "runtime": runtime_diagnostics(),
    }
    if logger is not None:
        diag["verbose_tail"] = logger.tail()
    payload: Dict[str, Any] = {
        "success": False,
        "error_code": code,
        "error": _USER_MESSAGES[code],
        "technical": technical[:400],
        "diagnostics": diag,
    }
    if extra:
        payload.update(extra)

    # Full trace to logcat for development tracing (secrets already excluded -
    # tracebacks of yt-dlp DownloadErrors contain only public error text).
    _diag_log(f"FAILURE[{phase}] code={code}")
    _diag_log(f"FAILURE[{phase}] technical={technical}")
    for line in tb.strip().splitlines()[-12:]:
        _diag_log(f"FAILURE[{phase}] tb: {_sanitize(line)[:200]}")
    if logger is not None:
        for line in logger.tail():
            _diag_log(f"FAILURE[{phase}] ytdlp: {line}")
    return payload


# --------------------------------------------------------------------------- #
# TikTok-specific extraction (Android).
#
# TikTok's extractor intermittently gets served an anti-bot / "rehydration"
# challenge page that lacks the __UNIVERSAL_DATA_FOR_REHYDRATION__ script the
# extractor needs, producing:
#   [TikTok] <id>: Unable to extract universal data for rehydration
# That hit is PROBABILISTIC and depends on source IP / device / timing, so a
# single generic yt-dlp call fails the whole Submit on the first challenge hit.
# Windows handles that with a bounded cascade of DISTINCT request contexts
# (yt-dlp there has curl_cffi impersonation, which changes the HTTP response).
# On Android the challenge is deterministic (no impersonation possible), so a
# native Kotlin extractor is the primary path and this Python cascade is a
# bounded last-resort fallback. It is applied ONLY to TikTok URLs;
# YouTube/Facebook/Instagram use their existing paths untouched. No browser
# cookies (Android has none) and impersonation is a graceful no-op when the
# optional dep is absent.
# --------------------------------------------------------------------------- #

_TIKTOK_HOSTS = ("tiktok.com", "vt.tiktok.com", "vm.tiktok.com")
_TIKTOK_WEBPAGE_UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
)
_TIKTOK_MIN_REQUEST_GAP_SECONDS = 6.0

_tiktok_last_finish_monotonic = 0.0
_tiktok_consecutive_failures = 0


def _log_tiktok(message: str) -> None:
    _diag_log(f"TikTok: {message}")


def _is_tiktok(platform: str, url: str = "") -> bool:
    plat = (platform or "").lower()
    if plat in ("tiktok", "vt.tiktok.com", "vm.tiktok.com"):
        return True
    low = (url or "").lower()
    return any(host in low for host in _TIKTOK_HOSTS)


def _resolve_tiktok_url(url: str) -> str:
    """Resolve vt.tiktok.com / vm.tiktok.com short links to the canonical
    www.tiktok.com URL, preserving query params. Returns the original URL on
    any failure so extraction can still proceed."""
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
        resp = urllib.request.build_opener(urllib.request.HTTPRedirectHandler()).open(
            req, timeout=25)
        final = resp.geturl() or url
        resp.close()
        return final
    except Exception:
        return url


def _extract_tiktok(
    url: str,
    download: bool,
    quality: int,
    output_dir: Optional[Path],
    progress_sink: Any = None,
    mode: str = "video",
) -> Dict[str, Any]:
    """TikTok extraction/download with a bounded fallback cascade.

    mode="audio" selects the best audio stream and converts it to a real MP3
    with FFmpeg; the video cascade logic is unchanged otherwise.

    Returns:
      success  - bool
      info     - metadata dict (extraction) / None
      filepath - final file path (download) / None
      logger   - _CaptureLogger with verbose yt-dlp tail for diagnostics
      error    - clean user-facing message when success is False
      error_code - classify_error code when success is False
    """
    global _tiktok_last_finish_monotonic, _tiktok_consecutive_failures

    resolved = _resolve_tiktok_url(url)
    _log_tiktok(f"URL={url}")
    if resolved and resolved != url:
        _log_tiktok(f"Resolved short URL -> {resolved}")
        _ensure_app_temp()
        prob = _probe_tikTok_page(resolved)
        _LAST_TIKTOK_PROBE.clear()
        _LAST_TIKTOK_PROBE.update(prob)
        _log_tiktok(f"probe: status={prob.get('status')} ct={prob.get('content_type')} len={prob.get('content_length')}")
        _log_tiktok(f"probe: universal_data={prob.get('has_universal_data')} login={prob.get('has_login_redirect')} challenge={prob.get('has_challenge')} err={prob.get('error')}")

    # Adaptive inter-request pacing (mirrors Windows): never let rapid-fire
    # Submits hammer TikTok; after a failure the gap escalates.
    if _tiktok_last_finish_monotonic > 0:
        since = time.monotonic() - _tiktok_last_finish_monotonic
        required = (_TIKTOK_MIN_REQUEST_GAP_SECONDS
                    if _tiktok_consecutive_failures == 0
                    else min(6.0 + 2.0 * _tiktok_consecutive_failures, 10.0))
        if since < required:
            time.sleep(required - since)

    log = _CaptureLogger(capacity=150)
    out_dir = output_dir or Path(os.getcwd())

    def base_opts() -> dict:
        opts = {
            "format": (
                f"bestvideo[height<={quality}]"
                f"+bestaudio/best[height<={quality}]/best"
            ),
            "merge_output_format": "mp4",
            "outtmpl": str(out_dir / "%(title)s.%(ext)s"),
            "noplaylist": True,
            "quiet": True,
            "no_warnings": False,
            "noprogress": True,
            "referer": "https://www.tiktok.com/",
            # Sanitize filenames for Android shared storage (matches the other
            # working Android platforms).
            "windowsfilenames": True,
            "socket_timeout": 30,
            "logger": log,
        }
        if mode == "audio":
            # Audio-only: TikTok exposes progressive (muxed) MP4s, so select
            # the best one and extract a real MP3 track with FFmpeg. This uses
            # the same bundled FFmpeg runtime as video merging.
            opts["format"] = "bestaudio/best"
            opts.pop("merge_output_format", None)
            opts["postprocessors"] = [{
                "key": "FFmpegExtractAudio",
                "preferredcodec": "mp3",
                "preferredquality": "192",
            }]
        return opts

    # Attempt C (Android): TikTok's modern API path. The webpage extractor
    # always calls `_download_webpage_handle(..., impersonate=True)`; on
    # Android curl_cffi (yt-dlp's impersonation provider) is absent, so
    # impersonate is a no-op and the page request lands on TikTok's anti-bot
    # challenge. The mobile API endpoint (api16-normal-*.tiktokv.com) does NOT
    # require impersonation and is selected automatically when `app_info` +
    # `device_id` are supplied (see TikTokBaseIE._real_extract). NOTE:
    # app_info must be `<iid>/<app_name>/<app_version>/<manifest_version>/<aid>`
    # (iid FIRST) else yt-dlp mis-parses it.
    import random as _random
    app_api = base_opts()
    _tt_device_id = str(_random.randint(7250000000000000000, 7325099899999994577))
    _tt_iid = str(_random.randint(7250000000000000000, 7325099898989999999))
    app_api["extractor_args"] = {
        # CRITICAL: the outer key MUST be lowercase "tiktok". yt-dlp looks it
        # up as ie_key.lower() via traverse_obj, which is case-SENSITIVE for
        # dict keys - "TikTok" silently yields None and the extractor then
        # behaves exactly like the standard webpage attempt (proven by test).
        "tiktok": {
            "device_id": [_tt_device_id],
            "app_info": [_tt_iid + "/musical_ly/35.1.3/2023501030/0"],
            "api_hostname": ["api16-normal-c-useast1a.tiktokv.com"],
        }
    }
    attempts = [("standard", base_opts())]
    # NOTE (Phase 17): the "browser_ua" attempt was removed. Swapping the
    # User-Agent alone was proven to never change the HTTP response (the
    # challenge is TLS-fingerprint based), so it was pure request spam.
    attempts.append(("app_api", app_api))

    hook_state: Dict[str, Any] = {"last_percent": -1, "last_time": 0.0}
    return _run_tiktok_cascade(resolved, download, attempts, hook_state, log,
                               progress_sink, quality, output_dir)


def _run_tiktok_cascade(resolved, download, attempts, hook_state, log,
                        progress_sink, quality, output_dir) -> Dict[str, Any]:
    """Execute the TikTok attempt cascade (bounded, no cool-off rescue)."""
    global _tiktok_last_finish_monotonic, _tiktok_consecutive_failures

    last_error: Optional[str] = None
    deadline = None if download else time.monotonic() + 55

    for attempt_no, (name, opts) in enumerate(attempts, start=1):
        if deadline is not None and attempt_no > 1 and time.monotonic() >= deadline:
            _log_tiktok("Extraction time budget exhausted; stopping fallbacks")
            break
        if download and progress_sink is not None:
            opts["progress_hooks"] = [_make_progress_hook(progress_sink, hook_state)]
        _log_tiktok(f"Attempting {name} extraction")
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                info = ydl.extract_info(resolved, download=download)
                if download:
                    filepath = _resolve_final_filepath(ydl, info)
                    if mode == "audio":
                        # FFmpegExtractAudio writes "<title>.mp3"; the
                        # requested_downloads record may still point at the
                        # pre-conversion source, so normalize to .mp3.
                        alt = Path(filepath).with_suffix(".mp3")
                        if alt.exists():
                            filepath = str(alt)
            if download:
                fp = Path(filepath)
                if not fp.exists() or fp.stat().st_size <= 0:
                    raise RuntimeError("Downloaded file is missing or empty")
            _tiktok_last_finish_monotonic = time.monotonic()
            _tiktok_consecutive_failures = 0
            _log_tiktok(f"Successful via {name}")
            return {"success": True, "info": info, "filepath": filepath,
                    "logger": log}
        except Exception as e:
            last_error = f"{type(e).__name__}: {e}"
            _log_tiktok(f"{name} failed: {last_error[:200]}")
        pause = min(1.0 * attempt_no, 4.0)
        if deadline is not None:
            pause = min(pause, max(0.0, deadline - time.monotonic()))
        if pause > 0:
            time.sleep(pause)

    # NOTE (Phase 17): the old "cool-off rescue" (25-30s sleep + one more
    # identical request) was REMOVED. It never changed the HTTP response - the
    # challenge is served deterministically without TLS impersonation, which
    # Android cannot provide. The native Kotlin TikTok adapter (OkHttp over the
    # device TLS stack) is the primary path; this Python cascade is a bounded
    # last-resort fallback only and must NOT hammer TikTok.

    _tiktok_last_finish_monotonic = time.monotonic()
    _tiktok_consecutive_failures += 1
    _log_tiktok(f"All attempts failed; last error: {last_error}")

    code = classify_error(last_error or "", phase="download" if download
                          else "extraction")
    _log_tiktok(f"Classified as {code}")
    return {"success": False, "info": None, "filepath": None, "logger": log,
            "error": _USER_MESSAGES[code], "error_code": code,
            "technical": last_error or ""}


def _tiktok_failure_json(res: Dict[str, Any], phase: str) -> str:
    """Build a failure JSON response from a TikTok cascade result dict."""
    logger = res.get("logger")
    payload = {
        "success": False,
        "error_code": res.get("error_code", "EXTRACTION_FAILED"),
        "error": res.get("error", _USER_MESSAGES["EXTRACTION_FAILED"]),
        "technical": res.get("technical", ""),
        "diagnostics": {
            "stage": phase,
            "verbose_tail": logger.tail() if logger else [],
            "tiktok_probe": dict(_LAST_TIKTOK_PROBE),
        },
    }
    return json.dumps(payload)


def get_qualities(url: str, platform: str = "youtube") -> str:
    """
    Extract available video qualities from a URL.

    Args:
        url: Video URL
        platform: Platform identifier

    Returns:
        JSON-encoded string with success status and available qualities
    """
    _ensure_app_temp()
    if not yt_dlp:
        return json.dumps({
            "success": False,
            "error": "yt-dlp is not installed. Please check the Chaquopy pip configuration."
        })

    # TikTok uses its own extraction cascade to get past the intermittent
    # anti-bot "rehydration" page. All other platforms keep the standard path.
    if _is_tiktok(platform, url):
        res = _extract_tiktok(url, download=False, quality=1080, output_dir=None)
        if not res["success"]:
            return _tiktok_failure_json(res, "extraction")
        info = res["info"]
        available_heights = {int(f["height"]) for f in info.get("formats", [])
                             if f.get("height") and f["height"] > 0}
        qualities = sorted(available_heights)
        if not qualities:
            return json.dumps({
                "success": False,
                "error_code": "EXTRACTION_FAILED",
                "error": "No downloadable video qualities found for this TikTok video.",
            })
        return json.dumps({
            "success": True,
            "qualities": qualities,
            "title": info.get("title", "Video"),
        })

    logger = _CaptureLogger()
    try:
        with yt_dlp.YoutubeDL({
            "quiet": True,
            "no_warnings": False,
            "socket_timeout": 30,
            "logger": logger,
        }) as ydl:
            info = ydl.extract_info(url, download=False)

            available_heights = set()

            for fmt in info.get("formats", []):
                height = fmt.get("height")
                if height and height > 0:
                    available_heights.add(int(height))

            qualities = sorted(available_heights)

            if not qualities:
                return json.dumps({
                    "success": False,
                    "error_code": "FORMAT_UNAVAILABLE",
                    "error": "No downloadable video qualities found for this URL.",
                    "diagnostics": {
                        "extractor": info.get("extractor", ""),
                        "format_count": len(info.get("formats", [])),
                    },
                })

            return json.dumps({
                "success": True,
                "qualities": qualities,
                "title": info.get("title", "Video")
            })

    except yt_dlp.utils.DownloadError as e:
        code = classify_error(str(e), phase="extraction")
        return json.dumps(_failure_payload(e, code, "extraction", logger))
    except Exception as e:
        code = classify_error(str(e), phase="extraction")
        return json.dumps(_failure_payload(e, code, "extraction", logger))


def diagnose(url: str, platform_name: str = "youtube") -> str:
    """Internal extraction diagnostic (development tracing).

    Returns runtime identity, extractor selection and the exact failure
    reason for a URL without changing any UI flow. Callable via the
    'nazzelha/python' MethodChannel method 'diagnose'.
    """
    logger = _CaptureLogger(capacity=200)
    result: Dict[str, Any] = {"platform": platform_name, "url_provided": bool(url)}
    result["runtime"] = runtime_diagnostics()
    if not yt_dlp:
        result.update({"success": False, "stage": "import",
                       "error": "yt-dlp is not installed"})
        return json.dumps(result)
    try:
        with yt_dlp.YoutubeDL({
            "quiet": True,
            "no_warnings": False,
            "socket_timeout": 30,
            "logger": logger,
        }) as ydl:
            # Which extractor would claim this URL?
            match = ydl._match_entry(url, False) if hasattr(ydl, "_match_entry") else None
            ie_candidates = [ie.ie_key() for ie in ydl._ies.values()
                             if ie.suitable(url)] if hasattr(ydl, "_ies") else []
            result["matching_extractors"] = ie_candidates[:5]
            result["match_note"] = str(match) if match else ""
            info = ydl.extract_info(url, download=False)
            heights = sorted({f.get("height") for f in info.get("formats", [])
                              if f.get("height")})
            result.update({
                "success": True,
                "stage": "extraction",
                "extractor": info.get("extractor", ""),
                "title": info.get("title", ""),
                "format_count": len(info.get("formats", [])),
                "heights": heights,
                "verbose_tail": logger.tail(),
            })
    except Exception as e:
        tb = traceback.format_exc()
        code = classify_error(str(e), phase="extraction")
        result.update({
            "success": False,
            "stage": "extraction",
            "error_code": code,
            "exception_type": type(e).__name__,
            "exception_message": str(e)[:500],
            "traceback_tail": [_sanitize(l)[:200]
                               for l in tb.strip().splitlines()[-12:]],
            "verbose_tail": logger.tail(),
        })
    return json.dumps(result)


def _make_progress_hook(sink: Any, state: Dict[str, Any]):
    """Build a yt-dlp progress hook that streams REAL download progress.

    The hook receives yt-dlp's own progress dictionaries and forwards them as
    JSON through the Java-side sink (which pushes them to Flutter over the
    platform channel). Events are throttled so the UI thread is not flooded.
    """
    def hook(d: Dict[str, Any]) -> None:
        if sink is None:
            return
        try:
            status = d.get("status")

            if status == "downloading":
                total = d.get("total_bytes") or d.get("total_bytes_estimate") or 0
                downloaded = d.get("downloaded_bytes") or 0
                percent = round((downloaded * 100.0 / total), 1) if total else 0.0

                # Throttle: emit when the integer percentage changes, or at
                # most every 400 ms for slow-moving downloads.
                now = time.time()
                int_percent = int(percent)
                if int_percent == state.get("last_percent") and \
                        (now - state.get("last_time", 0)) < 0.4:
                    return
                state["last_percent"] = int_percent
                state["last_time"] = now

                speed = d.get("_speed_str") or "N/A"
                eta = d.get("_eta_str") or "N/A"
                filename = os.path.basename(d.get("info_dict", {}).get("_filename")
                                            or d.get("filename") or "")
                payload = {
                    "event": "progress",
                    "status": "downloading",
                    "percent": percent,
                    "downloaded_bytes": downloaded,
                    "total_bytes": total,
                    "speed": str(speed).strip(),
                    "eta": str(eta).strip(),
                    "filename": filename,
                }
            elif status == "finished":
                filename = os.path.basename(d.get("info_dict", {}).get("_filename")
                                            or d.get("filename") or "")
                payload = {
                    "event": "progress",
                    "status": "finished",
                    "percent": 100,
                    "downloaded_bytes": d.get("total_bytes") or 0,
                    "total_bytes": d.get("total_bytes") or 0,
                    "speed": "N/A",
                    "eta": "00:00",
                    "filename": filename,
                }
            else:
                return

            sink.send(json.dumps(payload))
        except Exception:
            # Never let a progress-reporting failure abort the download.
            pass
    return hook


def _resolve_final_filepath(ydl, info: Dict[str, Any]) -> str:
    """Resolve the FINAL on-disk file path after a completed download.

    ydl.prepare_filename() returns the pre-merge template name (e.g. .webm)
    which is wrong once FFmpeg has merged streams into the target container.
    yt-dlp records the actual final location in requested_downloads[].filepath.
    """
    # Preferred: yt-dlp's own record of the produced file(s).
    for rd in info.get("requested_downloads") or []:
        candidate = rd.get("filepath") or rd.get("_filename")
        if candidate and os.path.exists(candidate):
            return candidate

    # Fallback: template name, trying both the original and merged extensions.
    base = ydl.prepare_filename(info)
    if os.path.exists(base):
        return base

    root, _ext = os.path.splitext(base)
    for ext in ("mp4", "mkv", "webm", "m4a"):
        candidate = f"{root}.{ext}"
        if os.path.exists(candidate):
            return candidate

    return base


def download_video(url: str, platform: str, quality: int, output_path: str,
                   progress_sink: Any = None, mode: str = "video") -> str:
    """
    Download a video at specified quality, or audio-only when mode='audio'.

    Args:
        url: Video URL
        platform: Platform identifier
        quality: Desired quality (height in pixels; ignored in audio mode)
        output_path: Directory to save the video (staging directory; the
                     Kotlin layer persists the finished file to the public
                     Downloads/Nazzelha location afterwards)
        progress_sink: Optional Java object with a send(json: str) method that
                       receives REAL yt-dlp progress events as JSON strings
        mode: "video" (default, current behavior) or "audio".

    Returns:
        JSON-encoded string with success status and file path or error message
    """
    _ensure_app_temp()
    if not yt_dlp:
        return json.dumps({
            "success": False,
            "error": "yt-dlp is not installed. Please check the Chaquopy pip configuration."
        })

    # TikTok downloads use their own cascade (see _extract_tiktok) so an
    # intermittent anti-bot page during re-extraction does not fail the
    # download. All other platforms keep the standard path below.
    if _is_tiktok(platform, url):
        output_dir = Path(output_path)
        output_dir.mkdir(parents=True, exist_ok=True)
        res = _extract_tiktok(url, download=True, quality=quality,
                              output_dir=output_dir, progress_sink=progress_sink,
                              mode=mode)
        if not res["success"]:
            return _tiktok_failure_json(res, "download")
        info = res["info"]
        filepath = res["filepath"]
        file_exists = os.path.isfile(filepath)
        file_size = os.path.getsize(filepath) if file_exists else 0
        return json.dumps({
            "success": file_exists and file_size > 0,
            "mode": mode,
            "file": filepath,
            "filename": os.path.basename(filepath),
            "title": info.get("title", "Video"),
            "size": file_size,
            "diagnostics": {
                "output_dir": str(output_dir),
                "final_path": filepath,
                "final_exists": file_exists,
                "final_size": file_size,
            },
            "error": None if file_exists and file_size > 0
                     else "Download finished but the output file is missing or empty."
        })

    try:
        # Ensure output directory exists
        output_dir = Path(output_path)
        output_dir.mkdir(parents=True, exist_ok=True)

        # Configure download options based on platform and mode
        ydl_opts = _get_yt_dlp_opts(platform, quality, output_dir, mode=mode)

        # Stream REAL progress from yt-dlp to Flutter.
        hook_state: Dict[str, Any] = {"last_percent": -1, "last_time": 0.0}
        ydl_opts["progress_hooks"] = [_make_progress_hook(progress_sink, hook_state)]

        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            info = ydl.extract_info(url, download=True)
            filepath = _resolve_final_filepath(ydl, info)
            if mode == "audio":
                # FFmpegExtractAudio writes "<title>.mp3"; ensure we report the
                # converted MP3 (the record may still point at the source).
                alt = Path(filepath).with_suffix(".mp3")
                if alt.exists():
                    filepath = str(alt)

            file_exists = os.path.isfile(filepath)
            file_size = os.path.getsize(filepath) if file_exists else 0

            return json.dumps({
                "success": file_exists and file_size > 0,
                "mode": mode,
                "file": filepath,
                "filename": os.path.basename(filepath),
                "title": info.get("title", "Video"),
                "size": file_size,
                "diagnostics": {
                    "output_dir": str(output_dir),
                    "final_path": filepath,
                    "final_exists": file_exists,
                    "final_size": file_size,
                    "merged": bool(info.get("requested_downloads")),
                },
                "error": None if file_exists and file_size > 0
                         else "Download finished but the output file is missing or empty."
            })

    except yt_dlp.utils.DownloadError as e:
        # A DownloadError during ydl.extract_info(download=True) can be EITHER
        # an extraction failure OR a media-download failure (yt-dlp raises the
        # same type for both). classify_error() inspects the message and we
        # pass phase="download" so bare HTTP statuses are attributed to the
        # media transfer, which is where they occur in this call.
        code = classify_error(str(e), phase="download")
        return json.dumps(_failure_payload(e, code, "download", None,
                                           {"error": _USER_MESSAGES[code]}))

    except Exception as e:
        error_msg = str(e)
        error_lower = error_msg.lower()

        code = classify_error(error_msg, phase="download")

        # Give actionable feedback when the merge step cannot run.
        if "ffmpeg" in error_lower and (
            "not installed" in error_lower or "not found" in error_lower
            or "aborting" in error_lower
        ):
            return json.dumps({
                "success": False,
                "error_code": "MEDIA_DOWNLOAD_FAILED",
                "error": (
                    "The video streams were downloaded but could not be merged "
                    "because the built-in media processor failed to start. "
                    "Please restart the app and try again."
                )
            })

        return json.dumps(_failure_payload(
            e, code, "download", None,
            {"error": f"Download failed: {_USER_MESSAGES[code]}"}))


def _get_yt_dlp_opts(platform: str, quality: int, output_dir: Path,
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
        # Sanitize filenames the way Windows/sdcardfs require. YouTube titles
        # frequently contain characters (":" "|" '"' etc.) that are legal on
        # desktop Linux filesystems but REJECTED by Android's shared storage
        # (sdcardfs/FUSE), which would make the final file impossible to write.
        "windowsfilenames": True,
    }

    # Point yt-dlp at the bundled FFmpeg runtime so separate video/audio
    # streams can be merged on-device. The directory contains "ffmpeg" and
    # "ffprobe" entry points prepared during initialization.
    if _FFMPEG_BIN_DIR and os.path.isdir(_FFMPEG_BIN_DIR):
        base_opts["ffmpeg_location"] = _FFMPEG_BIN_DIR

    if mode == "audio":
        # Audio-only: select the best audio stream (falling back to any media
        # whose audio can be extracted), then have FFmpeg convert it to a real
        # MP3. Uses the same bundled FFmpeg runtime as video merging above.
        base_opts["format"] = "bestaudio/best"
        base_opts.pop("merge_output_format", None)
        base_opts["postprocessors"] = [{
            "key": "FFmpegExtractAudio",
            "preferredcodec": "mp3",
            "preferredquality": "192",
        }]

    # Platform-specific configurations
    if platform in ("youtube", "youtu.be"):
        pass  # YouTube works with defaults

    elif platform in ("facebook", "fb.watch"):
        base_opts.update({
            "referer": "https://www.facebook.com/",
            "user_agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36",
        })

    elif platform in ("instagram", "instagr.am"):
        base_opts.update({
            "geo_bypass": True,
            "geo_bypass_country": "US",
            "referer": "https://www.instagram.com/",
            "user_agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36",
        })

    elif platform in ("tiktok", "vt.tiktok.com", "vm.tiktok.com"):
        base_opts.update({
            "referer": "https://www.tiktok.com/",
            "user_agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36",
        })

    else:
        base_opts.update({
            "user_agent": "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36",
        })

    return base_opts