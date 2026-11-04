# Downloads, playlists, and app refresh

## Download fixes

- Desktop JSON input/output is explicitly UTF-8, including the Dart process input. Windows code-page decoding previously changed an Arabic playlist folder into a second, corrupted name.
- On desktop, loading an existing playlist repairs its known UTF-8/code-page folder alias, moves only its recorded files, and updates saved paths. Existing files are never overwritten. Empty aliases are removed; unrelated folders remain untouched.
- Android and desktop share URL validation, extraction options, Facebook canonical-URL fallback, and final-output checks. yt-dlp is pinned to 2026.10.26.
- YouTube selects the highest resolution and frame rate, preferring HTTPS over HLS at equal quality. Missing fragments fail the item rather than incorrectly reporting success.
- Desktop FFmpeg resolves from an explicit override, PATH, or the installed portable imageio-ffmpeg package. Cancellation releases the worker so the next operation can run.

## YouTube playlist

Use the Playlist navigation destination. Paste a YouTube URL containing `list=`, extract the list, choose the folder name, and start. Each video has its own status; an unavailable item does not prevent the others downloading. Completed items are skipped when resuming. The name is locked after files have been saved so retries keep the same destination.

Public output is `Downloads/Nazzelha/YouTube/Playlists/<chosen name>` (Android uses `Download`). Android owns the sequential queue in a foreground service with a notification and wake lock; it continues when the activity is backgrounded. Saved state supports resuming remaining videos. This does not promise uninterrupted execution after an Android force-stop.

## Download queue and history

The first destination is Nazzelha, with all single-video controls inside each card. The separate single-download screens have been removed. Each card can fetch the available resolutions, retain its own selected quality, and pass that exact choice to the downloader. Best available remains the default. Changing the URL/platform clears stale choices.

The History destination stores multiple playlists and migrates the previously saved playlist. Its list shows playlist names and downloaded/remaining counts. Open a row for its videos: each unfinished video has an independent Resume button and every video can be removed from the queue. Removing a record or video keeps already downloaded files. Removed entries stay excluded from retries and native snapshots. A single-video retry does not start other pending entries. History updates even while a different playlist is being viewed.

Folder buttons open the download location instead of copying text. Windows reveals an existing video in Explorer; the browser asks its local bridge to do the same. Android resolves MediaStore relative paths and opens the corresponding directory in Files. A system folder-picker fallback supplies the initial URI on devices without a directory-view handler ([Android documentation](https://developer.android.com/training/data-storage/shared/documents-files)). Opening locations works independently of an active download.

## Unavailable Facebook videos

The first supplied public share video downloaded successfully. The second share URL and direct video `1124975946568625` did not expose public media. Authenticated downloading of that video has not been verified. At the user's request, the platform-session button and import dialog are removed. Access/extraction failures show the short requested publisher-restriction message in Arabic/English; network and storage failures retain their relevant messages. The interface uses Nazzelha / نزلها throughout.

## Interface and identity

The new [logo](../assets/logo/nazzelha-v2.png) is used by the launcher, splash screen, and interface. [The brand notes](BRAND.md) include the generation prompts and export commands.

Navigation adapts between a mobile bottom bar and a desktop side rail, preserves tab state, and supports swiping. Buttons, page changes, and theme changes use short transitions and respect reduced-motion settings. Arabic/English and dark/light modes share the same screens and settings. Poppins and Tajawal are bundled, so fonts do not depend on network access.

Rendered UI checks are saved in `build/ui_previews/`: `dark-ar-390.png`, `light-en-390.png`, `light-ar-1200.png`, and `dark-en-1200.png`. The `queue-` and `history-` variants show the per-card quality selector and compact playlist history. Explicit card/title styles also use bundled Tajawal fallback for Arabic glyphs.

## Verified behavior

- Flutter static analysis: no issues. Flutter unit/widget suite: 40 passed, two live tests skipped by default. Python suite: 13 passed.
- The supplied playlist `PLPqyWmL4W9D0` extracted three videos. Actual downloads completed on Edge through the local bridge, the Windows Dart/Python engine, and Android's native background service.
- A separate Windows live run downloaded all three into the exact Arabic folder `اختبار نزلها — Windows`. Another live run verified cancellation followed by a successful new command.
- The final Windows application also repaired the user's original completed playlist: all three existing MP4 files now live in `اناشيد عامة`, their stored paths were updated, and the empty corrupted alias was removed.
- Android was tested on an emulator, including backgrounding the activity. Its network required a test-only loopback CONNECT relay; TLS remained end-to-end. No physical Android device was verified.
- Final APK installation/startup succeeded, including Python/FFmpeg initialization. The final web build rendered successfully in Edge 156; its screenshot is `build/acceptance/edge-controls-card-final.png`.
- A Windows live location smoke test opened the original Arabic playlist directory and revealed an existing MP4 through the Dart service without errors.
- Responsive UI tests cover Arabic/English, both themes, narrow/wide layouts, navigation state, settings persistence, no session button, the requested inaccessible-video message, and reduced motion.

Reproduce the non-network checks from the repository root:

```powershell
flutter analyze --no-pub
flutter test test --no-pub
.\.venv\Scripts\python.exe -m unittest discover -s python_backend -p 'test_*.py'
```

Opt-in live Windows tests (download real media):

```powershell
flutter test test/desktop_live_test.dart --dart-define=LIVE_MEDIA_TESTS=true
```

The native control harness `integration_test/android_playlist_controls_test.dart` additionally passed real-service single-entry retry, persistent removal against a stale snapshot, history dismissal, and opening the exact Arabic folder in Files. ADB confirmed `Files in اختبار المسار`. These deterministic control checks use intentionally invalid URLs; the full real-media background test is separate.

The full live UI harnesses are `integration_test/edge_playlist_test.dart` and `integration_test/android_playlist_test.dart`.

## Local builds

- Android debug APK: `build/app/outputs/flutter-apk/app-debug.apk`.
- Browser build: `build/web`. Run `python python_backend/web_bridge.py` on the same computer; the bridge binds to loopback, port 8000. Serve the web build locally, or use `flutter run -d edge --no-web-resources-cdn`.
- Windows debug application: `build/windows_controls/runner/Debug/nazzelha.exe`. Launch it with `Run Nazzelha.cmd` at the project root so the Python backend is found reliably. Keep the whole output directory together. This is a local development build, not a standalone installer: it also needs the project Python backend and its environment.

This machine has the Visual Studio 2026 compiler but lacks its CMake integration. The final Windows build uses portable CMake from the Python environment. After Flutter has generated `windows/flutter/ephemeral/generated_config.cmake` for `lib/main.dart` and plugin links are present:

```powershell
.\.venv\Scripts\cmake.exe -S windows -B build/windows_controls -G 'Visual Studio 18 2026' -A x64 -DFLUTTER_TARGET_PLATFORM=windows-x64
.\.venv\Scripts\cmake.exe --build build/windows_controls --config Debug --target INSTALL --parallel 4
```

These checks cover the supplied media and the listed environments. They do not establish that every link on every supported service is accessible, or verify iOS, macOS, Linux, or a release-signed Android package.
