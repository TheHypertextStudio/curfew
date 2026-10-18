import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const read = path => readFileSync(new URL(`../${path}`, import.meta.url), 'utf8');

test('Protection is named in navigation and removal is outside technical details', () => {
  assert.match(read('Curfew/UI/SettingsSection.swift'), /case \.general: "Protection"/);
  const panel = read('Curfew/UI/SettingsView+PrivilegedHelperPanel.swift');
  const details = panel.indexOf('DisclosureGroup("Details")');
  const removal = panel.indexOf('Button("Remove Background Protection…")');
  assert.ok(removal >= 0 && removal < details, 'Removal must be visible before collapsed details');
});
