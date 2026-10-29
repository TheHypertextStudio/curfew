import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { generateKeyPairSync, sign } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
const cli = new URL('./license-ledger-import.mjs', import.meta.url).pathname;

async function fixture(t, mode = 'staging', proofMode = mode) {
  const directory = await mkdtemp(join(tmpdir(), 'curfew-ledger-import-'));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const { privateKey, publicKey } = generateKeyPairSync('ed25519');
  const payload = Buffer.from(
    JSON.stringify({
      email: 'buyer@example.com',
      product: 'curfew-plus',
      plan: 'lifetime',
      order_id: 'cs_fixture',
      issued_at: '2026-10-01T00:00:00Z',
    }),
  );
  const key = `${payload.toString('base64url')}.${sign(null, payload, privateKey).toString('base64url')}`;
  const snapshot = {
    version: 1,
    mode,
    namespaceID: 'a'.repeat(32),
    records: [{ key: 'session:cs_fixture', value: key }],
  };
  const proof = {
    version: 1,
    mode: proofMode,
    orders: [{ sessionID: 'cs_fixture', plan: 'lifetime', paymentIntent: 'pi_fixture' }],
    invoices: [],
    refunds: [],
  };
  const paths = {
    snapshot: join(directory, 'snapshot.json'),
    proof: join(directory, 'proof.json'),
    output: join(directory, 'import.sql'),
  };
  await writeFile(paths.snapshot, JSON.stringify(snapshot));
  await writeFile(paths.proof, JSON.stringify(proof));
  const run = () =>
    spawnSync(
      process.execPath,
      [
        cli,
        'prepare',
        '--snapshot',
        paths.snapshot,
        '--provenance',
        paths.proof,
        '--mode',
        mode,
        '--namespace',
        'a'.repeat(32),
        '--public-key',
        publicKey.export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64'),
        '--output',
        paths.output,
      ],
      { encoding: 'utf8' },
    );
  return { run, paths, snapshot, proof, key };
}

test('prepares a private additive import while leaving readiness closed', async (t) => {
  const f = await fixture(t);
  const result = f.run();
  assert.equal(result.status, 0, result.stderr);
  const sql = await readFile(f.paths.output, 'utf8');
  assert.match(sql, /curfew_license_record/);
  const db = new DatabaseSync(':memory:');
  db.exec(sql);
  assert.equal(
    db.prepare("SELECT value FROM curfew_license_record WHERE key='session:cs_fixture'").get()
      .value,
    f.key,
  );
  assert.equal(db.prepare('SELECT ready FROM curfew_license_meta').get().ready, 0);
  const count = db.prepare('SELECT count(*) AS n FROM curfew_license_record').get().n;
  db.exec(sql);
  assert.equal(db.prepare('SELECT count(*) AS n FROM curfew_license_record').get().n, count);
  db.close();
  assert.doesNotMatch(sql, /SET ready\s*=\s*1/);
  assert.doesNotMatch(sql, /BEGIN TRANSACTION/);
  assert.match(sql, /ready=0/);
  assert.doesNotMatch(result.stdout + result.stderr, /buyer@example.com|pi_fixture|eyJ/);
  const { stat } = await import('node:fs/promises');
  assert.equal((await stat(f.paths.output)).mode & 0o777, 0o600);
});
test('refuses environment crossover and never writes an import for a tampered license', async (t) => {
  const f = await fixture(t, 'staging', 'production');
  assert.notEqual(f.run().status, 0);
  f.proof.mode = 'staging';
  const parts = f.key.split('.');
  const signature = Buffer.from(parts[1], 'base64url');
  signature[0] ^= 1;
  f.snapshot.records[0].value = parts[0] + '.' + signature.toString('base64url');
  await writeFile(f.paths.proof, JSON.stringify(f.proof));
  await writeFile(f.paths.snapshot, JSON.stringify(f.snapshot));
  assert.notEqual(f.run().status, 0);
});
test('does not claim unresolved historical keys are reconciled and refuses overwrites', async (t) => {
  const f = await fixture(t);
  f.proof.orders = [];
  await writeFile(f.paths.proof, JSON.stringify(f.proof));
  assert.equal(f.run().status, 2);
  const original = await readFile(f.paths.output, 'utf8');
  assert.notEqual(f.run().status, 0);
  assert.equal(await readFile(f.paths.output, 'utf8'), original);
});

test('an import cannot mix a different snapshot or overwrite an active ledger', async (t) => {
  const f = await fixture(t);
  assert.equal(f.run().status, 0);
  const first = await readFile(f.paths.output, 'utf8');
  const db = new DatabaseSync(':memory:');
  db.exec(first);
  const count = db.prepare('SELECT count(*) AS n FROM curfew_license_record').get().n;
  f.snapshot.records.push({ key: 'event:foreign', value: '1' });
  await writeFile(f.paths.snapshot, JSON.stringify(f.snapshot));
  f.paths.output += '.second';
  assert.equal(f.run().status, 0);
  const changed = await readFile(f.paths.output, 'utf8');
  db.exec(changed);
  assert.equal(db.prepare('SELECT count(*) AS n FROM curfew_license_record').get().n, count);
  db.exec('UPDATE curfew_license_meta SET ready=1');
  db.exec(changed);
  assert.equal(db.prepare('SELECT count(*) AS n FROM curfew_license_record').get().n, count);
  db.close();
});
