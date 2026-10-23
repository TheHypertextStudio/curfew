import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import {
  mkdtempSync, mkdirSync, writeFileSync, readFileSync, rmSync, copyFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { verifyEmbeddedToolPackaging } from './release-candidate.mjs';

const tools = [
  'curfew-ctl', 'curfew-mcp', 'curfew-daemon', 'studio.hypertext.curfew.browser',
];
// Minimal Mach-O headers are architecture fixtures, never launched or signed.
function slice(arch) {
  const header = Buffer.alloc(32);
  header.writeUInt32LE(0xfeedfacf, 0);
  header.writeUInt32LE(arch === 'arm64' ? 0x100000c : 0x1000007, 4);
  header.writeUInt32LE(arch === 'arm64' ? 0 : 3, 8);
  header.writeUInt32LE(2, 12);
  return header;
}
function fixture() {
  const root = mkdtempSync(join(tmpdir(), 'curfew-architectures-'));
  for (const arch of ['arm64', 'x86_64']) {
    writeFileSync(join(root, arch), slice(arch), { mode: 0o700 });
  }
  execFileSync('/usr/bin/lipo', [
    '-create', join(root, 'arm64'), join(root, 'x86_64'),
    '-output', join(root, 'universal'),
  ]);
  return root;
}

for (const archs of ['arm64 x86_64', 'arm64']) {
  test(`Xcode bundles every tool for ARCHS=${archs} using the queried product path`, () => {
    const root = fixture();
    try {
      const project = JSON.parse(execFileSync('plutil', [
        '-convert', 'json', '-o', '-', 'Curfew.xcodeproj/project.pbxproj',
      ], { encoding: 'utf8' }));
      const phase = Object.values(project.objects).find(
        o => o.isa === 'PBXShellScriptBuildPhase' && o.name === 'Bundle CLI Tools',
      );
      mkdirSync(join(root, 'bin'));
      mkdirSync(join(root, 'CurfewKit/.build/release'), { recursive: true });
      mkdirSync(join(root, 'queried products'), { recursive: true });
      // A host-only stale path remains available, reproducing the original bug.
      for (const tool of tools) {
        copyFileSync(join(root, 'arm64'), join(root, 'CurfewKit/.build/release', tool));
      }
      writeFileSync(join(root, 'bin/swift'), `#!/usr/bin/env node
const fs = require('fs'), p = require('path'), args = process.argv.slice(2), root = process.env.FIXTURE_ROOT;
fs.appendFileSync(p.join(root, 'calls.jsonl'), JSON.stringify(args) + '\\n');
const arches = args.flatMap((v,i) => v === '--arch' ? [args[i+1]] : []);
const source = arches.includes('x86_64') ? 'universal' : 'arm64';
const out = p.join(root, 'queried products');
if (args.includes('--show-bin-path')) console.log(out);
else if (args.includes('--product')) fs.copyFileSync(p.join(root, source), p.join(out, args[args.indexOf('--product')+1]));
`, { mode: 0o700 });
      // Keep the real script and launch plist available under the fixture SRCROOT.
      mkdirSync(join(root, 'scripts'));
      for (const name of ['bundle-cli-tools.sh']) {
        try {
          copyFileSync(join('scripts', name), join(root, 'scripts', name));
        } catch (error) {
          if (error.code !== 'ENOENT') throw error;
        }
      }
      mkdirSync(join(root, 'Curfew/Resources/LaunchDaemons'), { recursive: true });
      const plist = 'studio.hypertext.apps.curfew.dev.daemon.plist';
      copyFileSync(join('Curfew/Resources/LaunchDaemons', plist), join(root, 'Curfew/Resources/LaunchDaemons', plist));
      const result = spawnSync('/bin/sh', ['-c', phase.shellScript], {
        encoding: 'utf8',
        env: {
          ...process.env,
          PATH: `${root}/bin:${process.env.PATH}`,
          FIXTURE_ROOT: root,
          SRCROOT: root,
          BUILT_PRODUCTS_DIR: root,
          CONTENTS_FOLDER_PATH: 'Fixture.app/Contents',
          ARCHS: archs,
          CONFIGURATION: 'Debug',
          CURFEW_DAEMON_PLIST_NAME: plist,
          CURFEW_SERVICE_SWIFT_FLAG: 'CURFEW_STAGING',
          CODE_SIGNING_ALLOWED: 'NO',
        },
      });
      assert.equal(result.status, 0, result.stderr);
      for (const tool of tools) {
        const actual = execFileSync('/usr/bin/lipo', [
          '-archs', join(root, 'Fixture.app/Contents/Resources', tool),
        ], { encoding: 'utf8' }).trim().split(/\s+/).sort();
        assert.deepEqual(actual, archs.split(' ').sort(), `${tool} must match the app's requested slices`);
      }
      const calls = readFileSync(join(root, 'calls.jsonl'), 'utf8').trim().split('\n').map(JSON.parse);
      for (const tool of tools) {
        const build = calls.find(args => args.includes(tool) && !args.includes('--show-bin-path'));
        assert.ok(build.includes('-Xswiftc') && build.includes('-DCURFEW_STAGING'), 'staging boundary must survive');
        assert.ok(calls.some(args =>
          args.includes('--show-bin-path') &&
          args.filter(v => v === '--arch').length === archs.split(' ').length,
        ));
      }
    } finally { rmSync(root, { recursive: true, force: true }); }
  });
}

test('final artifact verification rejects every missing tool slice and a narrowed app', async () => {
  const root = fixture();
  try {
    const app = join(root, 'Curfew.app');
    mkdirSync(join(app, 'Contents/MacOS'), { recursive: true });
    mkdirSync(join(app, 'Contents/Resources'), { recursive: true });
    const main = join(app, 'Contents/MacOS/Curfew');
    copyFileSync(join(root, 'universal'), main);
    for (const tool of tools) copyFileSync(join(root, 'universal'), join(app, 'Contents/Resources', tool));
    assert.deepEqual(await verifyEmbeddedToolPackaging(app), tools);
    for (const arch of ['arm64', 'x86_64']) {
      for (const tool of tools) {
        const path = join(app, 'Contents/Resources', tool);
        copyFileSync(join(root, arch), path);
        await assert.rejects(() => verifyEmbeddedToolPackaging(app), new RegExp(`${tool}.*${arch === 'arm64' ? 'x86_64' : 'arm64'}`));
        copyFileSync(join(root, 'universal'), path);
      }
      copyFileSync(join(root, arch), main);
      await assert.rejects(() => verifyEmbeddedToolPackaging(app), new RegExp(`Curfew.*${arch === 'arm64' ? 'x86_64' : 'arm64'}`));
      copyFileSync(join(root, 'universal'), main);
    }
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test('the bundle phase rejects absent architectures and staging in Release before building', () => {
  const root = mkdtempSync(join(tmpdir(), 'curfew-packaging-boundary-'));
  try {
    mkdirSync(join(root, 'bin'));
    writeFileSync(join(root, 'bin/swift'), '#!/bin/sh\necho UNEXPECTED_BUILD >&2\nexit 99\n', { mode: 0o700 });
    for (const [archs, configuration, flag, expected] of [
      ['', 'Debug', '', /Xcode ARCHS is required/],
      ['   ', 'Debug', '', /ARCHS must contain/],
      ['arm64 x86_64', 'Release', 'CURFEW_STAGING', /requires an isolated Debug/],
      ['arm64', 'Debug', 'UNKNOWN_SERVICE', /Unsupported Curfew service/],
    ]) {
      const result = spawnSync('/bin/bash', ['scripts/bundle-cli-tools.sh'], {
        encoding: 'utf8',
        env: {
          ...process.env,
          SRCROOT: root,
          PATH: `${root}/bin:${process.env.PATH}`,
          ARCHS: archs,
          CONFIGURATION: configuration,
          CURFEW_SERVICE_SWIFT_FLAG: flag,
          CURFEW_DAEMON_PLIST_NAME: configuration === 'Debug'
            ? 'studio.hypertext.apps.curfew.dev.daemon.plist'
            : 'studio.hypertext.curfew.daemon.plist',
        },
      });
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, expected);
      assert.doesNotMatch(result.stderr, /UNEXPECTED_BUILD/);
    }
  } finally { rmSync(root, { recursive: true, force: true }); }
});
