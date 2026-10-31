import assert from 'node:assert/strict';
import test from 'node:test';
import * as acceptance from './signed-installer-acceptance.mjs';

const candidate = Object.freeze({
  version: '0.0.17',
  sourceCommit: 'a'.repeat(40),
  dmgSHA256: 'b'.repeat(64),
});
function evidence() {
  return {
    schemaVersion: 1,
    scope: 'signed-warning-lockout-override',
    subject: { ...candidate },
    bundleIdentifier: 'studio.hypertext.apps.curfew',
    runner: {
      githubActions: 'true',
      username: 'runner',
      home: '/Users/runner',
      temporary: '/Users/runner/work/_temp',
    },
    observations: {
      warning: { phase: 'warning' },
      locked: { phase: 'locked' },
      afterShortHold: { phase: 'locked' },
      afterOverride: { phase: 'working' },
    },
    uptime: {
      warning: 100,
      locked: 160,
      cooldownStarted: 161,
      cooldownReady: 462,
      shortHoldEnded: 463,
      overrideGranted: 468,
    },
    shortHoldSeconds: 0.25,
    confirmationHoldSeconds: 3.25,
    warningTimerVisible: true,
    lockoutVisible: true,
    confirmationInitiallyDisabled: true,
    stillLockedAfterShortHold: true,
    overlayDismissedAfterOverride: true,
    sideEffects: {
      directSettingsWrites: false,
      permissionGrantPerformed: false,
      clockChanged: false,
      demoFixtureUsed: false,
    },
  };
}
function verify(value, subject = candidate) {
  assert.equal(
    typeof acceptance.validateSignedEnforcementReceipt,
    'function',
    'The signed-enforcement driver needs a fail-closed evidence validator',
  );
  return acceptance.validateSignedEnforcementReceipt(value, subject);
}
test('signed enforcement admits exact healthy observations after the real cooldown and hold', () => {
  assert.doesNotThrow(() => verify(evidence()));
});
for (const [name, mutate] of [
  [
    'another source artifact',
    (r) => {
      r.subject.dmgSHA256 = 'c'.repeat(64);
    },
  ],
  [
    'a personal host',
    (r) => {
      r.runner.username = 'owner';
    },
  ],
  [
    'degraded protection behind a visible overlay',
    (r) => {
      r.observations.locked.phase = 'unknown';
      r.observations.locked.unavailable_reason = 'enforcement_degraded';
    },
  ],
  [
    'a shortened five-minute cooldown',
    (r) => {
      r.uptime.cooldownReady = 460;
    },
  ],
  [
    'a short confirmation hold',
    (r) => {
      r.confirmationHoldSeconds = 2.99;
    },
  ],
  [
    'unlocking after the short hold',
    (r) => {
      r.observations.afterShortHold.phase = 'working';
    },
  ],
  [
    'an overlay that never dismissed',
    (r) => {
      r.overlayDismissedAfterOverride = false;
    },
  ],
  [
    'granting Accessibility in the driver',
    (r) => {
      r.sideEffects.permissionGrantPerformed = true;
    },
  ],
  [
    'changing the host clock in this case',
    (r) => {
      r.sideEffects.clockChanged = true;
    },
  ],
  [
    'substituting a demo fixture',
    (r) => {
      r.sideEffects.demoFixtureUsed = true;
    },
  ],
  [
    'nonmonotonic observations',
    (r) => {
      r.uptime.overrideGranted = 450;
    },
  ],
]) {
  test(`signed enforcement rejects ${name}`, () => {
    const value = evidence();
    mutate(value);
    assert.equal(
      typeof acceptance.validateSignedEnforcementReceipt,
      'function',
      'Missing signed-enforcement validator',
    );
    assert.throws(() => acceptance.validateSignedEnforcementReceipt(value, candidate));
  });
}
