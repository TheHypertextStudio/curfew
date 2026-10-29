import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
const command = new URL('./license-sql-format.mjs', import.meta.url).pathname;
test('SQLite migration formatting is stable and preserves executable constraints', () => {
  const first = spawnSync(process.execPath, [command], {
    encoding: 'utf8',
    input: 'create table t(x integer check(x>0));\n',
  });
  assert.equal(first.status, 0, first.stderr);
  assert.match(first.stdout, /CREATE TABLE/);
  const second = spawnSync(process.execPath, [command], { encoding: 'utf8', input: first.stdout });
  assert.equal(second.status, 0, second.stderr);
  assert.equal(second.stdout, first.stdout);
  const db = new DatabaseSync(':memory:');
  db.exec(first.stdout);
  db.exec('INSERT INTO t VALUES(1)');
  assert.throws(() => db.exec('INSERT INTO t VALUES(-1)'));
  const migration = readFileSync(
    new URL('../web/worker/migrations/0001_license_store.sql', import.meta.url),
    'utf8',
  );
  const formatted = spawnSync(process.execPath, [command], { encoding: 'utf8', input: migration });
  assert.equal(formatted.status, 0, formatted.stderr);
  db.exec(formatted.stdout);
  db.exec("INSERT INTO curfew_license_record(key,value) VALUES('order:test','paid')");
  assert.deepEqual(
    { ...db.prepare('SELECT key,value,expires_at FROM curfew_license_record').get() },
    { key: 'order:test', value: 'paid', expires_at: null },
  );
  db.close();
});
