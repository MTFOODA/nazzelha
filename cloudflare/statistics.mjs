const sites = new Set([
  'https://nazzelha.mohamed-fooda-mtf.workers.dev',
  'https://nazzelha-mtfooda.vercel.app',
]);
const ttl = 15 * 60;

export async function downloadCounts(db, fetcher = fetch, now = Math.floor(Date.now() / 1000)) {
  const cached = await db.prepare('SELECT windows, android, updated_at FROM download_cache WHERE id = 1').first();
  if (cached && now - cached.updated_at < ttl) return { ...cached, stale: false };
  try {
    const counts = { windows: 0, android: 0 };
    for (let page = 1; ; page++) {
      const response = await fetcher(`https://api.github.com/repos/MTFOODA/nazzelha/releases?per_page=100&page=${page}`, {
        headers: { 'User-Agent': 'Nazzelha-Statistics', Accept: 'application/vnd.github+json' },
        signal: AbortSignal.timeout(8000),
      });
      if (!response.ok) throw new Error('GitHub statistics unavailable');
      const releases = await response.json();
      if (!Array.isArray(releases)) throw new Error('Invalid release data');
      for (const release of releases) {
        if (release.draft || release.prerelease) continue;
        for (const asset of release.assets ?? []) {
          const platform = asset.name === 'Nazzelha-Windows-x64.zip' ? 'windows'
            : asset.name === 'Nazzelha-Android.apk' ? 'android' : null;
          if (platform && Number.isSafeInteger(asset.download_count) && asset.download_count >= 0) counts[platform] += asset.download_count;
        }
      }
      if (releases.length < 100) break;
      if (page >= 20) throw new Error('Release pagination limit');
    }
    await db.prepare('INSERT INTO download_cache (id, windows, android, updated_at) VALUES (1, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET windows=excluded.windows, android=excluded.android, updated_at=excluded.updated_at')
      .bind(counts.windows, counts.android, now).run();
    return { ...counts, updated_at: now, stale: false };
  } catch (_) {
    return cached ? { ...cached, stale: true } : null;
  }
}

export async function statistics(request, env, url) {
  const origin = request.headers.get('origin');
  const headers = { 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', Vary: 'Origin' };
  if (origin && !sites.has(origin) && origin !== url.origin) return new Response('Forbidden', { status: 403 });
  if (origin) headers['Access-Control-Allow-Origin'] = origin;
  if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: { ...headers,
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS', 'Access-Control-Allow-Headers': 'Content-Type' } });
  const visit = url.pathname === '/api/stats/visit';
  if ((visit && request.method !== 'POST') || (!visit && request.method !== 'GET')) return new Response('Method not allowed', { status: 405, headers });
  if (!env.STATS_DB) return Response.json({ error: 'Statistics unavailable' }, { status: 503, headers });
  try {
    if (visit) {
      if (request.headers.get('content-type')?.split(';')[0] !== 'application/json') return new Response('JSON required', { status: 415, headers });
      const body = await request.text();
      if (body.length > 256) return new Response('Too large', { status: 413, headers });
      let data;
      try { data = JSON.parse(body); } catch (_) { return new Response('Invalid JSON', { status: 400, headers }); }
      if (!/^[a-f0-9]{64}$/.test(data?.session ?? '')) return new Response('Invalid session', { status: 400, headers });
      const now = Math.floor(Date.now() / 1000);
      // Random session identifiers only; no IPs, URLs, accounts or fingerprints.
      // The trigger increments the total only for a newly inserted session.
      await env.STATS_DB.batch([
        env.STATS_DB.prepare('INSERT OR IGNORE INTO visit_sessions (id, created_at) VALUES (?, ?)').bind(data.session, now),
        env.STATS_DB.prepare('DELETE FROM visit_sessions WHERE id IN (SELECT id FROM visit_sessions WHERE created_at < ? LIMIT 100)').bind(now - 172800),
      ]);
      return Response.json({ recorded: true }, { headers });
    }
    const totals = await env.STATS_DB.prepare('SELECT visits, started_at FROM statistics WHERE id = 1').first();
    return Response.json({ ...totals, downloads: await downloadCounts(env.STATS_DB) }, { headers });
  } catch (_) {
    return Response.json({ error: 'Statistics temporarily unavailable' }, { status: 503, headers });
  }
}
