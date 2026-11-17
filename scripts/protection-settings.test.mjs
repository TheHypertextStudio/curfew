import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('Protection is named in navigation and the Curfew helper can be removed, but not during a lock', () => {
  assert.match(read('Curfew/UI/SettingsSection.swift'), /case \.general: "Protection"/);
  const panel = read('Curfew/UI/SettingsView+CurfewHelperPanel.swift');
  const removal = panel.indexOf('title: "Remove the Curfew helper"');
  assert.ok(removal >= 0, 'The Curfew helper group offers removal');
  assert.match(
    panel.slice(removal),
    /\.disabled\(isLocked\)/,
    'Removal is unavailable during a lock',
  );
});
