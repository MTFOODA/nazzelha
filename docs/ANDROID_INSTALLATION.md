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

The user-reported HyperOS 3.0.337.0 / Android 17 CP2A / Xiaomi 15T Pro refusal
was not reproduced on the stock emulator. These checks do not establish its
specific cause. Read the affected device's installer log to confirm that cause.
