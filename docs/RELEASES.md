# Release 1.1.1

Version: `1.1.1+3`. Official GitHub/LinkedIn profile marks, theme-aware GitHub variants, and corrected video-only quality menus. GitHub asset names used by the app's developer page:

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

- Flutter: analyzer clean; 42 tests passed, two optional live tests skipped.
- Python: 24 tests passed, including storyboard/audio quality exclusion.
- Cloudflare Worker: four routing/isolation tests passed.
- Edge 156: public 1.1.1 UI and official logos rendered; browser byte/ZIP
  harness passed with exact Arabic folder names and complete contents.
- Android: signed APK version 1.1.1/code 3 verified and installed as an update
  on the dedicated emulator; developer screen inspected. The earlier native
  background playlist and per-entry control integration checks passed.
- Windows: version 1.1.1+3 portable app starts its bundled engine with Python,
  Node and FFmpeg absent from PATH and JAVA_HOME empty.
- Public Vercel: Facebook example produced an MP4 with AV1 video/AAC audio.
  YouTube playlist metadata returned three entries; media requests were
  rejected by YouTube from the hosting network. See VERCEL.md for web limits.
- No native iOS build or physical iPhone verification was performed.
