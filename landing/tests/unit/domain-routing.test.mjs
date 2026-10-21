import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const moduleURL = new URL('../../domain-routing.mjs', import.meta.url);
async function route(request) {
  await assert.doesNotReject(() => readFile(moduleURL));
  const { legacyDomainResponse } = await import(moduleURL.href);
  return legacyDomainResponse(request, {
    siteOrigin: 'https://example.net',
    legacySiteOrigin: 'https://old.example.net',
  });
}
test('old public pages retain encoded paths and queries in a permanent redirect', async () => {
  const response = await route(new Request('https://old.example.net/docs/a%20b?q=hello%20world'));
  assert.equal(response.status, 308);
  assert.equal(response.headers.get('location'), 'https://example.net/docs/a%20b?q=hello%20world');
});
test('old authenticated API and callback requests are retired without a Location', async () => {
  for (const request of [
    new Request('https://old.example.net/api/auth/get-session'),
    new Request('https://old.example.net/oauth/callback?code=secret'),
    new Request('https://old.example.net/account', { headers: { authorization: 'Bearer secret' } }),
    new Request('https://old.example.net/account', { method: 'POST' }),
  ]) {
    const response = await route(request);
    assert.equal(response.status, 410);
    assert.equal(response.headers.get('location'), null);
  }
});
test('the new site and unrelated preview hosts never redirect', async () => {
  assert.equal(await route(new Request('https://example.net/docs')), null);
  assert.equal(await route(new Request('https://preview.example.net/docs')), null);
});

test('recovery links and session cookies never cross domains in a redirect', async () => {
  for (const request of [
    new Request('https://old.example.net/account/recover?email_token=secret'),
    new Request('https://old.example.net/success.html?session_id=secret'),
    new Request('https://old.example.net/account', {
      headers: { cookie: '__Secure-curfew_account.session_token=secret' },
    }),
  ]) {
    const response = await route(request);
    assert.equal(response.status, 410);
    assert.equal(response.headers.get('location'), null);
  }
});

for (const mode of ['production', 'staging'])
  test(`the ${mode} marketing routes retire credentials while preserving public redirects`, async () => {
    const { default: worker } = await import('../../worker.mjs');
    const { default: deployment } = await import('../../../deployment/generated/environments.mjs');
    const old = deployment[mode].legacySiteOrigin;
    const env = {
      DOCS_MODE: 'mintlify',
      DOCS_UPSTREAM: 'https://curfew.mintlify.site',
      ASSETS: {
        fetch: () => {
          throw new Error('Legacy credentials must not reach assets');
        },
      },
    };
    const fetcher = async () => {
      throw new Error('Legacy credentials must not reach a docs upstream');
    };
    for (const request of [
      new Request(`${old}/success?session_id=existing`),
      new Request(`${old}/api/auth/callback?code=existing`),
      new Request(`${old}/docs?access_token=existing`),
      new Request(`${old}/account`, { headers: { authorization: 'Bearer existing' } }),
    ]) {
      const response = await worker.fetch(request, env, {}, fetcher);
      assert.equal(response.status, 410);
      assert.equal(response.headers.get('location'), null);
      assert.equal(response.headers.get('cache-control'), 'no-store');
    }
    const response = await worker.fetch(
      new Request(`${old}/download?from=guide`),
      env,
      {},
      fetcher,
    );
    assert.equal(response.status, 308);
    assert.equal(
      response.headers.get('location'),
      `${deployment[mode].siteOrigin}/download?from=guide`,
    );
  });
