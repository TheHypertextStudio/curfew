import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, mkdtemp, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import licenseConfig from '../cloudflare.config.ts';
import { createArtifact } from '../../../scripts/deployment-config.mjs';

test('transactional issuer binds only an explicit retained D1 database and schedules outbox retry', async (t) => {
  const keys = [
    'CURFEW_DEPLOYMENT_ARTIFACT',
    'CURFEW_CONFIGURATION_COMMIT',
    'CURFEW_CONFIGURATION_SHA256',
    'CURFEW_LICENSE_PRODUCTION_DATABASE_ID',
    'CURFEW_LICENSE_STAGING_DATABASE_ID',
    'CURFEW_LICENSE_KV_NAMESPACE_ID',
    'CURFEW_LICENSE_WORKER_NAME',
  ];
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  const directory = await mkdtemp(join(tmpdir(), 'curfew-ledger-config-'));
  t.after(async () => {
    for (const key of keys)
      saved[key] === undefined ? delete process.env[key] : (process.env[key] = saved[key]);
    await rm(directory, { recursive: true, force: true });
  });
  const manifest = JSON.parse(
    await readFile(new URL('../../../deployment/environments.json', import.meta.url), 'utf8'),
  );
  const artifact = createArtifact(manifest, 'a'.repeat(40));
  const file = join(directory, 'artifact.json');
  await writeFile(file, JSON.stringify(artifact));
  Object.assign(process.env, {
    CURFEW_DEPLOYMENT_ARTIFACT: file,
    CURFEW_CONFIGURATION_COMMIT: artifact.sourceCommit,
    CURFEW_CONFIGURATION_SHA256: artifact.sha256,
    CURFEW_LICENSE_PRODUCTION_DATABASE_ID: '11111111-1111-4111-8111-111111111111',
    CURFEW_LICENSE_STAGING_DATABASE_ID: '22222222-2222-4222-8222-222222222222',
    CURFEW_LICENSE_KV_NAMESPACE_ID: 'a'.repeat(32),
    CURFEW_LICENSE_WORKER_NAME: 'curfew-issue-license-staging',
  });
  const production = await licenseConfig({ mode: 'production' });
  const staging = await licenseConfig({ mode: 'staging' });
  assert.equal(production.worker.env.LICENSE_DB.type, 'd1');
  assert.equal(
    production.worker.env.LICENSE_DB.id,
    process.env.CURFEW_LICENSE_PRODUCTION_DATABASE_ID,
  );
  assert.equal(staging.worker.env.LICENSE_DB.id, process.env.CURFEW_LICENSE_STAGING_DATABASE_ID);
  assert.ok(
    production.worker.triggers.some(
      (trigger) => trigger.type === 'scheduled' && trigger.schedule === '*/5 * * * *',
    ),
  );
  process.env.CURFEW_LICENSE_STAGING_DATABASE_ID =
    process.env.CURFEW_LICENSE_PRODUCTION_DATABASE_ID;
  await assert.rejects(() => licenseConfig({ mode: 'staging' }), /Staging.*production/);
  delete process.env.CURFEW_LICENSE_PRODUCTION_DATABASE_ID;
  const unconfigured = await licenseConfig({ mode: 'production' });
  assert.equal(unconfigured.worker.env.LICENSE_DB, undefined);
});
