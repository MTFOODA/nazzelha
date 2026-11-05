import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { downloadCounts, statistics } from './statistics.mjs';

function database(t) {
  const sql = new DatabaseSync(':memory:');
  sql.exec(readFileSync(new URL('./migrations/0001_statistics.sql', import.meta.url), 'utf8'));
  t.after(() => sql.close());
  const statement = (query, args = []) => ({
    bind: (...values) => statement(query, values),
    first: async () => sql.prepare(query).get(...args) ?? null,
    run: async () => sql.prepare(query).run(...args),
    execute: () => sql.prepare(query).run(...args),
  });
  return { prepare: statement, batch: async (list) => {
    sql.exec('BEGIN');
    try { const results = list.map(s => s.execute()); sql.exec('COMMIT'); return results; }
    catch (error) { sql.exec('ROLLBACK'); throw error; }
  }};
}
const origin = 'https://nazzelha.mohamed-fooda-mtf.workers.dev';
const url = new URL(origin + '/api/stats/visit');
const visit = id => new Request(url, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: origin }, body: JSON.stringify({ session: id.repeat(64) }) });

test('visits persist and replaying the same session never increases the total', async t => {
  const db = database(t);
  for (const id of ['a', 'a', 'b', 'a']) assert.equal((await statistics(visit(id), { STATS_DB: db }, url)).status, 200);
  assert.equal((await db.prepare('SELECT visits FROM statistics').first()).visits, 2);
  await db.prepare('UPDATE visit_sessions SET created_at = 0').run();
  await statistics(visit('c'), { STATS_DB: db }, url);
  assert.equal((await db.prepare('SELECT visits FROM statistics').first()).visits, 3);
});

test('GitHub counts combine stable releases and paginate, excluding debug files and click counts', async t => {
  const db = database(t); let calls = 0;
  const release = { assets: [{ name: 'Nazzelha-Android.apk', download_count: 4 }, { name: 'Nazzelha-Windows-x64.zip', download_count: 2 }, { name: 'Nazzelha-debug.apk', download_count: 99 }] };
  const fetcher = async url => {
    calls++;
    return Response.json(url.endsWith('page=1') ? [release, ...Array.from({ length: 99 }, () => ({ prerelease: true, ...release }))] : [release]);
  };
  const result = await downloadCounts(db, fetcher, 1000);
  assert.equal(result.android, 8); assert.equal(result.windows, 4); assert.equal(calls, 2);
  await downloadCounts(db, async () => { throw new Error('Must use persisted cache'); }, 1100);
  assert.equal((await downloadCounts(db, async () => { throw new Error('offline'); }, 3000)).stale, true);
});

test('upstream failure without a cached value remains unknown, not zero', async t => {
  assert.equal(await downloadCounts(database(t), async () => new Response('', { status: 429 })), null);
});

test('statistics allow the canonical Vercel website, reject foreign mutations and validate sessions', async t => {
  const db = database(t);
  const foreign = new Request(url, { method: 'POST', headers: { Origin: 'https://evil.test' } });
  assert.equal((await statistics(foreign, { STATS_DB: db }, url)).status, 403);
  assert.equal((await statistics(visit('x'), { STATS_DB: db }, url)).status, 400);
  const preflight = new Request(url, { method: 'OPTIONS', headers: { Origin: 'https://nazzelha-mtfooda.vercel.app' } });
  const response = await statistics(preflight, {}, url);
  assert.equal(response.status, 204);
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), 'https://nazzelha-mtfooda.vercel.app');
  assert.equal((await db.prepare('SELECT visits FROM statistics').first()).visits, 0);
});
