# Release 1.1.2

Version: `1.1.2+4`. Persistent website visit totals, separate Windows/Android release-download counts, two platform selection buttons, and a consistent header across all three destinations. GitHub asset names used by the app's developer page:

- `Nazzelha-Android.apk`: signed universal release APK.
- `Nazzelha-Windows-x64.zip`: portable Windows x64 application and download engine.
- `SHA256SUMS.txt`: asset checksums.

There is no IPA in this release. Building and signing native iOS requires a
macOS/Xcode build environment, iOS backend implementation and Apple signing.
The iPhone/iPad edition button opens the web app with Safari Home Screen guidance.

## Android

Run `python tool/prepare_release_signing.py` once, then
`python tool/build_android_release.py` with Flutter on PATH or `FLUTTER_BIN` set.
The helper prepares release configuration, removes only dev-dependency entries
from the generated Java registrant when the installed SDK leaves them there,
then runs Gradle and copies the APK to `build/deliveries/`. Test plugins remain
excluded from release builds.
The key and passwords are generated in ignored `.release/`. **Back up both the
keystore and signing.properties privately**: future Android updates require the
same key. They are never uploaded with source or releases. Release builds fail
if signing is missing instead of silently using a debug certificate.

An existing debug-signed installation cannot update in place to this release
certificate. Preserve app data before replacing it. Public downloaded videos
are separate from private app history.

Do not run Flutter tests, pub get or other Flutter builds in parallel with the
Android build: they can regenerate the plugin registrant for a different build
mode while Gradle is still compiling it.

## Windows

Install `python_backend/requirements.txt` and `tool/requirements-release.txt` in
the build virtual environment. Run `python tool/package_engine.py` with Node.js
on PATH. Build the Flutter runner in Release, then run `python tool/package_windows.py`.
The final ZIP includes the Python engine, FFmpeg, Node.js, plugin DLLs, Flutter
assets and the Visual C++ runtime DLLs from Visual Studio's redistributable folder.

On this workspace, Visual Studio's CMake integration is missing. Flutter still
generates the versioned configuration before reporting that toolchain issue;
the installed portable CMake builds it with Visual Studio 18 2026:

```
flutter build windows --release --config-only --no-pub
cmake -S windows -B build/windows_release -G "Visual Studio 18 2026" -A x64 -DFLUTTER_TARGET_PLATFORM=windows-x64
cmake --build build/windows_release --config Release --target INSTALL --parallel 4
python tool/package_windows.py
```

The Windows executable is unsigned. It needs the adjacent `backend/` and `data/`
folders. Test from outside the source tree with Python, FFmpeg and Node absent
from PATH to verify that the bundled engine is used.

Publish assets against the matching source commit/tag and verify each public
download URL before announcing the release. Never publish `.release/` contents.

## Verification on 2026-11-05

- Flutter: analyzer clean; 44 tests passed, two optional live tests skipped.
- Python: 24 tests passed, including storyboard/audio quality exclusion.
- Cloudflare Worker: eight statistics/routing/isolation tests passed.
- Edge 156: public 1.1.2 UI, platform selections and live counters verified on both domains; reload preserved the visit session; browser byte/ZIP
  harness passed with exact Arabic folder names and complete contents.
  In the preceding 1.1.1 verification, the real Facebook sample was also downloaded through the published Flutter
  card and saved using its Save to your device button. The saved MP4 matched
  the API's SHA-256 digest and decoded with FFmpeg without errors.
- Android: signed APK version 1.1.2/code 4 verified and installed as an update
  on the dedicated emulator; developer screen inspected. The earlier native
  background playlist and per-entry control integration checks passed.
- Windows: version 1.1.2+4 portable app starts its bundled engine with Python,
  Node and FFmpeg absent from PATH and JAVA_HOME empty.
- Public Vercel: Facebook example produced an MP4 with AV1 video/AAC audio.
  YouTube playlist metadata returned three entries; media requests were
  rejected by YouTube from the hosting network. See VERCEL.md for web limits.
- No native iOS build or physical iPhone verification was performed.

Published release: https://github.com/MTFOODA/nazzelha/releases/tag/v1.1.2.
All three release asset URLs were verified anonymously. Uploaded APK/ZIP hashes
match the local SHA256SUMS.txt. Public Cloudflare API routing and version 1.1.2
were verified in Edge after replacing an older concurrent automatic deployment.

Statistics persistence, 30-minute visit sessions, direct GitHub file counts and
15-minute refresh behavior are documented in [STATISTICS.md](STATISTICS.md).
The native Android statistics panel also loaded the same live counts.

## 1.1.3 compatibility and documentation artifacts

The final signed Android package fixes the Android 7 runtime calls and R8's
renaming/removal of Python-facing progress/cancellation callbacks. Update,
clean-install, launch and FFmpeg startup passed on API 24 and API 37 with both
4 KB and 16 KB pages. A real public Facebook download completed with the API 24
activity backgrounded after resuming a transient TLS failure. Windows 1.1.3's
bundled-engine startup also passed. See [installation evidence](ANDROID_INSTALLATION.md).

The documentation package includes an Arabic manual, a guide with 40 numbered
control locations, the 3:05 captioned illustrated MP4 and its editable source.
The video is not a new live interaction recording. See [demo scope](DEMO.md).
The separate live Android MP4 records real transfers, folder naming, background
execution and individual controls at 1.75x. Its two retained playlist MP4s passed
full decode checks; the third item was intentionally excluded in the demo.

Prepare these files in `build/deliveries/` before running
`python tool/publish_release.py --publish`:

- `Nazzelha-Android.apk`
- `Nazzelha-Windows-x64.zip`
- `Nazzelha-Documentation.zip`
- `Nazzelha-Walkthrough-AR.mp4`
- `Nazzelha-Live-Demo-Android.mp4`

The publisher generates `SHA256SUMS.txt`, uploads a draft, validates GitHub
asset digests and sizes, then publishes when `--publish` is present. It obtains
the GitHub credential in memory from Git Credential Manager and never prints
or uploads it. Commit and push the reviewed source first. An already-public
version's assets are not overwritten. This helper is currently prepared for
tag `v1.1.3`; review the version and notes before reusing it for another release.

## iOS 1.2.0 preview (2026-11-06)

The separate prerelease provides an unsigned ARM64 device IPA targeting iOS 15+
and a debug simulator app. The device app is a Release/AOT build, not the
simulator binary repackaged as an IPA. Personal signing is required; the free
Sideloadly route is documented in [the iOS guide](IOS_PREVIEW_AR.md).

[CI run 42134549733](https://github.com/MTFOODA/nazzelha/actions/runs/42134549733)
built both apps, installed and launched the full app on an iPhone 17 Pro / iOS
26.5 simulator, and passed the iOS HTTP/Unicode-file/history integration test.
The transfer test used 4,099 fixture bytes, not a real downloaded video. Flutter
analysis and 47 tests passed; two optional live tests were skipped. Physical
Apple signing and installation have not been verified.

This preview uses the hosted engine with its 96 MiB/225-second limits and
upstream YouTube hosting restrictions. It needs foreground execution. Keep the
current stable Android/Windows release as latest; publish iOS as a prerelease
with `make_latest: false` and never replace its existing native assets.

## 1.2.1 playlist clearing and Android runtime repair

Clear page empties the playlist editor while preserving downloaded files and
playlist history. The cleared selection survives native polling and reopening;
select a playlist from History to restore it. Clearing is disabled during an
active playlist or extraction. The Arabic manual and HTML guide describe it.

Android now bundles the matching EJS solver and a local QuickJS-NG executable
for all three supported ABIs. Shared, atomic media initialization fixes an
activity/service FFmpeg race. The user confirmed all six videos of the reported
playlist downloaded on the signed 1.2.0 acceptance candidate on Android 17.
1.2.1 retains that native engine and adds the Clear page interface. Details and
artifact identity are in [runtime acceptance](ANDROID_YOUTUBE_RUNTIME.md).

Flutter analysis is clean: 49 tests passed, two optional live tests skipped.
Python backend tests: 31 passed. Cloudflare tests: eight passed. Actual Android
7 acceptance and new release artifact checks are recorded in the accompanying
[1.2.1 verification report](verification-1.2.1.json). The actual API 24 emulator
passed JavaScript/EJS/FFmpeg startup and the native clear/poll/reload test with
history and a completed fixture file retained. The final signed APK updated
the physical Android 17 phone successfully without clearing data. These checks
do not establish execution on every supported Android version. iOS remains a separate unsigned
preview requiring personal signing and physical-device testing.
