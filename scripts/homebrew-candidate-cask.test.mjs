import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, readFile, rm, stat, utimes, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath, pathToFileURL } from 'node:url';

const helper = fileURLToPath(new URL('./prepare-homebrew-candidate-cask.py', import.meta.url));
const checksum = 'b'.repeat(64);

async function fixture(t, version) {
  const dir = await mkdtemp(join(tmpdir(), 'curfew-cask-fixture-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const source = join(dir, 'public.rb');
  const staged = join(dir, 'candidate.rb');
  const image = join(dir, 'Curfew candidate.dmg');
  const original = [
    'cask "curfew" do',
    `  version "${version}"`,
    `  sha256 "${'a'.repeat(64)}"`,
    '  url "https://github.com/TheHypertextStudio/curfew/releases/download/v#{version}/Curfew-v#{version}.dmg"',
    '  binary "#{appdir}/Curfew.app/Contents/Resources/curfew-ctl"',
    'end',
    '',
  ].join('\n');
  await writeFile(source, original);
  return {
    source,
    staged,
    image,
    original,
    run(version) {
      return spawnSync('python3', [helper, source, staged, image, version, checksum], {
        encoding: 'utf8',
      });
    },
  };
}

test('the candidate cask can advance from a newer public predecessor and repeat', async (t) => {
  const files = await fixture(t, '0.0.99');
  const first = files.run('0.0.100');
  assert.equal(first.status, 0, first.stderr);
  assert.equal(first.stdout.trim(), '0.0.99');
  const candidate = await readFile(files.staged, 'utf8');
  assert.match(candidate, /version "0\.0\.100"/);
  assert.ok(candidate.includes(`sha256 "${checksum}"`));
  assert.ok(candidate.includes(`url "${pathToFileURL(files.image).href}"`));
  assert.ok(candidate.includes('/Contents/Resources/curfew-ctl'));
  await utimes(files.staged, 1000000000, 1000000000);
  const before = await stat(files.staged);
  assert.equal(files.run('0.0.100').status, 0);
  assert.equal((await stat(files.staged)).mtimeMs, before.mtimeMs);
  assert.equal(await readFile(files.staged, 'utf8'), candidate);
  assert.equal(await readFile(files.source, 'utf8'), files.original);
});

test('a candidate must be newer than the published cask before any output', async (t) => {
  const files = await fixture(t, '0.0.20');
  for (const version of ['0.0.19', '0.0.20']) {
    const result = files.run(version);
    assert.equal(result.status, 1);
    assert.match(result.stderr, /candidate must be newer/);
  }
  await assert.rejects(readFile(files.staged), { code: 'ENOENT' });
});
