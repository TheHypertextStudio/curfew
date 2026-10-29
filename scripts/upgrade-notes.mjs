import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFile, writeFile, lstat, realpath } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { validateUpgradeVersion } from './signed-installer-acceptance.mjs';

const git = (root, ...args) =>
  execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trim();
async function regularPath(root, parts) {
  assert.equal(await realpath(root), resolve(root), 'Checkout root must not be a symlink');
  for (let index = 0; index < parts.length; index++) {
    const entry = await lstat(join(root, ...parts.slice(0, index + 1)));
    assert.ok(
      index === parts.length - 1 ? entry.isFile() : entry.isDirectory(),
      'Regular release-note path required',
    );
  }
}

// This supplies response data only. All verifier/feed-driver commands still run
// from the exact producer checkout against the original signed candidate bytes.
export async function stageUpgradeNotes({ harnessRoot, producerRoot, upgradeRoot }) {
  const plan = JSON.parse(await readFile(join(upgradeRoot, 'upgrade-plan.json'), 'utf8'));
  const subject = JSON.parse(
    await readFile(join(upgradeRoot, 'candidate/acceptance-subject.json'), 'utf8'),
  );
  assert.equal(plan.scope, 'disposable-sparkle-upgrade');
  const version = validateUpgradeVersion(plan.candidate.version);
  for (const key of ['version', 'sourceCommit', 'runID', 'dmgSHA256'])
    assert.equal(plan.candidate[key], subject[key], `Prepared subject mismatch: ${key}`);
  assert.match(subject.sourceCommit, /^[a-f0-9]{40}$/);
  const producerSourceCommit = git(producerRoot, 'rev-parse', 'HEAD');
  assert.equal(producerSourceCommit, subject.sourceCommit);
  assert.equal(
    git(producerRoot, 'status', '--porcelain', '--untracked-files=all'),
    '',
    'Producer must be completely clean before supplying notes',
  );
  const parts = ['landing', 'releases', `${version}.html`],
    path = parts.join('/');
  const tracked = git(producerRoot, 'ls-files', '--', path) === path;
  // Both parent directories must already belong to the producer checkout.
  assert.equal(await realpath(producerRoot), resolve(producerRoot));
  for (const parent of ['landing', 'landing/releases'])
    assert.ok(
      (await lstat(join(producerRoot, parent))).isDirectory(),
      'No symlinked producer directories',
    );
  let notes, notesSourceCommit;
  if (tracked) {
    await regularPath(producerRoot, parts);
    notes = await readFile(join(producerRoot, path));
    assert.deepEqual(notes, execFileSync('git', ['-C', producerRoot, 'show', `HEAD:${path}`]));
    notesSourceCommit = producerSourceCommit;
  } else {
    await assert.rejects(() => lstat(join(producerRoot, path)), { code: 'ENOENT' });
    await regularPath(harnessRoot, parts);
    notesSourceCommit = git(harnessRoot, 'rev-parse', 'HEAD');
    notes = await readFile(join(harnessRoot, path));
    const committed = execFileSync('git', ['-C', harnessRoot, 'show', `HEAD:${path}`]);
    assert.deepEqual(notes, committed, 'Notes must match the reviewed harness commit');
  }
  assert.ok(
    notes.includes(`<h1>Curfew ${version}</h1>`),
    'Notes must name the exact candidate version',
  );
  const receipt = {
    schemaVersion: 1,
    scope: tracked ? 'producer-release-note-data' : 'supplemental-release-note-data-only',
    version,
    producerSourceCommit,
    notesSourceCommit,
    path,
    notesSHA256: createHash('sha256').update(notes).digest('hex'),
  };
  if (!tracked) await writeFile(join(producerRoot, path), notes, { flag: 'wx' });
  git(producerRoot, 'diff', '--exit-code', 'HEAD', '--');
  assert.equal(
    git(producerRoot, 'status', '--porcelain', '--untracked-files=all'),
    tracked ? '' : `?? ${path}`,
  );
  await writeFile(join(upgradeRoot, 'release-note-input.html'), notes, { flag: 'wx' });
  await writeFile(
    join(upgradeRoot, 'release-note-input.json'),
    JSON.stringify(receipt, null, 2) + '\n',
    { flag: 'wx' },
  );
  return receipt;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  assert.equal(process.argv.length, 4);
  await stageUpgradeNotes({
    harnessRoot: process.cwd(),
    producerRoot: resolve(process.argv[2]),
    upgradeRoot: resolve(process.argv[3]),
  });
}
