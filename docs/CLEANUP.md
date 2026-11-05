# Workspace cleanup

The requested cleanup is limited to this Nazzelha project. No unrelated disk
folders, repositories, personal phone files or public release assets were
deleted.

Removed generated root-level one-off `_task_*` editing/probing scripts, stale
build logs, downloaded investigation pages and logo archives, abandoned ELF
header-patching experiments, the three `_testlibs*` experiment directories,
duplicate acceptance-test APKs, and the corrupt APK copied from the phone.
Their relevant findings were preserved in the installation notes and sanitized
verification summary. Counts and reclaimed bytes are in
[cleanup-summary.json](cleanup-summary.json).

Retained deliberately:

- `lib`, native platform code, assets/fonts, dependencies and runtime libraries.
- Useful `test`, `integration_test`, backend and Worker regression tests. These
  protect behavior; deleting them would reduce the project's ability to catch
  regressions and does not improve the distributed app.
- Signing material and credentials in their existing ignored private locations.
- Final distributable APK/ZIP files, finished documentation/video, and the
  underlying build environment.
- Personal AVD base data and any file still locked by a running process.
  After command approval resumed and recording/verification finished, only the
  two confirmed task-owned emulators were closed. Their disposable workspace
  data/system-image cache was cleaned; locked leftovers were skipped.
- The documented FFmpeg rebuilding/verification helpers and original native
  backup used by the existing rollback helper. These are not app runtime files.
- A local ignored task-resume note; no private diagnostics are published.

The reviewed release publisher moved from a disposable root helper to
`tool/publish_release.py`; it checks uploaded asset sizes/digests and refuses to
replace an already-public version. It is prepared for 1.1.3 and requires the
explicit `--publish` option to make a prepared draft public.

The second cleanup increased free disk space by approximately 11.4 GiB, in
addition to the earlier roughly 476 MiB of APK copies/root experiments.

Generated files under `build/`, caches and local helpers remain excluded by
`.gitignore`. Cleanup removes local experiments; it does not rewrite Git history
or remove useful tests from GitHub. Reviewed source/documentation updates use
the normal commit/push and release process; generated caches are not uploaded.
