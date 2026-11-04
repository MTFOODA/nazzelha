# Nazzelha

Nazzelha is a Flutter media downloader for video content from supported platforms. The app uses a Python backend with `yt-dlp` and `FFmpeg` to inspect sources, select quality, and download media locally.

## Features

- Download media from supported sites such as YouTube, Facebook, Instagram, and TikTok
- Independent quality selection per download card and progress updates
- Playlist history with downloaded/remaining counts, individual resume/removal, and direct folder opening
- Native Android integration via Chaquopy and bundled FFmpeg
- Windows desktop support with a local Python backend
- YouTube playlists with a chosen folder name, best-quality downloads, and Android background execution
- Arabic/English, light/dark themes, adaptive navigation, and playlist history

## Supported platforms

Verified in the current repository:

- Android: primary mobile target with native Python/FFmpeg integration
- Windows desktop: supported via the Flutter desktop shell and local Python backend
- Edge: supported with the loopback Python bridge (`python python_backend/web_bridge.py`)

Not currently described as a verified primary target in this repo:

- iOS, Linux, and macOS are not configured as supported app targets here
- The browser build requires the local Python bridge; it cannot run Python/FFmpeg inside the browser.

## Technology stack

- Flutter / Dart
- Android native integration via Chaquopy and Kotlin
- Python backend in [`python_backend/`](python_backend/)
- `yt-dlp` for media extraction
- `FFmpeg` for muxing and conversion

## Demo video

[Watch the Demo Video](ADD_VIDEO_URL_HERE)

## Prerequisites

- Flutter SDK (current project validated with Flutter 3.47.x)
- Python 3.11 for Android/Chaquopy builds
- Desktop dependencies from `python_backend/requirements.txt`; FFmpeg uses PATH or the bundled `imageio-ffmpeg` fallback
- Git and a local terminal

## Quick start

```bash
flutter pub get
```

For the desktop Python backend:

```bash
cd python_backend
python -m pip install -r requirements.txt
```

Then run the app:

```bash
flutter run -d android
# or
flutter run -d windows
```

## Build instructions

Android:

```bash
flutter build apk
# or
flutter build appbundle
```

Windows:

```bash
flutter build windows
```

If Android cannot find a Python 3.11 executable on `PATH`, set:

```bash
export CHAQUOPY_BUILD_PYTHON=/path/to/python3.11
# or on Windows PowerShell:
$env:CHAQUOPY_BUILD_PYTHON = "C:\Path\To\python.exe"
```

## Documentation

See the Python backend notes in [`python_backend/README.md`](python_backend/README.md) for backend protocol details and the download workflow.

## Limitations

- Site availability and media access remain subject to the target platform's own restrictions, bot protection, login requirements, and regional access rules.
- Source-based desktop builds use the local Python environment. Published Windows ZIPs include Python, FFmpeg and Node.
- The public web edition uses the isolated API described in [web deployment](docs/WEB_DEPLOYMENT.md). The development bridge remains local only.
- iPhone/iPad use the web edition. This release does not include a native iOS app. Linux and macOS native builds are unverified.

## Notes

Android and Windows download directly on the device. The public website prepares temporary files on the server, then lets the visitor save a video or a playlist ZIP. Download behavior depends on upstream platform restrictions and the server's free resource limits.

## Playlist history and verification

See [the implementation and verification notes](docs/DOWNLOADS_AND_DESIGN.md) for the Arabic-folder fix, per-card quality selection, per-video resume/removal, playlist history, build artifacts, and reproducible tests.

Edge development uses two terminals:

```powershell
.\.venv\Scripts\python.exe python_backend/web_bridge.py
flutter run -d edge --no-web-resources-cdn
```

Brand exports are derived from `assets/logo/nazzelha-v2.png`. Run `dart run tool/prepare_brand_assets.dart`, `dart run flutter_launcher_icons`, and `dart run flutter_native_splash:create` to regenerate them. [Brand prompt and asset notes](docs/BRAND.md).

## Web and release distribution

The header information icon opens Mohamed Fooda's developer page, GitHub and LinkedIn links, and edition downloads. Android APK and portable Windows ZIP assets are hosted on [GitHub Releases](https://github.com/MTFOODA/nazzelha/releases/latest). iPhone/iPad opens the web edition.

See [deployment and free-hosting limits](docs/WEB_DEPLOYMENT.md) and [release build instructions](docs/RELEASES.md).
