import { statistics } from './statistics.mjs';
const allowed = /^(?:health|command|download|cancel|archive|files\/[a-f0-9]{48})$/;

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/api/stats' || url.pathname === '/api/stats/visit') return statistics(request, env, url);
    if (!url.pathname.startsWith('/api/')) return env.ASSETS.fetch(request);
    const path = url.pathname.slice(5);
    if (!allowed.test(path)) return new Response('Not found', { status: 404 });
    if (!env.API_ORIGIN) return Response.json({ error: 'The download service is being configured. Please try again later.' }, { status: 503 });
    const origin = request.headers.get('origin');
    if (origin && origin !== url.origin) return new Response('Forbidden', { status: 403 });
    if (!['GET', 'HEAD', 'POST'].includes(request.method)) return new Response('Method not allowed', { status: 405 });
    const target = new URL(env.API_ORIGIN);
    if (target.protocol !== 'https:' || target.username || target.password ||
        !['.onrender.com', '.code.run', '.vercel.app'].some(suffix => target.hostname.endsWith(suffix))) {
      return Response.json({ error: 'The download service is unavailable.' }, { status: 503 });
    }
    target.pathname = (target.hostname.endsWith('.vercel.app') ? '/api/' : '/') + path;
    target.search = '';
    const headers = new Headers();
    for (const name of ['content-type', 'cookie', 'range', 'if-range']) {
      if (request.headers.has(name)) headers.set(name, request.headers.get(name));
    }
    headers.set('origin', url.origin);
    try {
      const upstream = await fetch(target, {
        method: request.method, headers,
        body: request.method === 'POST' ? request.body : undefined,
        redirect: 'manual',
      });
      const response = new Response(upstream.body, upstream);
      response.headers.set('Cache-Control', 'private, no-store');
      response.headers.set('X-Content-Type-Options', 'nosniff');
      response.headers.delete('access-control-allow-origin');
      return response;
    } catch (_) {
      return Response.json({ error: 'The free download service is waking up. Please try again shortly.' }, { status: 503 });
    }
  },
};
