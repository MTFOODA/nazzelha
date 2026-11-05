# Nazzelha illustrated walkthrough

[Watch/download the Arabic MP4](media/Nazzelha-Walkthrough-AR.mp4) · [Chapters](DEMO_CHAPTERS_AR.md) · [Annotated guide](guide-ar.html) · [Arabic manual](USER_GUIDE_AR.md)

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

The public Facebook sample completed in the Android 7 foreground service with
the activity backgrounded after resuming a transient TLS failure. The persisted
terminal result reports success and a 1,062,959-byte MP4. A media decode check of
that particular Android-downloaded file was not completed after command
approval became unavailable. Do not treat fixture screenshots as proof of it.

A new live screen recording remains pending: Windows Computer Use could not
connect to its native pipe after the prescribed retries/reset, and further ADB
commands requiring automatic approval were stopped by an approval usage limit.
No alternate execution path was used to bypass that approval failure.

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
