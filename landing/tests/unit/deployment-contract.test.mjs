import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
const landing = new URL('../../', import.meta.url);
const read = (name) => readFileSync(new URL(name, landing), 'utf8');
test('marketing declaration selects prebuilt Workers bytes and the exact native tool', () => {
  const declaration = read('studio.yaml');
  for (const expected of [
    "wrangler: '4.148.0'",
    'provider: workers',
    'config: wrangler.site.json',
    'entrypoint: modules/worker.js',
    'assets: assets',
    'staging: https://curfew-site-staging.hypertext.studio/__studio/release',
    'production: https://curfew.hypertext.studio/__studio/release',
  ])
    assert.ok(declaration.includes(expected), `missing ${expected}`);
});
test('marketing environments remain isolated and cannot route to the backend preview', () => {
  const config = JSON.parse(read('wrangler.site.json'));
  assert.equal(config.account_id, '2500680a3b2b0fe6a011c1c25fed5008');
  assert.equal(config.env.staging.name, 'curfew-site-staging');
  assert.equal(config.env.production.name, 'curfew-site-production');
  for (const scope of Object.values(config.env)) {
    assert.deepEqual(scope.routes, []);
    assert.equal(scope.workers_dev, false);
    assert.equal(scope.preview_urls, false);
    assert.equal(scope.vars.DOCS_MODE, 'html-guide');
  }
});
test('frontend runtime uses published v0.1.8 and intended initial package version', () => {
  const lock = JSON.parse(read('studio.lock.json'));
  assert.equal(lock.version, 'v0.1.8');
  assert.equal(lock.revision, '878260def7229cd3df7f752b32e5581230c5db2d');
  assert.equal(lock.sha256, '61f746429fc0ffc7826df2bde61ee4d41323fb5fa0c9f8661255040e7838afd4');
  const dependencies = JSON.parse(read('package.json')).devDependencies;
  for (const name of ['web-config', 'web-docs', 'web-tokens']) {
    assert.equal(dependencies[`@thehypertextstudio/${name}`], '0.0.1');
  }
});
