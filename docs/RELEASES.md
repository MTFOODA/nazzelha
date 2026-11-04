# Release 1.1.0

Version: `1.1.0+2`. GitHub asset names used by the app's developer page:

- `Nazzelha-Android.apk`: signed universal release APK.
- `Nazzelha-Windows-x64.zip`: portable Windows x64 application and download engine.
- `SHA256SUMS.txt`: asset checksums.

There is no IPA in this release. Building and signing native iOS requires a
macOS/Xcode build environment, iOS backend implementation and Apple signing.
The iPhone/iPad edition button opens the web app with Safari Home Screen guidance.

## Android

Run `python tool/prepare_release_signing.py` once, then `flutter build apk --release`.
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
