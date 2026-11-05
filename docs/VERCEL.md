# Vercel Hobby deployment

Vercel runs Python functions and supplies a free project subdomain under
`vercel.app`. A custom purchased domain is separate. Use **Hobby**, never upgrade
to Pro or enable paid resources for this project.

Hobby has a five-minute function duration and monthly compute/transfer quotas.
The ordinary 4.5 MB response limit does not apply to streaming responses.
Streaming still has the five-minute duration limit. These constraints make the
original long-lived process and server-side file-token cache unsuitable as-is.

## Stateless downloads

`api/index.py` loads `python_backend/serverless_api.py`. Each download starts a
separate child process running the shared download engine. It prepares the best
requested format, merges media using FFmpeg, then streams binary chunks in NDJSON
to the browser. The child and its FFmpeg process group are terminated on timeout
or disconnection. That invocation's temporary directory is removed afterward.

The browser reconstructs a Blob and exposes an explicit Save to your device
button. It builds playlist ZIPs locally, preserving the chosen Unicode folder
name. There is no dependency on a later HTTP request reaching the same function
instance, no shared process-global cancel action, no database and no Blob-storage
subscription. Media is held only in temporary browser memory until saved.

Current web limits are intentionally below the hosting/browser limits:

- 96 MiB per video, about 225 seconds to prepare it, followed by streaming within
  Vercel's total 300-second deadline. A slow connection can still time out.
- 128 MiB per playlist ZIP, at most 200 selected prepared videos.
- 256 MiB total temporary browser cache. Oldest files are evicted when full.
- One-hour cache lifetime and no cache persistence across reloads/tab closure.

Save ready videos before leaving the page. If a link is stale, its individual
Save action unlocks retry. Use the installed Android/Windows app for larger
playlists. Android background downloading remains in the installed app's native
foreground service. A browser tab cannot promise that background behavior.

Upstream sites may still reject datacenter IPs, require a login, or restrict a
particular video. Never present local tests as proof that every platform works
from Vercel's network; test the public deployment separately.

## Build and publish

`vercel.json` builds Flutter web 3.47.7 and prepares QuickJS-NG 0.18.0, a small
runtime supported by yt-dlp's JS solver. Its download is checked against the
official release's SHA256 digest. Native Windows continues to use bundled Node.
The file-based Vercel builder enforced a 225 MB function bundle limit during
deployment, so the cloud package uses QuickJS rather than the much larger Node
binary. Python 3.12 and pinned requirements are selected. The Python
bundle excludes the Flutter SDK, native sources, tests, assets and private keys.
FFmpeg is supplied by the imageio-ffmpeg wheel. GitHub release binaries are linked
from the developer page instead of being uploaded as website assets.

```
npx vercel login
npx vercel deploy --prod
```

Select the personal Hobby scope. Vercel supplies the exact production URL after
deployment. Do not announce a guessed subdomain as live. Connect the existing
GitHub repository to the resulting project for future deployments.

The same app can remain on Cloudflare's existing `nazzelha` Worker. Configure
`API_ORIGIN` to the verified Vercel HTTPS origin, then deploy the matching web
assets. This leaves the separate `azkar-sadaqa` Worker untouched.

## Verification

```
python -m unittest discover -s python_backend -p "test_*.py"
flutter analyze
flutter test
python tool/test_browser_transfer.py
```

The Edge harness verifies full byte reconstruction, ZIP contents, exact Arabic
folder names and rejection of incomplete/oversized transfers. The Python suite
checks a response over 4.5 MB, route rewriting, deadline cleanup and command/URL
restrictions. Live Vercel verification must additionally exercise actual download
responses larger than 4.5 MB and verify the resulting MP4, file-save and ZIP flows.

References: https://vercel.com/docs/functions/runtimes/python,
https://vercel.com/docs/functions/limitations,
https://vercel.com/kb/guide/how-to-bypass-vercel-body-size-limit-serverless-functions,
https://vercel.com/docs/plans/hobby.
