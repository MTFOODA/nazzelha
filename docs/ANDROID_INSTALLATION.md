# Android installation and compatibility

Supported package: Android 7.0 / API 24 and later on ARM64, ARMv7 and x86_64.
The APK is universal, not a split APK. Devices below API 24 and 32-bit x86
devices are outside this package's supported targets.

Download `Nazzelha-Android.apk` from the project's GitHub release and open it
with Android's package installer. Allow installation for the browser/file
manager used to open that file when Android requests it. If Play Protect offers
a scan, follow the scan and its result. Do not disable security checks to test
installation.

An `App not installed` message does not identify its cause. The Package Manager
error from the affected device is needed to distinguish a corrupt/incomplete
download, insufficient storage, an incompatible version/ABI, an existing package
in another profile, a signing mismatch, and an installer/device policy refusal.
The APK has about 143 MB of uncompressed contents in addition to its download;
Android may require additional space for extraction and optimization.

Stable releases use the same certificate. An older debug-signed development
build cannot be updated by the release certificate. Do not uninstall an existing
app containing important history before exporting or backing up its private
data. This explanation applies only when such a conflicting installation exists.

## Verified public 1.1.2 artifact

The test APK was downloaded anonymously from GitHub, not copied from Gradle:

```
Size:   90921062 bytes
SHA256: 76b48e54c48b0a75411b0df48419d5f26a086c3b3d3f1716a56c96cdc574b75e
Signer: 18e10d4f4200ab4d54c82cf7c7e940ff9465488aee05240978d0610011c7d045
```

On Android 17/API 37 x86_64 with both 4 KB and 16 KB pages:

- Updating public 1.1.1 to public 1.1.2 succeeded and retained a theme preference.
- Removing the app and installing public 1.1.2 succeeded; the app opened.
- On the 4 KB image, installation through the normal Android installer also
  succeeded for both update and clean-install flows. Play Protect's scan returned
  `This app looks safe`. This scan is a test observation, not an independent
  security audit or a promise about every device's scanner.
- ARM64 and x86_64 ELF load segments and the APK's ZIP layout passed 16 KB
  alignment checks. ARM64 was inspected statically; these emulator tests run
  x86_64 code and do not reproduce Xiaomi's HyperOS firmware.

On Android 7/API 24, installation succeeded but the original app crashed at
startup with `NoClassDefFoundError: java.nio.file.Paths`. The FFmpeg symlink
setup in both the activity and background service used API 26 calls without a
version guard. Release 1.1.3 replaces them with `android.system.Os.symlink`,
available since API 21. The native audio process timeout also avoids the API 26
`Process.waitFor(timeout, unit)` overload.

The old AOSP image needed its mount-complete framework-start trigger when run
with the current emulator. Its app/API runtime remained Android 7. The image
and writable AVD data were isolated in the workspace; existing personal AVD
data and the physical phone were not modified.

## Build gate

`tool/build_android_release.py` invokes `tool/verify_android_release.py` before
accepting the distributable APK. The gate checks ZIP CRCs, signing identity,
modern APK signing, exact app/version metadata, minSdk 24, all three supported
ABIs, required native tools, ZIP alignment, and 16 KB ELF alignment for both
64-bit ABIs. Example:

```
python tool/verify_android_release.py build/deliveries/Nazzelha-Android.apk --expected-version 1.1.3 --expected-version-code 5
```

## Physical Xiaomi browser installation

On 2026-11-05, the user downloaded the public 1.1.2 APK through the official
website in Edge on a Xiaomi 15T Pro running HyperOS 3.0.337.0 / Android 17
(API 37, ARM64, 4 KB pages). Installation through the phone's normal installer
succeeded and the app opened. Its embedded Python engine reported `ready: true`
and `ffmpeg_run_ok: true`. The downloaded file matched the public SHA-256 above.

The older rejected APK still in the phone's Downloads folder had the same byte
length, but SHA-256
`ebdfb04d8e0520a39ad71103c964119551191a928f4ddbae94e4b45a1cf93e34`.
Its ZIP CRC check failed for `lib/armeabi-v7a/libffmpeg.zip.so`, and Android's
`apksigner verify` returned `APK integrity check failed` with a v2 content-digest
mismatch. This establishes that the old local APK was corrupt; it does not
establish where that corruption happened. A fresh download resolved the observed
installation failure without changing the APK signing identity, deleting app
data, or disabling security checks. USB touch control was restricted by HyperOS,
so the user pressed the download and installation controls while diagnostics
were collected over ADB.

## Release download callback compatibility

A live Facebook download in the signed release reproduced
`AttributeError: 'o' object has no attribute 'isCancelled'`. R8 had renamed or
removed `ProgressSink` methods used dynamically by Chaquopy from Python, so
successful extraction was followed by a failure at the first progress hook.
`android/app/proguard-rules.pro` preserves this interface and the two callback
methods in its activity/service implementations. Other code remains optimized.
See Android's [keep-rule guidance](https://developer.android.com/topic/performance/app-optimization/keep-rules-overview)
for dynamic calls outside R8's call graph. Signed-release download acceptance
must exercise the real foreground service, not just startup or a debug build.

## Candidate 1.1.3 verification

The corrected signed APK (version code 5) passed the independent package gate,
including all three ABI machine types and the eight packed FFmpeg shared
libraries in each ABI. Its current SHA-256 is:

```
6b651232cfc05a0f92baac413cc030d0a58de9aab2562b3ce788aa2127076e2e
```

On Android 7, both updating public 1.1.2 to this candidate and uninstalling then
installing the candidate succeeded. The update retained a seeded preference
(the old release cannot open on this OS). The corrected app opened normally and
reported `ready: true` and `ffmpeg_run_ok: true`. Android release lint completed
with zero errors and 29 warnings. Flutter analysis passed and 44 tests passed
(two optional live tests skipped).

On Android 17/API 37 x86_64 with both 4 KB and 16 KB pages, updating public 1.1.2 to the final
candidate succeeded with the theme preference preserved. Removing the app and
installing the candidate also succeeded; the app opened and FFmpeg reported
ready. Windows 1.1.3's portable package started its bundled engine with Python,
Node and FFmpeg absent from PATH.

A real download of the public Facebook example completed with the activity
backgrounded on Android 7 after this final callback fix. The persisted terminal
result was `success: true`, `phase: completed`, with a 1,062,959-byte
`API24Acceptance.mp4` in the public Downloads folder. The first request had a
transient TLS record error; the normal Resume action succeeded. After command approval resumed, the actual downloaded MP4 was pulled from
the isolated emulator and decoded completely with FFmpeg without errors. These results do not establish successful
access to private/account-only sources or every supported platform.

The physical-device browser installation above used public 1.1.2; the final
1.1.3 artifact was tested on the three emulator configurations described here.
Use GitHub Releases to determine the currently published version.
