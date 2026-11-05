import test from 'node:test';
import assert from 'node:assert/strict';
import worker from './worker.mjs';

test('static app and unknown API paths', async () => {
  const env = { ASSETS: { fetch: () => new Response('app') } };
  assert.equal(await (await worker.fetch(new Request('https://nazzelha.test/'), env)).text(), 'app');
  assert.equal((await worker.fetch(new Request('https://nazzelha.test/api/configure_auth'), env)).status, 404);
  assert.equal((await worker.fetch(new Request('https://nazzelha.test/api/health'), env)).status, 503);
});

test('proxy preserves cookie, Unicode attachment, range and streaming response', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    assert.equal(url.href, 'https://nazzelha-api.onrender.com/files/' + 'a'.repeat(48));
    assert.equal(options.headers.get('cookie'), 'nazzelha_session=owner');
    assert.equal(options.headers.get('range'), 'bytes=0-3');
    assert.equal(options.headers.get('origin'), 'https://nazzelha.test');
    assert.equal(options.headers.get('authorization'), null);
    return new Response('part', { status: 206, headers: { 'content-disposition': 'attachment; filename="video.mp4"', 'set-cookie': 'nazzelha_session=owner; Secure; HttpOnly; Path=/' } });
  };
  try {
    const result = await worker.fetch(new Request('https://nazzelha.test/api/files/' + 'a'.repeat(48),
      { headers: { cookie: 'nazzelha_session=owner', range: 'bytes=0-3', authorization: 'not forwarded' } }), { API_ORIGIN: 'https://nazzelha-api.onrender.com' });
    assert.equal(result.status, 206);
    assert.equal(result.headers.get('cache-control'), 'private, no-store');
    assert.ok(result.headers.has('set-cookie'));
    assert.equal(await result.text(), 'part');
  } finally { globalThis.fetch = original; }
});

test('reject cross-origin mutations and arbitrary upstreams', async () => {
  assert.equal((await worker.fetch(new Request('https://nazzelha.test/api/cancel', { method: 'POST', headers: { origin: 'https://evil.test' } }), { API_ORIGIN: 'https://nazzelha-api.onrender.com' })).status, 403);
  assert.equal((await worker.fetch(new Request('https://nazzelha.test/api/health'), { API_ORIGIN: 'http://127.0.0.1' })).status, 503);
});

test('Vercel proxy reaches the Python API rather than the SPA', async () => {
  const original = globalThis.fetch;
  globalThis.fetch = async (url) => {
    assert.equal(url.href, 'https://nazzelha-mtfooda.vercel.app/api/health');
    return Response.json({ ready: true, transfer: 'browser' });
  };
  try {
    const result = await worker.fetch(new Request('https://nazzelha.test/api/health'),
      { API_ORIGIN: 'https://nazzelha-mtfooda.vercel.app' });
    assert.equal((await result.json()).transfer, 'browser');
  } finally { globalThis.fetch = original; }
});
