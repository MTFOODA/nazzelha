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

Prepare these files in `build/deliveries/` before running
`python tool/publish_release.py --publish`:

- `Nazzelha-Android.apk`
- `Nazzelha-Windows-x64.zip`
- `Nazzelha-Documentation.zip`
- `Nazzelha-Walkthrough-AR.mp4`

The publisher generates `SHA256SUMS.txt`, uploads a draft, validates GitHub
asset digests and sizes, then publishes when `--publish` is present. It obtains
the GitHub credential in memory from Git Credential Manager and never prints
or uploads it. Commit and push the reviewed source first. An already-public
version's assets are not overwritten. This helper is currently prepared for
tag `v1.1.3`; review the version and notes before reusing it for another release.
