import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import {
  lstat,
  mkdir,
  readFile,
  writeFile,
  readdir,
  readlink,
  rm,
  rmdir,
  cp,
  rename,
  realpath,
} from 'node:fs/promises';
import { userInfo } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { requireDisposableRunner } from './signed-installer-acceptance.mjs';
import { verifyCandidate } from './release-candidate.mjs';

const subjects = [
  {
    version: '0.0.16',
    runID: '40113971717',
    sourceCommit: '07a1322780a8428d63486748eb94396985693cf8',
    dmgSHA256: '4804f7cdf26ec6aa54fc0877d5cc5f7c12043bb972c10502f346f0924a5f8f34',
  },
  {
    version: '0.0.17',
    runID: '40872194413',
    sourceCommit: '8eefbc723397e3fa05657b89b2aff95bdad83fb3',
    dmgSHA256: '64b045c08570c4ac0886224c234f726428d8bec4456cc4d0f99c22a2a822b41e',
  },
];
const app = '/Applications/Curfew.app';
const data = '/Users/runner/Library/Application Support/Curfew';
const hash = (bytes) => createHash('sha256').update(bytes).digest('hex');
const json = async (path) => JSON.parse(await readFile(path, 'utf8'));
const run = (command, args, options = {}) =>
  execFileSync(command, args, { encoding: 'utf8', ...options });
export function snapshotDigest(snapshot) {
  const value = structuredClone(snapshot);
  // Swift encodes [Weekday: DayRule] as unordered alternating key/value pairs.
  // Preserve every entry and value; ordering of all other arrays stays significant.
  const rules = value.settings.schedule.rules;
  assert.ok(Array.isArray(rules) && rules.length % 2 === 0);
  const pairs = [];
  const days = new Set();
  for (let i = 0; i < rules.length; i += 2) {
    const day = rules[i];
    assert.ok(Number.isInteger(day) && day >= 1 && day <= 7 && !days.has(day));
    days.add(day);
    pairs.push([day, rules[i + 1]]);
  }
  value.settings.schedule.rules = pairs.sort((a, b) => a[0] - b[0]).flat();
  const canonical = (item) =>
    Array.isArray(item)
      ? item.map(canonical)
      : item !== null && typeof item === 'object'
        ? Object.fromEntries(
            Object.keys(item)
              .sort()
              .map((key) => [key, canonical(item[key])]),
          )
        : item;
  return hash(JSON.stringify(canonical(value)));
}
export function requireContinuityHost(context) {
  requireDisposableRunner(context);
  assert.equal(context.runnerEnvironment, 'github-hosted', 'A GitHub-hosted VM is required');
  assert.ok(
    Number.isInteger(context.uid) && context.uid >= 500,
    'Unprivileged disposable user required',
  );
}
function host() {
  const account = userInfo();
  requireContinuityHost({
    githubActions: process.env.GITHUB_ACTIONS,
    username: account.username,
    home: account.homedir,
    uid: account.uid,
    temporary: process.env.RUNNER_TEMP,
    runnerEnvironment: process.env.RUNNER_ENVIRONMENT,
  });
  assert.equal(process.env.HOME, account.homedir);
  return account;
}
export async function requireEmptyPaths(paths) {
  for (const path of paths)
    await assert.rejects(() => lstat(path), { code: 'ENOENT' }, `Preexisting state: ${path}`);
}
export function requireMissingService(result) {
  assert.equal(result.status, 113, 'Service query did not establish absence');
  assert.match(
    String(result.stderr),
    /Could not find service/,
    'Unrecognized service query failure',
  );
}
function servicesAbsent() {
  const uid = userInfo().uid;
  for (const name of [
    'studio.hypertext.apps.curfew.supervisor',
    'studio.hypertext.apps.curfew.dev.supervisor',
    'studio.hypertext.curfew.lockdown',
  ])
    requireMissingService(spawnSync('launchctl', ['print', `gui/${uid}/${name}`]));
  for (const name of ['studio.hypertext.curfew.daemon', 'studio.hypertext.apps.curfew.dev.daemon'])
    requireMissingService(spawnSync('launchctl', ['print', `system/${name}`]));
  assert.equal(
    spawnSync('pgrep', ['-x', 'Curfew|Curfew Dev|curfew-supervisor|curfew-daemon']).status,
    1,
    'Curfew processes must be absent',
  );
  return true;
}
export function continuityReceipt(input) {
  for (const [i, key] of ['baseline', 'candidate'].entries())
    for (const [field, value] of Object.entries(subjects[i]))
      assert.equal(input[key][field], value);
  assert.equal(input.baseline.configurationSHA256, input.candidate.configurationSHA256);
  assert.deepEqual(
    input.stages.map((x) => x.name),
    ['baseline', 'candidate', 'rollback', 'restored'],
  );
  for (const [index, stage] of input.stages.entries()) {
    assert.equal(stage.version, index === 1 ? '0.0.17' : '0.0.16');
    assert.equal(stage.ui.version, stage.version);
    assert.equal(stage.ui.bundleIdentifier, 'studio.hypertext.apps.curfew');
    assert.equal(stage.ui.appMenuVisible, true);
    assert.equal(stage.ui.onboardingComplete, false);
    assert.ok(Number.isInteger(stage.ui.pid) && stage.ui.pid > 0);
    for (const key of ['installedFilesMatchCandidate', 'servicesAbsent', 'signedExportsVerified'])
      assert.equal(stage[key], true);
    assert.equal(stage.recordCount, index < 2 ? 1 : 2);
    assert.match(stage.beforeDataSHA256, /^[a-f0-9]{64}$/);
    assert.equal(
      stage.beforeDataSHA256,
      stage.afterDataSHA256,
      'App launch changed retained synthetic content',
    );
  }
  assert.equal(input.stages[0].afterDataSHA256, input.stages[1].beforeDataSHA256);
  assert.equal(input.stages[2].beforeDataSHA256, input.postWriteSHA256);
  assert.equal(input.stages[3].beforeDataSHA256, input.postWriteSHA256);
  return {
    schemaVersion: 1,
    scope: 'unonboarded-signed-data-continuity-and-rollback',
    ...input,
    enforcementTested: false,
    helperApprovalTested: false,
    accountAcceptanceClaimed: false,
    credentialContinuityTested: false,
    productionRollbackClaimed: false,
  };
}
async function ownedRoot(directory) {
  const account = host();
  assert.equal(resolve(directory), join(process.env.RUNNER_TEMP, 'signed-continuity'));
  assert.equal(await realpath(process.env.RUNNER_TEMP), process.env.RUNNER_TEMP);
  const owner = await json(join(directory, 'owner.json'));
  assert.equal(owner.uid, account.uid);
  assert.equal(owner.runID, process.env.GITHUB_RUN_ID);
  assert.equal(owner.harnessSourceCommit, process.env.GITHUB_SHA);
}
async function prepare(directory) {
  const account = host();
  for (const [key, field] of [
    ['CURFEW_UPGRADE_VERSION', 'version'],
    ['CURFEW_UPGRADE_RUN_ID', 'runID'],
    ['CURFEW_UPGRADE_SOURCE_COMMIT', 'sourceCommit'],
    ['CURFEW_UPGRADE_DMG_SHA256', 'dmgSHA256'],
  ])
    assert.equal(
      process.env[key],
      subjects[1][field],
      'This continuity check pins the approved 0.0.17 subject',
    );
  assert.equal(resolve(directory), join(process.env.RUNNER_TEMP, 'signed-continuity'));
  assert.equal(await realpath(process.env.RUNNER_TEMP), process.env.RUNNER_TEMP);
  servicesAbsent();
  await requireEmptyPaths([
    directory,
    app,
    data,
    '/Users/runner/Library/Preferences/studio.hypertext.curfew.plist',
    '/Users/runner/Library/Group Containers/group.studio.hypertext.apps.curfew',
    '/Users/runner/Library/Group Containers/group.studio.hypertext.curfew',
    '/Library/Application Support/Curfew',
  ]);
  const preferences = spawnSync('defaults', ['read', 'studio.hypertext.curfew']);
  assert.equal(preferences.status, 1, 'Preferences domain already exists or its lookup failed');
  assert.match(String(preferences.stderr), /does not exist/);
  await mkdir(directory, { mode: 0o700 });
  await writeFile(
    join(directory, 'owner.json'),
    JSON.stringify({
      uid: account.uid,
      runID: process.env.GITHUB_RUN_ID,
      harnessSourceCommit: process.env.GITHUB_SHA,
    }),
    { flag: 'wx', mode: 0o600 },
  );
  for (const [index, subject] of subjects.entries()) {
    run(
      'node',
      [
        'scripts/signed-installer-acceptance.mjs',
        'prepare',
        join(directory, index ? 'candidate' : 'baseline'),
      ],
      {
        stdio: 'inherit',
        env: {
          ...process.env,
          CURFEW_UPGRADE_VERSION: subject.version,
          CURFEW_UPGRADE_RUN_ID: subject.runID,
          CURFEW_UPGRADE_SOURCE_COMMIT: subject.sourceCommit,
          CURFEW_UPGRADE_DMG_SHA256: subject.dmgSHA256,
        },
      },
    );
  }
}
async function manifest(root) {
  const entries = [];
  async function visit(relative = '') {
    for (const name of (await readdir(join(root, relative))).sort()) {
      const path = join(relative, name),
        stat = await lstat(join(root, path));
      if (stat.isDirectory()) await visit(path);
      else if (stat.isFile()) entries.push([path, hash(await readFile(join(root, path)))]);
      else {
        assert.ok(stat.isSymbolicLink());
        entries.push([path, await readlink(join(root, path))]);
      }
    }
  }
  await visit();
  return hash(JSON.stringify(entries));
}
async function install(directory, index, previousManifest) {
  servicesAbsent();
  if (previousManifest)
    assert.equal(await manifest(app), previousManifest, 'Installed app changed outside this run');
  else await requireEmptyPaths([app]);
  const part = join(directory, index ? 'candidate' : 'baseline'),
    subject = await json(join(part, 'candidate.json'));
  const source = resolve(index ? 'candidate-source' : 'baseline-source');
  assert.equal(
    run('git', ['-C', source, 'rev-parse', 'HEAD']).trim(),
    subjects[index].sourceCommit,
  );
  run('git', ['-C', source, 'diff', '--exit-code', 'HEAD', '--']);
  for (const [key, value] of Object.entries(subjects[index])) assert.equal(subject[key], value);
  const image = join(part, `Curfew-v${subject.version}.dmg`);
  verifyCandidate({
    candidate: subject,
    configuration: await json(join(part, 'release-configuration.json')),
    dmg: await readFile(image),
    appcast: await readFile(join(part, 'appcast.xml')),
  });
  run('xcrun', ['stapler', 'validate', image], { stdio: 'inherit' });
  run('spctl', ['--assess', '--type', 'open', '--context', 'context:primary-signature', image], {
    stdio: 'inherit',
  });
  const volume = join(directory, 'mount');
  await mkdir(volume);
  let mounted = false;
  try {
    run('hdiutil', ['attach', '-readonly', '-nobrowse', '-mountpoint', volume, image], {
      stdio: 'inherit',
    });
    mounted = true;
    run(
      'bash',
      [
        'scripts/verify-release-artifact.sh',
        join(volume, 'Curfew.app'),
        join(part, 'release-configuration.json'),
        subject.version,
      ],
      { cwd: source, stdio: 'inherit' },
    );
    const expected = await manifest(join(volume, 'Curfew.app'));
    if (previousManifest) await rm(app, { recursive: true });
    run('ditto', [join(volume, 'Curfew.app'), app]);
    assert.equal(await manifest(app), expected);
    run('codesign', ['--verify', '--strict', '--deep', app], { stdio: 'inherit' });
    run(
      '/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister',
      [app],
    );
    return expected;
  } finally {
    if (mounted) run('hdiutil', ['detach', volume], { stdio: 'inherit' });
    await rmdir(volume);
  }
}
async function execute(directory) {
  await ownedRoot(directory);
  servicesAbsent();
  await requireEmptyPaths([app, data]);
  const source = resolve('candidate-source');
  assert.equal(run('git', ['-C', source, 'rev-parse', 'HEAD']).trim(), subjects[1].sourceCommit);
  const files = run('git', ['-C', source, 'ls-files', 'CurfewKit/Sources/CurfewKit'])
    .trim()
    .split('\n')
    .filter((x) => x.endsWith('.swift'))
    .map((x) => join(source, x));
  const helper = join(directory, 'continuity-data');
  run(
    'swiftc',
    ['-parse-as-library', ...files, resolve('scripts/SignedContinuityData.swift'), '-o', helper],
    { stdio: 'inherit' },
  );
  const snapshot = () => JSON.parse(run(helper, ['snapshot']));
  const digest = snapshotDigest;
  let currentManifest;
  const stages = [];
  let postWriteSHA256;
  for (const [position, name] of ['baseline', 'candidate', 'rollback', 'restored'].entries()) {
    const index = position === 1 ? 1 : 0;
    if (position !== 3) currentManifest = await install(directory, index, currentManifest);
    if (position === 0) run(helper, ['seed']);
    if (position === 3) {
      servicesAbsent();
      await rename(data, join(directory, 'pre-restore-data'));
      await cp(join(directory, 'backup'), data, {
        recursive: true,
        errorOnExist: true,
        force: false,
      });
      run('defaults', ['import', 'studio.hypertext.curfew', join(directory, 'preferences.plist')]);
    }
    const before = snapshot(),
      count = position < 2 ? 1 : 2;
    assert.equal(before.events.length, count);
    assert.equal(before.reflections.length, count);
    assert.equal(before.settings.hasCompletedInitialSetup, false);
    assert.equal(before.settings.autoShutdownEnabled, false);
    await writeFile(join(directory, `${name}-before-data.json`), JSON.stringify(before, null, 2), {
      flag: 'wx',
    });
    const uiPath = join(directory, `${name}-ui.json`);
    run(
      'xcodebuild',
      [
        'test',
        '-project',
        'Curfew.xcodeproj',
        '-scheme',
        'Curfew',
        '-destination',
        'platform=macOS',
        '-resultBundlePath',
        join(directory, `${name}.xcresult`),
        '-only-testing:CurfewUITests/SignedInstallerAcceptanceTests/testSignedDataContinuityLaunch',
        '-parallel-testing-enabled',
        'NO',
        'CODE_SIGNING_ALLOWED=NO',
        'CODE_SIGNING_REQUIRED=NO',
      ],
      {
        stdio: 'inherit',
        env: {
          ...process.env,
          TEST_RUNNER_GITHUB_ACTIONS: 'true',
          TEST_RUNNER_RUNNER_TEMP: process.env.RUNNER_TEMP,
          TEST_RUNNER_CURFEW_SIGNED_CONTINUITY: '1',
          TEST_RUNNER_CURFEW_SIGNED_CONTINUITY_VERSION: subjects[index].version,
          TEST_RUNNER_CURFEW_SIGNED_CONTINUITY_RECEIPT: uiPath,
        },
      },
    );
    servicesAbsent();
    const after = snapshot(),
      ctl = join(app, 'Contents/Resources/curfew-ctl');
    const activity = JSON.parse(run(ctl, ['activity', '--json']));
    const reflections = JSON.parse(run(ctl, ['reflections', '--json']));
    assert.equal(
      activity.events.filter((x) => x.note?.startsWith('Signed continuity synthetic')).length,
      count,
    );
    assert.equal(
      reflections.reflections.filter((x) =>
        x.answers.some((a) => a.value?.startsWith?.('Signed continuity synthetic')),
      ).length,
      count,
    );
    const budget = JSON.parse(run(ctl, ['budget', '--json']));
    assert.equal(budget.extensions.weekly_limit, 7);
    await writeFile(
      join(directory, `${name}-signed-exports.json`),
      JSON.stringify({ activity, reflections, budget }, null, 2),
      { flag: 'wx' },
    );
    await writeFile(join(directory, `${name}-data.json`), JSON.stringify(after, null, 2), {
      flag: 'wx',
    });
    stages.push({
      name,
      version: subjects[index].version,
      ui: await json(uiPath),
      installedFilesMatchCandidate: (await manifest(app)) === currentManifest,
      servicesAbsent: true,
      beforeDataSHA256: digest(before),
      afterDataSHA256: digest(after),
      recordCount: count,
      signedExportsVerified: true,
    });
    if (position === 1) {
      run(helper, ['append']);
      postWriteSHA256 = digest(snapshot());
      await cp(data, join(directory, 'backup'), {
        recursive: true,
        errorOnExist: true,
        force: false,
      });
      run('defaults', ['export', 'studio.hypertext.curfew', join(directory, 'preferences.plist')]);
    }
  }
  const receipt = continuityReceipt({
    baseline: await json(join(directory, 'baseline/candidate.json')),
    candidate: await json(join(directory, 'candidate/candidate.json')),
    stages,
    postWriteSHA256,
    observedAt: new Date().toISOString(),
    harnessSourceCommit: process.env.GITHUB_SHA,
  });
  await writeFile(join(directory, 'continuity.json'), JSON.stringify(receipt, null, 2) + '\n', {
    flag: 'wx',
  });
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  assert.equal(process.argv.length, 4);
  const [command, directory] = process.argv.slice(2);
  if (command === 'prepare') await prepare(resolve(directory));
  else {
    assert.equal(command, 'run');
    await execute(resolve(directory));
  }
}
