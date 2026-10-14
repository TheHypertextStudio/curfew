/** Retire authenticated traffic; only public navigations may cross domains. */
export function legacyDomainResponse(request, config) {
  const url = new URL(request.url);
  if (!config.legacySiteOrigin || url.origin !== config.legacySiteOrigin) return null;
  const sensitive =
    url.pathname.startsWith('/account/') ||
    [
      'code',
      'state',
      'email_token',
      'access_token',
      'refresh_token',
      'id_token',
      'token',
      'session_id',
    ].some((key) => url.searchParams.has(key)) ||
    /(?:^|;\s*)(?:__Secure-)?curfew_(?:account|email)[^=]*=/i.test(
      request.headers.get('cookie') || '',
    ) ||
    url.pathname === '/api' ||
    url.pathname.startsWith('/api/') ||
    url.pathname.startsWith('/oauth/') ||
    url.pathname.startsWith('/.well-known/') ||
    url.pathname === '/mcp' ||
    url.pathname.startsWith('/sync/');
  if (
    sensitive ||
    request.headers.has('authorization') ||
    !['GET', 'HEAD'].includes(request.method)
  ) {
    return new Response('Curfew has moved. Sign in again at the new account portal.', {
      status: 410,
      headers: { 'cache-control': 'no-store' },
    });
  }
  const destination = new URL(config.siteOrigin);
  destination.pathname = url.pathname;
  destination.search = url.search;
  return new Response(null, { status: 308, headers: { location: destination.href } });
}
