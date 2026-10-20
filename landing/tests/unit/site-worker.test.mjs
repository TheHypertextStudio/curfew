import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { docsTarget } from '../../worker.mjs';
import deployment from '../../../deployment/generated/environments.mjs';

const env = {
  ASSETS: { fetch: async () => new Response('retained HTML guide', { status: 200 }) },
  DOCS_MODE: 'html-guide',
  DOCS_UPSTREAM: 'https://curfew.mintlify.site',
};

test('one staging host preserves account requests and response cookies without redirects', async () => {
  for (const path of [
    '/account',
    '/account/sign-in?return_section=security',
    '/account-assets/authenticator-qr.js',
    '/api/auth/callback/apple?code=fixture',
    '/api/account',
    '/design/components.css?rev=fixture',
    '/sync/status',
    '/.well-known/openid-configuration',
    '/mcp',
  ]) {
    let observed;
    const request = new Request(new URL(path, deployment.staging.siteOrigin), {
      method: 'POST',
      headers: {
        cookie: 'session=fixture',
        authorization: 'Bearer fixture',
        'content-type': 'application/json',
      },
      body: '{"fixture":true}',
    });
    const response = await worker.fetch(request, {
      ...env,
      ACCOUNT_PORTAL: deployment.staging.accountPortal,
      STAGING_ACCOUNT_SERVICE: {
        fetch: async (incoming) => {
          observed = incoming;
          return new Response('account result', {
            status: 401,
            headers: { 'set-cookie': 'session=renewed; Secure; HttpOnly; Path=/' },
          });
        },
      },
    });
    assert.equal(observed?.url, request.url, path);
    assert.equal(observed.method, 'POST');
    assert.equal(observed.headers.get('cookie'), 'session=fixture');
    assert.equal(observed.headers.get('authorization'), 'Bearer fixture');
    assert.equal(await observed.text(), '{"fixture":true}');
    assert.equal(response.status, 401);
    assert.equal(response.headers.get('set-cookie'), 'session=renewed; Secure; HttpOnly; Path=/');
    assert.equal(response.headers.get('location'), null);
  }
});

test('marketing assets have their own paths beside the account design assets', async () => {
  let asset;
  const response = await worker.fetch(
    new Request(
      new URL(
        '/site-assets/design/fonts/Calistoga-Regular.ttf?v=one',
        deployment.staging.siteOrigin,
      ),
    ),
    {
      ...env,
      STAGING_ACCOUNT_SERVICE: {
        fetch: () => assert.fail('website assets must not reach accounts'),
      },
      ASSETS: {
        fetch: async (request) => {
          asset = request;
          return new Response('font');
        },
      },
    },
  );
  assert.equal(new URL(asset.url).pathname, '/site-assets/design/fonts/Calistoga-Regular.ttf');
  assert.equal(new URL(asset.url).search, '?v=one');
  assert.equal(await response.text(), 'font');
});

test('consolidated staging remains unindexed on pages and backend errors', async () => {
  const configuration = {
    ...env,
    STAGING_ACCOUNT_SERVICE: { fetch: async () => new Response('sign in', { status: 401 }) },
  };
  for (const path of ['/', '/restore', '/api/account']) {
    const response = await worker.fetch(
      new Request(new URL(path, deployment.staging.siteOrigin)),
      configuration,
    );
    assert.equal(response.headers.get('x-robots-tag'), 'noindex, nofollow');
  }
});

test('staging delegation cannot forward production requests and fails closed on service errors', async () => {
  const service = {
    fetch: () => assert.fail('must not forward production account traffic to staging'),
  };
  const production = await worker.fetch(
    new Request(`${deployment.production.siteOrigin}/api/account`),
    { ...env, STAGING_ACCOUNT_SERVICE: service },
  );
  assert.equal(await production.text(), 'retained HTML guide');
  const failed = await worker.fetch(new Request(`${deployment.staging.siteOrigin}/api/account`), {
    ...env,
    STAGING_ACCOUNT_SERVICE: {
      fetch: async () => {
        throw new Error('offline');
      },
    },
  });
  assert.equal(failed.status, 503);
  assert.equal(failed.headers.get('cache-control'), 'no-store');
});

test('old staging purchase links redirect to the canonical host while authenticated writes stay retired', async () => {
  const configuration = {
    ...env,
    STAGING_ACCOUNT_SERVICE: { fetch: () => assert.fail('old host must not reach accounts') },
  };
  for (const path of ['/restore', '/success?session_id=cs_test_fixture', '/#plus']) {
    const response = await worker.fetch(
      new Request(`https://curfew-site-staging.hypertext.studio${path}`),
      configuration,
    );
    assert.equal(response.status, 302);
    const destination = new URL(response.headers.get('location'));
    assert.equal(destination.origin, deployment.staging.siteOrigin);
    assert.equal(
      destination.pathname,
      new URL(`https://curfew-site-staging.hypertext.studio${path}`).pathname,
    );
    assert.equal(response.headers.get('cache-control'), 'no-store');
  }
  for (const request of [
    new Request('https://curfew-site-staging.hypertext.studio/account?code=fixture'),
    new Request('https://curfew-site-staging.hypertext.studio/api/account', {
      method: 'POST',
      body: 'private',
    }),
    new Request('https://curfew-site-staging.hypertext.studio/restore', {
      headers: { authorization: 'Bearer fixture' },
    }),
  ]) {
    const response = await worker.fetch(request, configuration);
    assert.equal(response.status, 410);
    assert.equal(response.headers.get('location'), null);
  }
});

test('old staging double-slash paths cannot redirect to another host', async () => {
  const response = await worker.fetch(
    new Request(
      'https://curfew-site-staging.hypertext.studio//example.invalid/restore?from=fixture',
    ),
    { ...env, STAGING_ACCOUNT_SERVICE: { fetch: () => assert.fail('must not delegate') } },
  );
  const destination = new URL(response.headers.get('location'));
  assert.equal(destination.origin, deployment.staging.siteOrigin);
  assert.equal(destination.pathname, '//example.invalid/restore');
  assert.equal(destination.search, '?from=fixture');
});

test('account entry cannot redirect to itself if site and portal routes overlap', async () => {
  const portal = deployment.staging.accountPortal;
  const response = await worker.fetch(new Request(portal), {
    ...env,
    ACCOUNT_PORTAL: portal,
  });
  assert.equal(response.status, 503);
  assert.equal(response.headers.get('location'), null);
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('unconnected Mintlify retains the HTML guide and never calls an upstream', async () => {
  const response = await worker.fetch(new Request('https://preview.invalid/docs?query=one'), env);
  assert.equal(await response.text(), 'retained HTML guide');
  assert.equal(response.status, 200);
});

test('docs targets preserve path/query and only delegate the documented asset and search paths', () => {
  for (const path of [
    '/docs',
    '/docs/mcp?query=one%20two',
    '/_mintlify/app.js',
    '/mintlify-assets/font.woff2',
    '/api/request?query=two',
  ]) {
    const target = docsTarget(new URL(path, 'https://curfew.hypertext.studio'), {
      ...env,
      DOCS_MODE: 'mintlify',
    });
    assert.equal(target.origin, 'https://curfew.mintlify.site');
    assert.equal(
      target.pathname + target.search,
      path.startsWith('/api/request')
        ? path.replace('/api/request', '/_mintlify/api/request')
        : path.replace(/^\/docs\/mcp(?=\?)/, '/docs/mcp-guide'),
    );
  }
  for (const path of ['/docs-other', '/account', '/license', '/api/checkout', '/download']) {
    assert.equal(
      docsTarget(new URL(path, 'https://curfew.hypertext.studio'), {
        ...env,
        DOCS_MODE: 'mintlify',
      }),
      null,
    );
  }
});

test('proxy refuses recursive, credentialed, non-HTTPS, path-bearing and foreign origins', () => {
  for (const origin of [
    'https://curfew.hypertext.studio',
    'https://preview.invalid',
    'http://curfew.mintlify.site',
    'https://user:pass@' + 'curfew.mintlify.site',
    'https://curfew.mintlify.site/docs',
    'https://evil.invalid',
  ]) {
    assert.throws(() =>
      docsTarget(new URL('https://preview.invalid/docs'), {
        ...env,
        DOCS_MODE: 'mintlify',
        DOCS_UPSTREAM: origin,
      }),
    );
  }
});

test('proxy forwards the actual public origin, drops cookies/authorization and rewrites only upstream redirects', async () => {
  let observed;
  const fetcher = async (request) => {
    observed = request;
    return new Response(null, {
      status: 302,
      headers: {
        location: 'https://curfew.mintlify.site/docs/cli?view=all',
        'set-cookie': 'upstream=private',
      },
    });
  };
  const request = new Request('https://preview.invalid/docs?search=term', {
    headers: {
      cookie: 'session=private',
      authorization: 'Bearer private',
      'cf-access-jwt-assertion': 'test-private-jwt',
      'cf-access-authenticated-user-email': 'staff@example.invalid',
      'cf-access-client-id': 'test-client-id',
      'cf-access-client-secret': 'test-client-secret',
      'x-forwarded-host': 'spoof.invalid',
      'x-forwarded-proto': 'http',
    },
  });
  const response = await worker.fetch(request, { ...env, DOCS_MODE: 'mintlify' }, {}, fetcher);
  assert.equal(observed.url, 'https://curfew.mintlify.site/docs?search=term');
  assert.equal(observed.headers.get('x-forwarded-host'), 'preview.invalid');
  assert.equal(observed.headers.get('x-forwarded-proto'), 'https');
  assert.equal(observed.headers.get('cookie'), null);
  assert.equal(observed.headers.get('authorization'), null);
  for (const name of [
    'cf-access-jwt-assertion',
    'cf-access-authenticated-user-email',
    'cf-access-client-id',
    'cf-access-client-secret',
  ]) {
    assert.equal(observed.headers.get(name), null, `${name} must stay outside public docs`);
  }
  assert.equal(response.headers.get('location'), 'https://preview.invalid/docs/cli?view=all');
  assert.equal(response.headers.get('set-cookie'), null);
});

test('upstream errors remain errors and unsafe methods never reach docs', async () => {
  const response = await worker.fetch(
    new Request('https://preview.invalid/docs'),
    { ...env, DOCS_MODE: 'mintlify' },
    {},
    async () => new Response('Not found', { status: 404 }),
  );
  assert.equal(response.status, 404);
  const rejected = await worker.fetch(
    new Request('https://preview.invalid/docs', { method: 'POST', body: 'private' }),
    { ...env, DOCS_MODE: 'mintlify' },
    {},
    () => assert.fail('must not fetch'),
  );
  assert.equal(rejected.status, 405);
});

test('search forwards POST body without frontend identity and preserves external redirects', async () => {
  let observed;
  const response = await worker.fetch(
    new Request('https://preview.invalid/api/request?locale=en', {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        cookie: 'session=private',
        'cf-access-jwt-assertion': 'test-private-jwt',
      },
      body: '{"query":"CLI setup"}',
    }),
    { ...env, DOCS_MODE: 'mintlify' },
    {},
    async (request) => {
      observed = request;
      return new Response(null, {
        status: 302,
        headers: { location: 'https://hypertext.studio/contact' },
      });
    },
  );
  assert.equal(observed.url, 'https://curfew.mintlify.site/_mintlify/api/request?locale=en');
  assert.equal(observed.method, 'POST');
  assert.equal(await observed.text(), '{"query":"CLI setup"}');
  assert.equal(observed.headers.get('cookie'), null);
  assert.equal(observed.headers.get('cf-access-jwt-assertion'), null);
  assert.equal(response.headers.get('location'), 'https://hypertext.studio/contact');
});

test('an unavailable upstream reports 502 without converting to the HTML guide', async () => {
  const response = await worker.fetch(
    new Request('https://preview.invalid/docs'),
    { ...env, DOCS_MODE: 'mintlify' },
    {},
    async () => {
      throw new Error('network failure');
    },
  );
  assert.equal(response.status, 502);
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('purchase preview stays in the staging Worker without acquiring production domains', async () => {
  const configure = (await import('../../hosting/cloudflare.config.ts')).default;
  const staging = configure({ mode: 'staging' }).worker;
  const production = configure({ mode: 'production' }).worker;
  assert.equal(staging.name, 'curfew-site-staging');
  assert.equal(production.name, 'curfew-site-production');
  assert.equal(staging.domains, undefined);
  assert.equal(staging.workersDev, false);
  assert.equal(staging.previewUrls, false);
  assert.equal(production.domains, undefined);
  assert.equal(staging.env.STAGING_ACCOUNT_SERVICE?.worker, 'curfew-account-platform-staging');
  assert.deepEqual(staging.triggers, [
    { type: 'fetch', pattern: 'curfew-staging.hypertext.studio/*', zone: 'hypertext.studio' },
  ]);
  assert.equal(production.env.STAGING_ACCOUNT_SERVICE, undefined);
  assert.equal(production.triggers, undefined);
});
