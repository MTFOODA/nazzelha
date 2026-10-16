# Bundled FFmpeg cannot link on 16 KB–page Android devices — root cause & fix

## Symptom
On a 16 KB page-size device (Android 17 / API 37 emulator `emu64xa16k`, x86_64),
the bundled FFmpeg CLI is unusable and yt-dlp cannot merge separate
video/audio streams. The failure reported in logcat / diagnostics is misleading:

```
CANNOT LINK EXECUTABLE ".../libffmpeg.so":
  empty/missing DT_HASH/DT_GNU_HASH in ".../libffmpeg.so" (new hash type from the future?)
```

or, once the loader gets far enough, the clearer message:

```
"<lib>" program alignment (4096) cannot be smaller than system page size (16384)
```

## Root cause (proven against AOSP source)
The bundled FFmpeg binaries are **4 KB page-size ELFs**. They were built with
**NDK r25.1.8937393** (see the `configuration:` string embedded in the binary),
whose linker defaults to `-z max-page-size=4096`. On a 16 KB device bionic
refuses to load them.

The decisive check is `ElfReader::CheckProgramHeaderAlignment()` +
`ElfReader::FixMinAlignFor16KiB()` in
`bionic/linker/linker_phdr.cpp` and `bionic/linker/linker_phdr_16kib_compat.cpp`
(tag `android-17.0.0_r1`):

```cpp
bool ElfReader::CheckProgramHeaderAlignment() {
  max_align_ = min_align_ = page_size();          // 16384 on a 16 KB device
  for (each PT_LOAD) {
    max_align_ = std::max(max_align_, p_align);
    if (phdr->p_align > 1) min_align_ = std::min(min_align_, p_align);
  }
  if (kPageSize == 16 * 1024) FixMinAlignFor16KiB();   // <-- the real culprit
  return true;
}
```

```cpp
void ElfReader::FixMinAlignFor16KiB() {
  // ... RELRO prefix check ...
  // Binaries whose LOAD segments OVERLAP when loaded with 16 KiB pages must be
  // loaded in 16 KiB compatibility mode.
  ElfW(Addr) prev_load_end = 0;
  for (each PT_LOAD) {
    if (prev_load_end > page_start(phdr->p_vaddr)) {   // page_start = align DOWN to 16 KB
      min_align_ = 4 * 1024;                            // FORCED to 4096
      break;
    }
    prev_load_end = phdr->p_vaddr + phdr->p_memsz;
  }
}
```

and then, in `LoadSegments()`:

```cpp
if (kPageSize >= 16384 && min_align_ < kPageSize && !should_use_16kib_app_compat_) {
  // prints exactly: "\"%s\" program alignment (%zu) cannot be smaller than system page size (%zu)"
  ...
  return false;   // link fails
}
```

### Why our binaries trip it
The bundled FFmpeg LOAD segments have **virtual addresses that are only 4 KB
aligned**, e.g. for `libpostproc.so`:

| # | p_vaddr | p_memsz | `page_start(p_vaddr)` @16 KB | overlap check |
|---|---------|---------|------------------------------|---------------|
| 0 | `0x0`    | `0x2D1C` | `0x0`    | ok |
| 1 | `0x3D20` | `0x1F020`| `0x0`    | `prev_end 0x2D1C > 0x0` → **OVERLAP → min_align_ = 4096** |

`page_start(0x3D20)` floors to `0x0`, which is below the previous segment's end
`0x2D1C`, so bionic concludes the segments would overlap and forces compat mode.
With 16 KB app-compat **disabled** for the process, the load aborts — and because
the DYNAMIC segment never gets mapped, the loader additionally reports the
cryptic `empty/missing DT_HASH/DT_GNU_HASH`.

## Why "patching p_align" cannot fix it
We tried realigning the ELFs (`_realign.py` / `_fix_all.py`): set `p_align` to
`0x4000`/`0x8000`/`0x10000` and made `p_offset ≡ p_vaddr (mod 0x4000)`. It does
**not** help and is actively harmful:

* The overlap check above runs **after** the `p_align` scan and overwrites
  `min_align_` to `4096` **regardless of the `p_align` we set** — the reported
  value stayed a constant `4096` for every `p_align` we wrote.
* A correct 16 KB layout requires moving the LOAD segment **virtual addresses**
  to 16 KB boundaries (e.g. `0x3D20 → 0x4000`) and fixing every internal
  reference (dynsym `st_value`, `.rela.*` `r_offset`/`r_addend`, `.dynamic`
  pointers, GOT/init-array relocations, RELR…). That is exactly a re-link, not a
  header tweak.
* Empirically, the realigned binaries stop producing the alignment error (with
  compat on) but then **segfault**; the pristine binaries instead fail with
  `DT_HASH`. Neither state works.

Verified on-device: every copy of every lib (app-data, `/data/local/tmp`,
installed APK lib dir) reads back with the same headers by md5 and
`llvm-readelf`, so this is not a stale-file problem.

## The fix: rebuild FFmpeg with 16 KB alignment
Rebuild the **same** FFmpeg configuration with a linker that emits 16 KB-aligned
segments — **NDK r27+ defaults to `-Wl,-z,max-page-size=16384`**, or pass it
explicitly. Then replace, for all three ABIs:

* `android/app/src/main/jniLibs/<abi>/libffmpeg.so`   (CLI executable)
* `android/app/src/main/jniLibs/<abi>/libffprobe.so`  (CLI executable)
* the eight `libav*.so` / `libsw*.so` / `libpostproc.so` inside
  `android/app/src/main/jniLibs/<abi>/libffmpeg.zip.so`

A ready-to-run build script is provided: **`_build_ffmpeg_16k.sh`**
(see the embedded `configuration:` line in the current binaries for the exact
upstream flags; only the NDK and the extra `-Wl,-z,max-page-size=16384` change).

### Original upstream build (extracted from the binary)
```
--prefix=.../ffmpeg/<abi> --enable-cross-compile --target-os=android --arch=<abi>
--sysroot=<ndk>/sysroot --cc=<ndk>/bin/<triple><api>-clang ...
--extra-cflags='-O3 -fPIC -I<external>/<abi>/include'
--extra-ldflags='-L<external>/<abi>/lib -lm -lm -lm -lm -lz'
--enable-shared --disable-static --disable-vulkan --enable-protocol=https
--enable-version3 --enable-gpl --enable-libaom --enable-libdav1d
--enable-libmp3lame --enable-libopus --enable-libtwolame --enable-libspeex
--enable-libvpx --enable-libwebp --enable-libfreetype --enable-libfribidi
--enable-mbedtls --enable-libbluray --enable-libx264
```
Built with NDK **25.1.8937393**, API **21**, by a GitHub-Actions project
(`/home/runner/work/build-ffmpeg/build-ffmpeg`). The single change required is
**NDK r28 (or r27+) + `-Wl,-z,max-page-size=16384`**.

### External codec dependencies (must be rebuilt too)
The upstream FFmpeg links external libraries **statically**, so they end up
compiled into `libavcodec.so` / `libavformat.so`. They therefore have to be
rebuilt from source with the same 16 KB alignment, or dropped. The app's Python
backend only needs two FFmpeg capabilities:

* **stream merge** (`-c copy`) for the video mode — pure FFmpeg, no external lib;
* **MP3 extraction** for the audio mode (`FFmpegExtractAudio`,
  `preferredcodec="mp3"` — see `android_backend.py::_get_yt_dlp_opts`) — needs
  **libmp3lame**, because FFmpeg has no native MP3 encoder.

`_build_ffmpeg_16k.sh` therefore builds **libmp3lame 3.100 from source** with the
same NDK/alignment settings (static, `-fPIC`) and links it in with
`--enable-libmp3lame`. Note: FFmpeg's configure looks for `<prefix>/include/lame/lame.h`,
so the header must be installed as `include/lame/lame.h` (not `include/lame.h`),
and `--pkg-config=false` requires `-lmp3lame` to be findable via `--extra-ldflags`.

The remaining upstream externals (libaom, libdav1d, libopus, libtwolame,
libspeex, libvpx, libwebp, libfreetype, libfribidi, mbedtls, libbluray, libx264)
are **not** rebuilt and remain disabled — nothing in the app calls them.
Consequence: AV1/VP9 *decoding* is unavailable (DASH video on YouTube/Instagram
is frequently AV1). That is harmless for merging, because `-c copy` never
decodes, and it is proven end-to-end below. A future transcode/re-encode feature
would need dav1d (and friends) rebuilt the same way. Never reuse the old 4 KB
prebuilt libraries to "complete" the feature set — they reintroduce exactly the
linker failure described above.

## Interim note (do NOT ship as the fix)
`bionic.linker.16kb.app_compat.enabled=true` (device-wide) removes the
*alignment* error, but the spawned `ffmpeg` main executable still fails
(compat mode is applied per-process by the framework, not to an `exec()`ed
child). It is a debugging aid only, not a shippable fix.

## Status of the repository binaries
`android/app/src/main/jniLibs/**` now contains the **16 KB rebuilds** for all
three ABIs (`x86_64`, `arm64-v8a`, `armeabi-v7a`). The pristine 4 KB originals
are preserved in `_orig_jniLibs/` and can be restored at any time with
`_revert_jniLibs.py`.

Tooling (project root; `C:\ffbuild\` holds the build trees and logs):

| file | purpose |
|------|---------|
| `_build_ffmpeg_16k.sh`   | builds libmp3lame + FFmpeg 5.1.4 for all ABIs (Git-Bash + NDK r28 + `-Wl,-z,max-page-size=16384`) |
| `_ff_finalize.py <abi>`  | packages `out/<abi>` → `pkg/<abi>` and asserts ELF class/machine + 16 KB alignment |
| `_install_ffmpeg_16k.py` | copies `pkg/<abi>` → `jniLibs/<abi>` (prints md5 before/after) |
| `_verify_final.py`       | re-verifies the installed `jniLibs`, including the libs inside `libffmpeg.zip.so` |
| `_revert_jniLibs.py`     | restores the pristine 4 KB originals from `_orig_jniLibs/` |

Remaining diagnostic files in the project root (`_realign.py`, `_fix_all.py`,
`_a17_*.cpp`, `_lk.cpp`, `_run2.txt`, `_*.ps1`, …) are investigation artefacts
(AOSP source dumps, header-patching experiments, logs) and are safe to delete.

## Verification (16 KB emulator `sdk_gphone16k_x86_64`, Android 17)
1. `_ff_finalize.py` / `_verify_final.py`: 30/30 artifacts report
   `min_p_align=0x4000`, `overlap16k=False` → **ALL PASS** for every ABI.
2. App `initialize()` diagnostics:
   `"ffmpeg_run_ok": true`, `"ffmpeg_version": "ffmpeg version 5.1.4 Copyright …"`,
   `"ffmpeg_error": ""` — previously `"ffmpeg_run_ok": false` with
   `CANNOT LINK EXECUTABLE … empty/missing DT_HASH/DT_GNU_HASH`.
3. The app's own extracted runtime (`run-as … bin/ffmpeg -version`) exits 0, and
   `-encoders` lists `A....D libmp3lame  libmp3lame MP3 (MPEG audio layer 3)`.
4. Direct functional test through that same runtime: a two-input `-c copy` merge
   yields `stream,mpeg4,video` + `stream,aac,audio` in the merged MP4, and
   `-c:a libmp3lame` yields `format_name=mp3` (192 kbps) that decodes with
   `decode_exit=0`.
5. Real UI downloads on the 16 KB emulator:
   * 1080p YouTube video+audio → 134 657 122-byte MP4 containing `av1` video +
     `opus` audio (merged on-device);
   * audio mode → `Download/Nazzelha/Me at the zoo.mp3`, 457 389 bytes,
     `codec_name=mp3`, 192 261 bps, `decode_exit=0`;
   * video mode on the same clip → `Me at the zoo.mp4` with `av1` + `opus`
     merged, `probe_exit=0`.

## Operational notes
* `/data/local/tmp` binaries must be `chmod 755` after `adb push` (adb push sets
  0644) before the shell can `exec()` them. `run-as <pkg>` can execute the app's
  extracted `bin/ffmpeg` with `LD_LIBRARY_PATH=<…>/ffmpeg/usr/lib`.
* The app cannot read `/sdcard/Download/Nazzelha/*` directly (scoped storage);
  verify those outputs from the `shell` user (which can) or from the app's UI.
* `adb install` of the ~175 MB debug APK takes several minutes on the emulator;
  `libffmpeg.zip.so` legitimately makes the Gradle strip task log
  `The file was not recognized as a valid object file` (it is a zip, not an ELF)
  — that warning is harmless.

