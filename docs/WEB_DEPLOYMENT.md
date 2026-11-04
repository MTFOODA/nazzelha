# Public web deployment

The intended public URL is `https://nazzelha.mohamed-fooda-mtf.workers.dev/`.
This is the `nazzelha` Worker only; the separate `azkar-sadaqa` project is untouched.

Cloudflare serves the Flutter web assets and streams `/api/*` to the Render
Docker service. The Worker does not run Python or FFmpeg. `API_ORIGIN` is a
Worker secret containing the Render service's HTTPS origin. It is not a user
credential. Secrets persist across GitHub-triggered deployments.

`npx wrangler deploy` runs `tool/build_web.mjs`, which uses Flutter 3.47.7 and
builds the public configuration. Local releases can set `FLUTTER_BIN` to an
installed SDK, or `NAZZELHA_SKIP_WEB_BUILD=1` after building the matching web assets.
The repository's existing Cloudflare GitHub connection can use its original
deploy command, `npx wrangler deploy`.

Deploy the Dockerfile as one Render **free** web service, with health path
`/health`. Do not create a database, persistent disk, paid instance, or paid
Cloudflare Container. The checked-in `render.yaml` describes the service; if
Blueprints require payment information, use `render services create --plan free`
instead. Account verification requirements can still be imposed by the provider.

Set `NAZZELHA_SITE_ORIGIN` to the exact public site origin. Set
`NAZZELHA_SESSION_SECRET` to a random private value through Render's environment
configuration. Never commit this value or a platform login/cookie file.

## Visitor downloads

- Each anonymous visitor gets a signed HttpOnly session cookie. Jobs, cancellation,
  temporary files and ZIP creation are scoped to that visitor.
- The web API exposes extraction, preparation, cancellation, file saving and ZIP
  creation. It exposes no platform-session import, host paths, Explorer opening,
  arbitrary output path or folder repair commands.
- Ready files are temporary for one hour and disappear on server restart. A
  visitor must click Save to your device or Save playlist ZIP. The browser
  chooses the destination. ZIPs contain the chosen Unicode folder name.
- A stale individual file link unlocks retry for that video. Local completed
  downloads remain completed. Browser history stays in local browser storage.
- The web tab must stay open to advance a playlist. Android's installed app uses
  its native foreground service for background playlist downloads.
- The free web edition caps each media file at 256 MiB, temporary cache at 1 GiB,
  ZIPs at 200 entries, download work at one job at a time and queued visitors at
  eight. Use the installed app for large videos and playlists.

## Free hosting limits

Render's free service sleeps after 15 minutes without traffic. The first request
can take about a minute. The web client retries health checks while starting an
operation. Free compute hours, bandwidth and build minutes are limited. With no
payment method, quota exhaustion suspends service rather than adding charges.
No keep-alive bot or quota circumvention is configured. A free service is not an
unlimited or guaranteed-availability replacement for direct app downloads.

Upstream platforms can reject data-center IPs, require an account, or restrict a
particular video. A public URL alone does not remove those restrictions.

References: https://render.com/docs/free,
https://render.com/docs/cli,
https://developers.cloudflare.com/workers/static-assets/.

## Local checks

```
python -m pip install -r python_backend/requirements-test.txt
python -m unittest discover -s python_backend -p "test_*.py"
node --test cloudflare/worker.test.mjs
docker build -t nazzelha-api:1.1.0 .
docker run --rm -p 127.0.0.1:8001:8000 --memory=512m --cpus=0.1 nazzelha-api:1.1.0
```

Never bind `web_bridge.py` or its compatibility `server.py` to a public interface.
