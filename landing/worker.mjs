import deployment from '../deployment/generated/environments.mjs';
import { legacyDomainResponse } from './domain-routing.mjs';

function stagingAccountPath(path) {
  return (
    ['/health', '/mcp'].includes(path) ||
    [
      '/account',
      '/account-assets',
      '/api/auth',
      '/api/account',
      '/sync',
      '/oauth',
      '/.well-known',
      '/mcp-app',
      '/design',
    ].some((prefix) => path === prefix || path.startsWith(`${prefix}/`))
  );
}

function retiredStagingResponse(request) {
  const url = new URL(request.url);
  if (url.origin !== 'https://curfew-site-staging.hypertext.studio') return null;
  const sensitive =
    stagingAccountPath(url.pathname) ||
    request.headers.has('authorization') ||
    ['code', 'state', 'token', 'email_token', 'access_token', 'refresh_token', 'id_token'].some(
      (key) => url.searchParams.has(key),
    ) ||
    (url.searchParams.has('session_id') && !['/success', '/success.html'].includes(url.pathname));
  if (sensitive || !['GET', 'HEAD'].includes(request.method)) {
    return new Response('Open the staging account portal to continue.', {
      status: 410,
      headers: { 'cache-control': 'no-store' },
    });
  }
  const destination = new URL(deployment.staging.siteOrigin);
  destination.pathname = url.pathname;
  destination.search = url.search;
  return new Response(null, {
    status: 302,
    headers: {
      location: destination.href,
      'cache-control': 'no-store',
    },
  });
}
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

const site = {
  async fetch(request, env, _context, fetcher = fetch) {
    const legacy = legacyDomainResponse(request, deployment.production);
    if (legacy) return legacy;
    const url = new URL(request.url);
    if (env.STAGING_ACCOUNT_SERVICE) {
      const retired = retiredStagingResponse(request);
      if (retired) return retired;
      if (url.origin === deployment.staging.siteOrigin && stagingAccountPath(url.pathname)) {
        try {
          return await env.STAGING_ACCOUNT_SERVICE.fetch(request);
        } catch {
          return new Response('Account services are temporarily unavailable.', {
            status: 503,
            headers: { 'cache-control': 'no-store' },
          });
        }
      }
    }
    // The marketing Worker owns navigation, not the account application.
    // Hand off only a plain account-entry navigation, never a request body,
    // Authorization header or query that could contain an auth callback.
    if (
      env.ACCOUNT_PORTAL &&
      ['/account', '/account/'].includes(url.pathname) &&
      ['GET', 'HEAD'].includes(request.method) &&
      !url.search &&
      !request.headers.has('authorization')
    ) {
      const allowed = [deployment.staging.accountPortal, deployment.production.accountPortal];
      if (!allowed.includes(env.ACCOUNT_PORTAL)) {
        return new Response('Account portal is not configured safely', {
          status: 503,
          headers: { 'cache-control': 'no-store' },
        });
      }
      if (new URL(env.ACCOUNT_PORTAL).origin === url.origin) {
        return new Response('Account sign-in is temporarily unavailable', {
          status: 503,
          headers: { 'cache-control': 'no-store' },
        });
      }
      return new Response(null, {
        status: 302,
        headers: { location: env.ACCOUNT_PORTAL, 'cache-control': 'no-store' },
      });
    }
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
    for (const name of [...headers.keys()]) {
      if (name.startsWith('cf-access-')) headers.delete(name);
    }
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

export default {
  async fetch(request, env, context, fetcher = fetch) {
    const response = await site.fetch(request, env, context, fetcher);
    if (!env.STAGING_ACCOUNT_SERVICE || response.status === 101) return response;
    const privateResponse = new Response(response.body, response);
    privateResponse.headers.set('x-robots-tag', 'noindex, nofollow');
    return privateResponse;
  },
};
