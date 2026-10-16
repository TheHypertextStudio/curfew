import assert from 'node:assert/strict';
import test from 'node:test';
const profiles = {
  production: { licenseOrigin: 'https://license.example.org' },
  staging: { licenseOrigin: 'https://license.staging.example.org' },
  local: { licenseOrigin: 'http://localhost:8788' },
};
async function profile(mode) {
  const { purchaseProfile } = await import('../../src/lib/purchase-profile.mjs');
  return purchaseProfile(mode, profiles);
}
test('purchase deployment pairs each configured issuer with the matching installed app', async () => {
  assert.deepEqual(await profile('production'), {
    issuer: 'https://license.example.org',
    scheme: 'curfew',
  });
  assert.deepEqual(await profile('staging'), {
    issuer: 'https://license.staging.example.org',
    scheme: 'curfew-studio-dev',
  });
  assert.deepEqual(await profile('local'), {
    issuer: 'http://localhost:8788',
    scheme: 'curfew-dev',
  });
});
test('purchase deployment refuses an unknown build environment', async () => {
  await assert.rejects(() => profile('preview'), /Unknown purchase deployment mode/);
});
