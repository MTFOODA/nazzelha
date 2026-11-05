# Nazzelha illustrated walkthrough

[Live Android demo](media/Nazzelha-Live-Demo-Android.mp4) · [Arabic illustrated walkthrough](media/Nazzelha-Walkthrough-AR.mp4) · [Chapters](DEMO_CHAPTERS_AR.md) · [Annotated guide](guide-ar.html) · [Arabic manual](USER_GUIDE_AR.md)

## Live Android recording

The separate live video records the signed 1.1.3 app on the isolated Android
7/API 24 emulator. It is 720×1280 H.264, about 3:53, silent, and explicitly sped
up to 1.75×. Three genuine captures are joined; the first is trimmed after the
Facebook completion sequence. Static frames are held between screen updates;
no download or success state is fabricated.

- 00:00: Facebook URL, video/audio selection, quality lookup, download,
  Android Home while the service works, and return to the completed card.
- 00:57: actual YouTube playlist extraction, three entries, chosen folder
  `اناشيد عامة Demo`, start, background execution and pause.
- 02:32: history counts, dark mode, English/Arabic, developer links and edition
  choices, individual video resume, and deliberately removing the third item.
  The two remaining videos complete in that same folder.

Both playlist MP4s and the Facebook MP4 passed full FFmpeg decode checks.
[Live download evidence](live-download-verification.json) records the folder,
file sizes and the intentionally excluded item. The raw recorded app honestly
shows temporarily unavailable statistics during the session. Android 7's
document picker may start at Recent instead of honoring the initial subfolder;
the user manual explains this OS/file-manager limitation.

The live capture uses Android SDK recording and UI inspection, not Windows
desktop automation. The Windows Computer Use helper was unavailable; no new
Windows live recording is claimed. Windows package startup was independently
verified. `live-captions.json` contains the live video's Arabic chapter labels.
`tool/render_live_demo.py` reproduces the edit when the three local original
captures (`01-facebook-final.mp4`, `02-playlist-good.mp4`, and
`03-history-settings.mp4`) are available in `build/live_demo`. Raw captures are
kept locally as editing inputs, excluded from the source repository.

## Illustrated walkthrough

The video is 3 minutes 5 seconds, 1280×720 H.264, with Arabic captions and no
audio track. It covers navigation, each download-card control, playlist folder
naming, per-item actions, history, Android background execution, languages,
themes, developer links, edition selection, statistics and web limits.

This is an illustrated walkthrough assembled from application UI captures. The
sample URL, counts, paths and playlist states in the UI preview captures are
demonstration fixtures, not recordings of new live downloads. The video labels
this throughout. Real verification results are separate in
[verification-1.1.3.json](verification-1.1.3.json) and
[ANDROID_INSTALLATION.md](ANDROID_INSTALLATION.md).

The earlier public Facebook sample also completed in the Android 7 foreground
service with the activity backgrounded after resuming a transient TLS failure.
The persisted result reports success and a 1,062,959-byte MP4. Its full media
decode was completed successfully after command approval resumed. Do not treat
fixture screenshots in the illustrated video as proof of actual transfers.

## Rebuild

Keep the supplied PNG captures in `docs/media`. Install Pillow in the authoring
environment and provide FFmpeg built with the `ass` filter (libass). Font license
files remain beside the fonts in `assets/fonts`.

```powershell
python tool/build_walkthrough.py --ffmpeg "C:\path\to\ffmpeg.exe"
# Rebuild only the interactive HTML guide:
python tool/build_walkthrough.py --html-only
```

`docs/walkthrough.json` is the editable source for control locations, explanations
and video scenes. `build/walkthrough` contains disposable render intermediates.
`docs/media/Nazzelha-Walkthrough-AR.mp4` is the finished artifact. Replacing a
capture requires reviewing its annotation coordinates before publishing.

## Capture a future live demonstration

Use an isolated app/test profile and the user-supplied public Facebook sample
and YouTube playlist from the manual. Record adding a card, choosing quality,
starting/resuming, opening the completed location, extracting the playlist,
choosing an Arabic folder, removing/resuming individual entries, inspecting
history, and the settings/developer screens. On Android also record returning
to Home while the foreground service works, then returning to the app. Leave
private accounts, device identifiers, notification content and signed media
URLs out of the recording. Show upstream failures honestly. Do not claim an
iOS native build or successful web YouTube transfer where none was verified.
