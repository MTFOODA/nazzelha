# Bundled software

The Windows distribution includes the Flutter engine and plugin libraries,
Python, yt-dlp and its dependencies, yt-dlp-ejs, curl-cffi, imageio-ffmpeg,
FFmpeg, and Node.js. Third-party software retains its own license.

- Flutter: BSD-3-Clause. https://github.com/flutter/flutter/blob/master/LICENSE
- Python: PSF license, bundled in `backend/tools/PYTHON-LICENSE.txt`.
- Node.js: MIT and third-party licenses, bundled in `backend/tools/NODE-LICENSE.txt`.
- yt-dlp: Unlicense, https://github.com/yt-dlp/yt-dlp (dependency licenses apply).
- yt-dlp-ejs: Unlicense, https://github.com/yt-dlp/ejs.
- curl-cffi: MIT, https://github.com/lexiforest/curl_cffi.
- imageio-ffmpeg: BSD-2-Clause, https://github.com/imageio/imageio-ffmpeg.
- FFmpeg: run the bundled FFmpeg executable with `-L` for the precise build
  license and configuration. Source: https://ffmpeg.org/download.html and
  https://github.com/imageio/imageio-binaries (the Windows binary supplier).
- Poppins and Tajawal: SIL Open Font License. Full OFL texts accompany the fonts.

Flutter's in-app license registry includes package notices. The portable
backend preserves package metadata and available license files under `_internal`.

Build and dependency scripts are available in the matching GitHub source tag.

The Android YouTube runtime also includes QuickJS-NG 0.18.0 (MIT),
built from upstream commit `d7215b0ad3fc2c562e8317fd9bca058fd4863804` for the
three supported ABIs. Its license is packaged in APK assets at
`licenses/QUICKJS-NG.txt`. The matching yt-dlp-ejs 0.8.0 package retains its
Unlicense and dependency notices. See [the Android runtime build and
verification notes](ANDROID_YOUTUBE_RUNTIME.md).
