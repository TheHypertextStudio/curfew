import deployment from '../deployment/generated/environments.mjs';
import { legacyDomainResponse } from './domain-routing.mjs';
/** The site delegates public docs only after the existing Mintlify project is connected and accepted. */
export function docsTarget(url, env) {
  if (env.DOCS_MODE !== 'mintlify') return null;
  const isDocs = url.pathname === '/docs' || url.pathname.startsWith('/docs/');
  const isAsset =
    url.pathname.startsWith('/_mintlify/') || url.pathname.startsWith('/mintlify-assets/');
  const isSearch = url.pathname === '/api/request';
  if (!isDocs && !isAsset && !isSearch) return null;
  const upstream = new URL(env.DOCS_UPSTREAM);
  if (
    upstream.origin !== 'https://curfew.mintlify.site' ||
    upstream.origin === url.origin ||
    upstream.username ||
    upstream.password ||
    upstream.pathname !== '/' ||
    upstream.search ||
    upstream.hash
  ) {
    throw new Error('Curfew docs require the verified explicit Mintlify origin');
  }
  upstream.pathname = isSearch ? '/_mintlify/api/request' : url.pathname;
  // Mintlify reserves /mcp; retain the existing public guide URL with an exact alias.
  if (upstream.pathname === '/docs/mcp') upstream.pathname = '/docs/mcp-guide';
  upstream.search = url.search;
  return upstream;
}

export default {
  async fetch(request, env, _context, fetcher = fetch) {
    const legacy = legacyDomainResponse(request, deployment.production);
    if (legacy) return legacy;
    const url = new URL(request.url);
    let target;
    try {
      target = docsTarget(url, env);
    } catch {
      return new Response('Documentation upstream is not configured safely', {
        status: 503,
        headers: { 'cache-control': 'no-store' },
      });
    }
    if (!target) return env.ASSETS.fetch(request);
    const isSearch = url.pathname === '/api/request';
    if (!['GET', 'HEAD'].includes(request.method) && !(isSearch && request.method === 'POST')) {
      return new Response('Method not allowed', {
        status: 405,
        headers: { allow: isSearch ? 'GET, HEAD, POST' : 'GET, HEAD', 'cache-control': 'no-store' },
      });
    }
    const headers = new Headers(request.headers);
    for (const name of ['authorization', 'cookie', 'host', 'x-forwarded-for', 'cf-connecting-ip'])
      headers.delete(name);
    headers.set('x-forwarded-host', url.host);
    headers.set('x-forwarded-proto', url.protocol.slice(0, -1));
    const outbound = new Request(target, {
      method: request.method,
      headers,
      body: request.method === 'POST' ? request.body : undefined,
      redirect: 'manual',
      ...(request.method === 'POST' ? { duplex: 'half' } : {}),
    });
    let response;
    try {
      response = await fetcher(outbound);
    } catch {
      return new Response('Documentation upstream is unavailable', {
        status: 502,
        headers: { 'cache-control': 'no-store' },
      });
    }
    const outgoing = new Headers(response.headers);
    outgoing.delete('set-cookie');
    const location = outgoing.get('location');
    if (location) {
      const destination = new URL(location, target);
      if (destination.origin === target.origin) {
        destination.protocol = url.protocol;
        destination.host = url.host;
        outgoing.set('location', destination.href);
      }
    }
    return new Response(response.body, {
      status: response.status,
      statusText: response.statusText,
      headers: outgoing,
    });
  },
};
