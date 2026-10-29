import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync, mkdtempSync, writeFileSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir, userInfo } from 'node:os';
import { join } from 'node:path';
import { execFileSync, spawnSync } from 'node:child_process';

const module = await import('./signed-data-continuity.mjs').catch(() => ({}));
test('service lookup errors cannot be misreported as an absent production service', () => {
  assert.equal(
    typeof module.requireMissingService,
    'function',
    'Missing fail-closed service admission',
  );
  module.requireMissingService({
    status: 113,
    stderr: 'Could not find service "Curfew" in domain for user gui:501',
  });
  for (const value of [
    { status: 0, stderr: '' },
    { status: null, stderr: '' },
    { status: 1, stderr: 'Operation not permitted' },
    { status: 113, stderr: 'Could not find domain' },
  ])
    assert.throws(() => module.requireMissingService(value));
});
test('existing files and symlinks are rejected before any synthetic-data write', async () => {
  const root = mkdtempSync(join(tmpdir(), 'continuity-boundaries-'));
  try {
    const file = join(root, 'state'),
      link = join(root, 'link');
    writeFileSync(file, 'unrelated state');
    symlinkSync(join(root, 'missing'), link);
    await module.requireEmptyPaths([join(root, 'absent')]);
    for (const path of [file, link, root])
      await assert.rejects(() => module.requireEmptyPaths([path]));
    assert.equal(readFileSync(file, 'utf8'), 'unrelated state');
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
test(
  'the compiled fixture refuses a forged hosted environment on the actual owner account',
  { skip: process.platform !== 'darwin' || userInfo().username === 'runner' },
  () => {
    const root = mkdtempSync(join(tmpdir(), 'continuity-guard-'));
    try {
      const sources = execFileSync('git', ['ls-files', 'CurfewKit/Sources/CurfewKit'], {
        encoding: 'utf8',
      })
        .trim()
        .split('\n')
        .filter((x) => x.endsWith('.swift'));
      const binary = join(root, 'data');
      execFileSync(
        'swiftc',
        [
          '-module-cache-path',
          join(root, 'cache'),
          '-parse-as-library',
          ...sources,
          'scripts/SignedContinuityData.swift',
          '-o',
          binary,
        ],
        { stdio: 'pipe' },
      );
      const result = spawnSync(binary, ['snapshot'], {
        env: {
          ...process.env,
          GITHUB_ACTIONS: 'true',
          RUNNER_ENVIRONMENT: 'github-hosted',
          RUNNER_TEMP: '/Users/runner/work/_temp',
        },
      });
      assert.equal(result.status, 64, 'Forged environment cannot authorize the real owner UID');
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  },
);
test('continuity refuses personal, root, self-hosted, or redirected runner identities', () => {
  assert.equal(
    typeof module.requireContinuityHost,
    'function',
    'Missing continuity isolation guard',
  );
  const valid = {
    githubActions: 'true',
    username: 'runner',
    home: '/Users/runner',
    temporary: '/Users/runner/work/_temp',
    runnerEnvironment: 'github-hosted',
    uid: 501,
  };
  module.requireContinuityHost(valid);
  for (const change of [
    { username: 'williecubed' },
    { home: '/tmp/fake' },
    { uid: 0 },
    { githubActions: 'false' },
    { temporary: '/tmp' },
    { runnerEnvironment: 'self-hosted' },
  ])
    assert.throws(() => module.requireContinuityHost({ ...valid, ...change }));
});

function evidence() {
  const subject = (version) => ({
    version,
    sourceCommit:
      version === '0.0.16'
        ? '07a1322780a8428d63486748eb94396985693cf8'
        : '8eefbc723397e3fa05657b89b2aff95bdad83fb3',
    runID: version === '0.0.16' ? '40113971717' : '40872194413',
    dmgSHA256:
      version === '0.0.16'
        ? '4804f7cdf26ec6aa54fc0877d5cc5f7c12043bb972c10502f346f0924a5f8f34'
        : '64b045c08570c4ac0886224c234f726428d8bec4456cc4d0f99c22a2a822b41e',
    configurationSHA256: '09f23b723420871b4b9db193eb3761dc13aeac25082578707d42e4470c2ab4bd',
  });
  return {
    baseline: subject('0.0.16'),
    candidate: subject('0.0.17'),
    stages: ['baseline', 'candidate', 'rollback', 'restored'].map((name, i) => ({
      name,
      version: i === 1 ? '0.0.17' : '0.0.16',
      ui: {
        version: i === 1 ? '0.0.17' : '0.0.16',
        bundleIdentifier: 'studio.hypertext.apps.curfew',
        appMenuVisible: true,
        pid: 100 + i,
        onboardingComplete: false,
      },
      installedFilesMatchCandidate: true,
      servicesAbsent: true,
      beforeDataSHA256: (i < 2 ? 'a' : 'b').repeat(64),
      afterDataSHA256: (i < 2 ? 'a' : 'b').repeat(64),
      recordCount: i < 2 ? 1 : 2,
      signedExportsVerified: true,
    })),
    postWriteSHA256: 'b'.repeat(64),
  };
}
test('continuity receipt requires actual UI, exact subjects, all stages and usable retained data', () => {
  assert.equal(typeof module.continuityReceipt, 'function', 'Missing truthful receipt admission');
  const receipt = module.continuityReceipt(evidence());
  assert.equal(receipt.scope, 'unonboarded-signed-data-continuity-and-rollback');
  assert.equal(receipt.enforcementTested, false);
  assert.equal(receipt.helperApprovalTested, false);
  assert.equal(receipt.accountAcceptanceClaimed, false);
  for (const mutate of [
    (x) => x.stages.pop(),
    (x) => (x.stages[1].ui.appMenuVisible = false),
    (x) => (x.stages[0].ui.onboardingComplete = true),
    (x) => (x.stages[2].servicesAbsent = false),
    (x) => (x.stages[1].installedFilesMatchCandidate = false),
    (x) => (x.stages[3].recordCount = 0),
    (x) => (x.stages[1].afterDataSHA256 = 'c'.repeat(64)),
    (x) => (x.stages[2].signedExportsVerified = false),
    (x) => (x.baseline.sourceCommit = '0'.repeat(40)),
    (x) => (x.candidate.dmgSHA256 = '0'.repeat(64)),
  ]) {
    const value = evidence();
    mutate(value);
    assert.throws(() => module.continuityReceipt(value));
  }
});
test('the dedicated mode uses a hosted runner and retains focused results without permissions or publication', () => {
  const workflow = readFileSync('.github/workflows/signed-installer-acceptance.yml', 'utf8');
  assert.ok(workflow.includes('data-continuity'), 'Missing isolated workflow mode');
  const job = workflow.split('\n  data-continuity:')[1];
  assert.ok(job?.includes('runs-on: macos-26'));
  assert.ok(job.includes('node scripts/signed-data-continuity.mjs prepare'));
  assert.ok(job.includes('node scripts/signed-data-continuity.mjs run'));
  assert.ok(job.includes('signed-data-continuity-acceptance'));
  assert.doesNotMatch(
    job,
    /tccutil|gh secret|publication\.mjs|sudo .*Curfew|--supervisor-acceptance/,
  );
});
