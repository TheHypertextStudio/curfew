import { readFileSync, existsSync } from 'node:fs';
import assert from 'node:assert/strict';
import test from 'node:test';

const project = readFileSync(new URL('../Curfew.xcodeproj/project.pbxproj', import.meta.url), 'utf8');
test('Xcode resolves shared library, protocol contract, and updater together', () => {
  const references = [...project.matchAll(/packageReferences = \(([\s\S]*?)\);/g)];
  assert.equal(references.length, 1, 'Duplicate packageReferences hides earlier dependencies');
  for (const name of ['CurfewKit', 'curfew-protocols', 'Sparkle']) {
    assert.ok(references[0][1].includes(name), `${name} must be in the package graph`);
  }
});

for (const label of ['studio.hypertext.curfew.daemon', 'studio.hypertext.apps.curfew.dev.daemon']) {
  test(`Helper ${label} registers its own authenticated endpoint`, () => {
    const plist = readFileSync(new URL(`../Curfew/Resources/LaunchDaemons/${label}.plist`, import.meta.url), 'utf8');
    const services = /<key>MachServices<\/key>\s*<dict>([\s\S]*?)<\/dict>/.exec(plist);
    assert.ok(services, 'Mach service registration is required for authenticated replies');
    assert.ok(services[1].includes(`<key>${label}</key>`));
    assert.match(plist, /<key>RunAtLoad<\/key>\s*<true\/>/);
  });
}

test('Formatting checks include real shared-package directories', () => {
  const recipe = readFileSync(new URL('../justfile', import.meta.url), 'utf8');
  const directories = /source_dirs := "([^"]+)"/.exec(recipe)[1].split(' ');
  for (const directory of directories) assert.ok(existsSync(new URL(`../${directory}`, import.meta.url)), directory);
  assert.ok(directories.includes('CurfewKit/Sources'));
  assert.ok(directories.includes('CurfewKit/Tests'));
});

test('Remote CI covers the shared package and interactive UI separately from captures', () => {
  const workflow = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  assert.ok(workflow.includes('swift test --package-path CurfewKit'));
  assert.ok(workflow.includes('-only-testing:CurfewUITests/CurfewUITests'));
  assert.ok(workflow.includes('just build-release'));
});

test('Graphical acceptance uses the isolated ARM64 macOS 26 lane', () => {
  const workflow = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  const graphicalJob = workflow.split('\n  screenshots:\n')[1];
  assert.ok(graphicalJob, 'Graphical acceptance must remain a separate hosted job');
  assert.match(graphicalJob, /runs-on: macos-26\s*\n/,
    'Avoid the Intel image whose IconServices crash blocks accessibility snapshots');
  assert.ok(graphicalJob.includes('-only-testing:CurfewUITests/CurfewUITests'));
  assert.ok(graphicalJob.includes('-only-testing:CurfewUITests/CurfewUITestsLaunchTests'));
  assert.ok(graphicalJob.includes('run: just capture'));
  assert.ok(graphicalJob.includes('${{ runner.arch }}-derived-'));
});

test('Native quality uses the ARM64 lane that supports the signed candidate', () => {
  const workflow = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  const qualityJob = workflow.split('\n  check:\n')[1]?.split('\n  screenshots:\n')[0];
  assert.ok(qualityJob, 'Native quality must remain a separate hosted job');
  assert.match(qualityJob, /runs-on: macos-26\s*\n/,
    'Avoid Intel runner test-host preparation failures');
  assert.ok(qualityJob.includes('swift test --package-path CurfewKit'));
  assert.ok(qualityJob.includes('run: just check'));
  assert.ok(qualityJob.includes('run: just build-release'));
});

test('Remote captures hide the runner Dock so app controls remain unobstructed', () => {
  const workflow = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  assert.ok(workflow.includes('defaults write com.apple.dock autohide -bool true'));
  assert.ok(workflow.includes('defaults write com.apple.dock autohide-delay -float 1000'));
});


test('New state fixtures run before the full capture sweep', () => {
  const workflow = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  const preflight = workflow.indexOf('Verify state fixtures before the full capture sweep');
  assert.ok(preflight >= 0);
  assert.ok(preflight < workflow.indexOf('- name: Capture demo screenshots'));
  assert.ok(workflow.includes('-only-testing:CurfewUITests/MarketingCaptureTests/testCaptureAStateConsistency'));
  assert.ok(workflow.includes('build/state-consistency.xcresult'));
});


test('State preflight independently exercises all ten state families', () => {
  const workflow = readFileSync(new URL('../.github/workflows/ci.yml', import.meta.url), 'utf8');
  const selected = workflow.match(/-only-testing:CurfewUITests\/MarketingCaptureTests\/testCaptureAStateConsistency\w+/g) || [];
  assert.equal(selected.length, 10);
  const tests = readFileSync(new URL('../CurfewUITests/StateConsistencyCaptureTests.swift', import.meta.url), 'utf8');
  for (const selection of selected) assert.ok(tests.includes('func ' + selection.split('/').at(-1) + '()'));
});
