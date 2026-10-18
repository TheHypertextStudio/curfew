import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import test from 'node:test';

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');
const project = read('Curfew.xcodeproj/project.pbxproj');
const plist = (path) => JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', path], { encoding: 'utf8' }));

test('Xcode offers only Debug and Release with distinct installable app names', () => {
  const configurations = [...project.matchAll(/name = (Debug|Release|StudioDev);/g)].map(m => m[1]);
  assert.deepEqual([...new Set(configurations)].sort(), ['Debug', 'Release']);
  assert.match(project, /WRAPPER_NAME = "Curfew Dev\.app";/);
  assert.match(project, /INFOPLIST_KEY_CFBundleDisplayName = "Curfew Dev";/);
  assert.doesNotMatch(project, /PRODUCT_BUNDLE_IDENTIFIER = studio\.hypertext\.apps\.curfew\.studio\.dev/);
});

test('Consolidated Dev retains the installed account access group and widget data', () => {
  const app = plist('Curfew/Curfew.entitlements');
  const widget = plist('CurfewWidget/CurfewWidget-Debug.entitlements');
  assert.deepEqual(app['keychain-access-groups'], ['$(AppIdentifierPrefix)studio.hypertext.curfew.studio.dev']);
  assert.deepEqual(app['com.apple.security.application-groups'], ['group.studio.hypertext.curfew.studio.dev']);
  assert.deepEqual(widget['com.apple.security.application-groups'], app['com.apple.security.application-groups']);
  assert.deepEqual(app['com.apple.developer.associated-domains'], [
    'applinks:curfew-account-staging.hypertext.studio',
    'webcredentials:curfew-account-staging.hypertext.studio',
  ]);
});

test('There are two runtime flavors, with explicit storage compatibility independent of display names', () => {
  const flavor = read('CurfewKit/Sources/CurfewKit/Settings/CurfewFlavor.swift');
  assert.doesNotMatch(flavor, /case studioDevelopment/);
  assert.match(flavor, /var storageIdentifierSuffix: String/);
  assert.match(flavor, /var storageDisplaySuffix: String/);
  const paths = read('CurfewKit/Sources/CurfewKit/Settings/SharedPaths.swift');
  assert.doesNotMatch(paths, /flavor\.displaySuffix|current\.displaySuffix|flavor\.identifierSuffix|current\.identifierSuffix/);
});

test('Capture entrypoints build isolated unsigned fixtures and never stop installed Curfew', () => {
  for (const name of ['scripts/capture-marketing.sh', 'scripts/capture-video.sh']) {
    const script = read(name);
    assert.match(script, /CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO/);
    assert.match(script, /derivedDataPath build\/capture/);
    assert.doesNotMatch(script, /pkill/);
  }
});

test('Incremental builds refresh embedded helpers and their launch registration', () => {
  const phase = /9BD3FBCC2F4D4584007B2E95 \/\* Bundle CLI Tools \*\/ = \{([\s\S]*?)\n\t\t\};/.exec(project)?.[1];
  assert.ok(phase);
  assert.match(phase, /alwaysOutOfDate = 1;/);
  assert.match(project, /CURFEW_DAEMON_PLIST_NAME = studio\.hypertext\.apps\.curfew\.dev\.daemon\.plist;/);
});
