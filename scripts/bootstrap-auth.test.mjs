import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmodSync, copyFileSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

function fixture(t) {
  const root = mkdtempSync(path.join(tmpdir(), 'curfew bootstrap auth '));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  mkdirSync(path.join(root, 'scripts'));
  copyFileSync(new URL('../bootstrap', import.meta.url), path.join(root, 'bootstrap'));
  chmodSync(path.join(root, 'bootstrap'), 0o755);
  const engine = path.join(root, 'scripts/bootstrap-worktree-engine');
  writeFileSync(
    engine,
    '#!/bin/sh\nprintf "%s\\n" "$PWD" "$@"\nexit "${BOOTSTRAP_TEST_EXIT:-0}"\n',
  );
  chmodSync(engine, 0o755);
  return root;
}

test('package setup anchors the checkout and forwards arguments without interpreting them', (t) => {
  const root = fixture(t);
  const args = ['packages', 'setup', 'space and $special'];
  const result = spawnSync(path.join(root, 'bootstrap'), args, { cwd: tmpdir(), encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  assert.deepEqual(result.stdout.trim().split('\n'), [root, ...args]);
});

test('package check preserves the engine failure for the caller', (t) => {
  const root = fixture(t);
  const args = ['packages', 'check', '@thehypertextstudio/web-tokens'];
  const result = spawnSync(path.join(root, 'bootstrap'), args, {
    cwd: tmpdir(),
    encoding: 'utf8',
    env: { ...process.env, BOOTSTRAP_TEST_EXIT: '7' },
  });
  assert.equal(result.status, 7, result.stderr);
  assert.deepEqual(result.stdout.trim().split('\n'), [root, ...args]);
});
