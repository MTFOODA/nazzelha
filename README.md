# Nazzelha

Nazzelha is a Flutter media downloader for video content from supported platforms. The app uses a Python backend with `yt-dlp` and `FFmpeg` to inspect sources, select quality, and download media locally.

[Official website](https://nazzelha.mohamed-fooda-mtf.workers.dev/) · [Download Android / Windows](https://github.com/MTFOODA/nazzelha/releases/latest) · [الدليل العربي](docs/USER_GUIDE_AR.md) · [Annotated walkthrough](docs/guide-ar.html)

## Features

[Unsigned iOS preview](https://github.com/MTFOODA/nazzelha/releases/tag/v1.2.0-ios-preview.1)
requires personal signing; see the [Arabic iOS installation guide](docs/IOS_PREVIEW_AR.md)
and [actual simulator verification](docs/verification-ios-preview.json).

- Download media from supported sites such as YouTube, Facebook, Instagram, and TikTok
- Independent quality selection per download card and progress updates
- Playlist history with downloaded/remaining counts, individual resume/removal, and direct folder opening
- Clear the playlist page in one action while keeping downloads and history, including after reopening
- Native Android integration via Chaquopy and bundled FFmpeg
- Packaged Android QuickJS-NG and matching EJS solver for full yt-dlp YouTube client support
- Windows desktop support with a local Python backend
- YouTube playlists with a chosen folder name, best-quality downloads, and Android background execution
- Arabic/English, light/dark themes, adaptive navigation, and playlist history

## Supported platforms

| Edition | Support |
| --- | --- |
| Android | Android 7 / API 24 and later; universal ARM, ARM64 and x86_64 APK. Clean installation and upgrade tested on Android 7 and Android 17 (4 KB and 16 KB pages), not every intermediate OS separately. |
| Windows x64 | Portable app with the local Python, FFmpeg and Node engine bundled. |
| Public web | Cloudflare website with a stateless Python API on Vercel. Tested in Edge; no local server required for visitors. |
| iPhone / iPad | Native iOS 15+ preview using the hosted engine. Unsigned Release IPA needs personal signing (for example, Sideloadly); physical-device installation remains to be verified. The web edition is also available. |
| Linux / macOS | Native builds are not configured and verified. |

Android background downloading belongs to the installed application's foreground
service. Browser preparation needs the tab to stay open and has free hosting
limits. The public hosting network can be rejected by upstream video services.

## Technology stack

- Flutter / Dart
- Android native integration via Chaquopy and Kotlin
- Python backend in [`python_backend/`](python_backend/)
- `yt-dlp` for media extraction
- `FFmpeg` for muxing and conversion

## Demo video

[Live Android demonstration](docs/media/Nazzelha-Live-Demo-Android.mp4) · [Arabic illustrated walkthrough — 3:05](docs/media/Nazzelha-Walkthrough-AR.mp4)

[Chapters and scope](docs/DEMO.md) · [Interactive button annotations](docs/guide-ar.html).
The live video records the signed app, real Facebook/YouTube downloads, Arabic
folder naming, background execution, history and individual controls at 1.75×
speed. The separate illustrated walkthrough uses labeled demonstration data.
Actual results are in [the verification summary](docs/verification-1.1.3.json).

The newer [1.2.1 verification report](docs/verification-1.2.1.json) covers the
playlist Clear page control and Android JavaScript runtime repair. The user
confirmed all six videos of the previously failing playlist on their phone.

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
python tool/prepare_release_signing.py
python tool/build_android_release.py
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

- [Arabic manual: every button, workflow and platform limit](docs/USER_GUIDE_AR.md)
- [Android installation, integrity and compatibility evidence](docs/ANDROID_INSTALLATION.md)
- [Release build and publication instructions](docs/RELEASES.md)
- [iOS preview, free signing and physical-device checklist](docs/IOS_PREVIEW_AR.md)
- [Why a link can work natively but fail on the public website](docs/WEB_TROUBLESHOOTING_AR.md)
- [Workspace cleanup scope and retained files](docs/CLEANUP.md)

## Limitations

- Site availability and media access remain subject to the target platform's own restrictions, bot protection, login requirements, and regional access rules.
- Source-based desktop builds use the local Python environment. Published Windows ZIPs include Python, FFmpeg and Node.
- The public web edition uses the isolated API described in [web deployment](docs/WEB_DEPLOYMENT.md). The development bridge remains local only.
- The iOS preview uses the hosted engine, with its 96 MiB file and 225-second preparation/transfer limits. It requires foreground execution and does not include Android's background service or a local Python/FFmpeg engine. Linux and macOS native builds are unverified.

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

The header information icon opens Mohamed Fooda's developer page, GitHub and LinkedIn links, and edition downloads. Android APK and portable Windows ZIP assets are hosted on [GitHub Releases](https://github.com/MTFOODA/nazzelha/releases/latest). The separate [iOS preview guide](docs/IOS_PREVIEW_AR.md) covers unsigned IPA builds and personal signing; the latest stable Android/Windows release remains separate.

See [deployment and free-hosting limits](docs/WEB_DEPLOYMENT.md) and [release build instructions](docs/RELEASES.md).

The [Vercel Hobby path](docs/VERCEL.md) streams each prepared file into the visitor's browser and creates playlist ZIPs there. It supports Python without assuming persistent function-local storage, with explicit per-video, browser-memory and hosting limits.
