import assert from 'node:assert/strict';
import test from 'node:test';
import worker, { docsTarget } from '../../worker.mjs';

const env = {
  ASSETS: { fetch: async () => new Response('retained HTML guide', { status: 200 }) },
  DOCS_MODE: 'html-guide',
  DOCS_UPSTREAM: 'https://curfew.mintlify.site',
};

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

test('release metadata is complete, noncacheable, and unavailable when not configured', async () => {
  const request = new Request('https://preview.invalid/__studio/release');
  assert.equal((await worker.fetch(request, env)).status, 503);
  const response = await worker.fetch(request, {
    ...env,
    STUDIO_SOURCE_SHA: 'source',
    STUDIO_ARTIFACT_SHA256: 'artifact',
    STUDIO_CANDIDATE_ID: 'candidate',
  });
  assert.deepEqual(await response.json(), {
    sourceSha: 'source',
    artifactSha256: 'artifact',
    candidateId: 'candidate',
  });
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('search forwards POST body without frontend identity and preserves external redirects', async () => {
  let observed;
  const response = await worker.fetch(
    new Request('https://preview.invalid/api/request?locale=en', {
      method: 'POST',
      headers: { 'content-type': 'application/json', cookie: 'session=private' },
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
