# Android YouTube playlist repair — physical-device acceptance

The user's Android 17 phone originally ran signed version 1.1.3/code 5. Its real
foreground-service logs show extraction failing before any media transfer with
`This video is not available` for all six playlist IDs:

`P8BqrRQehTM`, `Ls0zGx4AaMs`, `f830zgh5UrA`, `-pmD_4rmHT4`,
`cB4ACt11y-g`, `IRQXn24Naw4`.

The runtime report confirms `yt_dlp_ejs=false`. An offline inspection of the
published APK also found no JavaScript executable. Windows packages EJS and
explicitly enables Node. With no JavaScript provider, the pinned yt-dlp uses a
limited default YouTube client set; this is a confirmed capability gap, while
the repaired runtime has since passed the user's six-video acceptance below.

References: [yt-dlp's EJS setup](https://github.com/yt-dlp/yt-dlp/wiki/EJS),
[the pinned default client selection](https://github.com/yt-dlp/yt-dlp/blob/2026.10.26/yt_dlp/extractor/youtube/_video.py),
[the matching EJS 0.8.0 dependency](https://github.com/yt-dlp/yt-dlp/blob/2026.10.26/pyproject.toml).

## Implementation

- Pin Android's solver to `yt-dlp-ejs==0.8.0` for yt-dlp 2026.10.26.
- Build QuickJS-NG 0.18.0 from upstream commit
  `d7215b0ad3fc2c562e8317fd9bca058fd4863804`, with NDK 28.2.13676358.
- Target Android API 24 and verify ARM, ARM64 and x86_64 PIE executables have
  16 KiB-compatible load segments. Package them as `libqjs.so` in the system's
  executable native library directory, alongside the established FFmpeg model.
- Both the activity and foreground service already call the same Python
  initialization. It checks the actual executable and EJS package, and enables
  the local QuickJS provider for metadata/video/audio YouTube operations.
- A missing or failing local engine reports `LOCAL_RUNTIME_MISSING`, with an
  Arabic/English message, rather than claiming the publisher restricted it.
- No public proxies, shared sessions or remote challenge-code downloads.

## Build and acceptance

On the Windows development machine, run
`tool\build_android_playlist_candidate.cmd`. It runs Flutter analysis/tests,
builds the signed candidate using the existing signing key, verifies APK
integrity/ABIs/page alignment and packaged EJS scripts, and saves a result to
`build/android-playlist-candidate/result.json`. It **does not install, uninstall,
publish, or change any phone settings**. Build logs are private generated files.

The first manually executed candidate builder completed successfully on 2026-11-06:

- Flutter analysis is clean; 48 tests passed and two optional tests were skipped.
- Native QuickJS compilation passed for all three ABIs; every load segment has
  alignment 16,384. The matching EJS resources are present inside the APK.
- The APK is version `1.2.0+6`, minimum API 24, signed with the existing release
  identity. Signature, ZIP integrity, native architectures and 16 KiB ZIP/ELF
  alignment checks passed.
- APK SHA-256: `d5184ed4d7a779fb251372c5d85502a4fe3181131e532dbffeb765f6464c9f08`.
- Independent ZIP inspection confirmed the packaged Android Python sources
  matched the sources at build time and included both EJS solver scripts.

Offline Python checks also pass: 31 tests, including five new Android
runtime/packaging checks. They use mocks and synthetic ELF fixtures; they do not
prove execution on a phone.

The first candidate updated the physical Android 17 phone without clearing
data. Its native QuickJS self-check returned 42 with EJS available. The first
previously failing video `P8BqrRQehTM` completed and was saved in the chosen
Arabic folder (8,498,060 bytes). Capture ended while the second entry was still
running; full six-video acceptance is not established by that recording.

Startup logs also exposed concurrent media initialization and an FFmpeg
`PermissionError` caused by a link/copy preparation race. The latest source
serializes activity/service initialization, atomically replaces executable
links, and forbids app-data executable copies on Android 10+. These follow-up
changes were built and tested in the second candidate; they are not in the first
candidate SHA above. YouTube diagnostics remain bounded, redact URL queries and
credentials, and expose periodic progress only in private process logs.

Run `tool\install_android_playlist_candidate.cmd` to verify the installed app's
signing identity, update without clearing data, launch the app and capture the
same playlist test. The helper refuses a signing mismatch and never uninstalls
the app. A separate Android 7 startup/JavaScript acceptance workflow is provided
at `.github/workflows/android-runtime.yml`. Its probe checks
the actual JavaScript process and EJS availability, not a real YouTube download.

## Confirmed second candidate and 1.2.1

The second signed `1.2.0+6` candidate includes the initialization repair:

- Size: 92,679,868 bytes.
- SHA-256: `f9c9710adb21cff72f67a15a16688f7a25833ca95decfdbb11dc578e89d55039`.
- Installed as an update on the physical Xiaomi 15T Pro / HyperOS 3 / Android 17,
  preserving application data and using the existing release certificate.
- Native startup logs confirm `ffmpeg_run_ok=true`, JavaScript and EJS available,
  and an executable JavaScript self-check returning 42.
- The user explicitly confirmed **6 of 6 downloaded** for the reported playlist
  on 2026-11-06. This complete outcome is user acceptance; the private diagnostic
  captures do not individually record all six final file events.

Version `1.2.1+7` keeps the accepted native engine and adds **Clear page** to the
playlist editor. It retains history and saved files, disables clearing during
an active playlist, and persists the empty editor through native polling and
reopening. Flutter analysis is clean; 49 tests pass with two optional live tests
skipped. The isolated Android integration check uses a completed text fixture
to verify clearing and file retention without downloading real YouTube media.

Minimum supported Android API remains 24. A minimum SDK declaration and native
ELF inspection alone do not prove execution on every device or Android release;
check the release verification report for actual emulator/device evidence.
