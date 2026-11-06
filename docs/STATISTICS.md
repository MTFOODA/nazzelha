# Public app statistics

The developer page shows website visits and separate Windows/Android file
download counts. Windows and Android use selection buttons; the Download action
opens the selected stable release asset. The separate unsigned iOS preview is
distributed through its prerelease and is excluded from these stable counters.

The canonical Cloudflare Worker serves `/api/stats` and `/api/stats/visit` using
the free-plan D1 binding `STATS_DB`. Its additive migration lives in
`cloudflare/migrations/0001_statistics.sql`. Apply with:

```
npx wrangler d1 migrations apply nazzelha-statistics --remote
```

Website visits start when this counter is enabled; earlier visits cannot be
reconstructed. The web app keeps a random visit identifier in browser local
storage for 30 minutes, shared across tabs. D1 counts an identifier once, even
after refresh, route changes or a retried request. New visits after that interval
receive a new identifier. Installed apps can read totals without adding visits.
No IP address, account, downloaded URL or fingerprint is stored. Temporary
deduplication identifiers are cleaned up after 48 hours; the total is retained.
This is a session counter, not an audited unique-person measurement; automated
clients or a browser that cannot keep storage may affect totals.

Download totals come from GitHub's `download_count` for the official APK and
Windows ZIP across stable public releases, including direct GitHub downloads.
They count asset downloads rather than button clicks or installations. Drafts,
prereleases, debug APKs and checksum files are excluded. Totals are cached in D1
for 15 minutes. On an upstream failure, the last available counts are marked
stale; unknown values display a dash instead of a fabricated zero.

The Vercel web alias uses this same statistics service with an explicit CORS
allowlist, so both public addresses share one counter. Statistics failures do not
block the app or its download engine. The existing media API proxy is unchanged.

Verification: SQLite-backed Worker tests cover duplicate visits, expiry cleanup,
release pagination, cache reuse, upstream failures and allowed origins. Flutter
tests cover both platform selections, translations/themes and unavailable counts.
The live API was checked with a repeated visit identifier and a native Dart
client; the repeated identifier increased the total only once.
