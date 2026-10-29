import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, mkdir, writeFile, readFile, rm, symlink, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';

const git = (root, ...args) =>
  execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trim();
async function fixture(t) {
  const root = await realpath(await mkdtemp(join(tmpdir(), 'curfew-upgrade-notes-')));
  t.after(() => rm(root, { recursive: true, force: true }));
  const harnessRoot = join(root, 'harness'),
    producerRoot = join(root, 'producer'),
    upgradeRoot = join(root, 'upgrade');
  const notes = '<h1>Curfew 0.0.17</h1><p>Clock corrections.</p>';
  for (const dir of [harnessRoot, producerRoot]) {
    await mkdir(join(dir, 'landing/releases'), { recursive: true });
    git(dir, 'init', '-q');
    await writeFile(join(dir, 'tracked'), 'original');
  }
  await writeFile(join(harnessRoot, 'landing/releases/0.0.17.html'), notes);
  for (const dir of [harnessRoot, producerRoot]) {
    git(dir, 'add', '.');
    const tree = git(dir, 'write-tree');
    const commit = git(
      dir,
      '-c',
      'user.name=Fixture',
      '-c',
      'user.email=fixture@example.test',
      'commit-tree',
      tree,
      '-m',
      'fixture',
    );
    git(dir, 'update-ref', 'HEAD', commit);
  }
  await mkdir(join(upgradeRoot, 'candidate'), { recursive: true });
  const candidate = {
    version: '0.0.17',
    sourceCommit: git(producerRoot, 'rev-parse', 'HEAD'),
    runID: '123',
    dmgSHA256: 'a'.repeat(64),
  };
  await writeFile(
    join(upgradeRoot, 'upgrade-plan.json'),
    JSON.stringify({ scope: 'disposable-sparkle-upgrade', candidate }),
  );
  await writeFile(
    join(upgradeRoot, 'candidate/acceptance-subject.json'),
    JSON.stringify(candidate),
  );
  return { harnessRoot, producerRoot, upgradeRoot, notes, candidate };
}
async function stage(f) {
  const module = await import('./upgrade-notes.mjs').catch(() => ({}));
  assert.equal(
    typeof module.stageUpgradeNotes,
    'function',
    'Missing release-note data staging behavior',
  );
  return module.stageUpgradeNotes(f);
}
test('missing upgrade notes are supplied as separately attributed data without changing producer code', async (t) => {
  const f = await fixture(t),
    before = git(f.producerRoot, 'rev-parse', 'HEAD^{tree}');
  const receipt = await stage(f);
  assert.equal(
    await readFile(join(f.producerRoot, 'landing/releases/0.0.17.html'), 'utf8'),
    f.notes,
  );
  assert.equal(receipt.producerSourceCommit, f.candidate.sourceCommit);
  assert.equal(receipt.notesSourceCommit, git(f.harnessRoot, 'rev-parse', 'HEAD'));
  assert.equal(receipt.notesSHA256, createHash('sha256').update(f.notes).digest('hex'));
  assert.equal(receipt.scope, 'supplemental-release-note-data-only');
  assert.equal(git(f.producerRoot, 'rev-parse', 'HEAD^{tree}'), before);
  assert.equal(
    git(f.producerRoot, 'status', '--porcelain', '--untracked-files=all'),
    '?? landing/releases/0.0.17.html',
  );
  assert.deepEqual(
    JSON.parse(await readFile(join(f.upgradeRoot, 'release-note-input.json'))),
    receipt,
  );
  assert.equal(await readFile(join(f.upgradeRoot, 'release-note-input.html'), 'utf8'), f.notes);
});
test('normal producer-tracked release notes remain authoritative and are never replaced by harness notes', async (t) => {
  const f = await fixture(t),
    notes = '<h1>Curfew 0.0.17</h1><p>Producer notes.</p>';
  await writeFile(join(f.producerRoot, 'landing/releases/0.0.17.html'), notes);
  git(f.producerRoot, 'add', '.');
  const tree = git(f.producerRoot, 'write-tree');
  const commit = git(
    f.producerRoot,
    '-c',
    'user.name=Fixture',
    '-c',
    'user.email=fixture@example.test',
    'commit-tree',
    tree,
    '-m',
    'producer notes',
  );
  git(f.producerRoot, 'update-ref', 'HEAD', commit);
  f.candidate.sourceCommit = commit;
  await writeFile(
    join(f.upgradeRoot, 'upgrade-plan.json'),
    JSON.stringify({ scope: 'disposable-sparkle-upgrade', candidate: f.candidate }),
  );
  await writeFile(
    join(f.upgradeRoot, 'candidate/acceptance-subject.json'),
    JSON.stringify(f.candidate),
  );
  const receipt = await stage(f);
  assert.equal(receipt.scope, 'producer-release-note-data');
  assert.equal(receipt.notesSourceCommit, commit);
  assert.equal(await readFile(join(f.producerRoot, 'landing/releases/0.0.17.html'), 'utf8'), notes);
  assert.equal(await readFile(join(f.upgradeRoot, 'release-note-input.html'), 'utf8'), notes);
  assert.equal(git(f.producerRoot, 'status', '--porcelain', '--untracked-files=all'), '');
});
for (const scenario of [
  'wrong heading',
  'uncommitted notes',
  'existing destination',
  'symlink parent',
  'changed producer',
  'different subject',
  'unsafe version',
]) {
  test(`upgrade notes refuse ${scenario}`, async (t) => {
    const f = await fixture(t);
    if (scenario === 'wrong heading') {
      await writeFile(
        join(f.harnessRoot, 'landing/releases/0.0.17.html'),
        '<h1>Curfew 0.0.18</h1>',
      );
      git(f.harnessRoot, 'add', '.');
      const tree = git(f.harnessRoot, 'write-tree');
      git(
        f.harnessRoot,
        'update-ref',
        'HEAD',
        git(
          f.harnessRoot,
          '-c',
          'user.name=Fixture',
          '-c',
          'user.email=fixture@example.test',
          'commit-tree',
          tree,
          '-m',
          'wrong notes',
        ),
      );
    } else if (scenario === 'uncommitted notes') {
      await writeFile(join(f.harnessRoot, 'landing/releases/0.0.17.html'), f.notes + 'unreviewed');
    } else if (scenario === 'existing destination') {
      await writeFile(join(f.producerRoot, 'landing/releases/0.0.17.html'), 'retained');
    } else if (scenario === 'symlink parent') {
      await rm(join(f.producerRoot, 'landing/releases'), { recursive: true });
      await symlink(
        join(f.harnessRoot, 'landing/releases'),
        join(f.producerRoot, 'landing/releases'),
      );
    } else if (scenario === 'changed producer') {
      await writeFile(join(f.producerRoot, 'tracked'), 'changed');
    } else if (scenario === 'different subject') {
      await writeFile(
        join(f.upgradeRoot, 'candidate/acceptance-subject.json'),
        JSON.stringify({ ...f.candidate, sourceCommit: 'b'.repeat(40) }),
      );
    } else {
      await writeFile(
        join(f.upgradeRoot, 'upgrade-plan.json'),
        JSON.stringify({
          scope: 'disposable-sparkle-upgrade',
          candidate: { ...f.candidate, version: '../../arbitrary' },
        }),
      );
    }
    await assert.rejects(() => stage(f));
  });
}
test('workflow supplies notes after immutable preparation and retains the separate provenance', () => {
  const workflow = JSON.parse(
    execFileSync(
      'ruby',
      [
        '-rjson',
        '-ryaml',
        '-e',
        'puts JSON.generate(YAML.load_file(ARGV[0]))',
        '.github/workflows/signed-installer-acceptance.yml',
      ],
      { encoding: 'utf8' },
    ),
  );
  const steps = workflow.jobs['staging-upgrade'].steps;
  const stage = steps.find(
    (step) => step.name === 'Supply reviewed release-note data without changing producer code',
  );
  assert.ok(stage, 'Missing release-note data staging step');
  assert.ok(
    steps.indexOf(stage) >
      steps.findIndex(
        (step) => step.name === 'Retain the pinned older build and exact new subject',
      ),
  );
  assert.ok(
    steps.indexOf(stage) <
      steps.findIndex(
        (step) => step.name === 'Perform the real Sparkle update and verify installed bytes',
      ),
  );
  assert.match(stage.run, /node scripts\/upgrade-notes.mjs candidate-source/);
  assert.match(steps.at(-1).with.path, /release-note-input\.json/);
  assert.match(steps.at(-1).with.path, /release-note-input\.html/);
});
