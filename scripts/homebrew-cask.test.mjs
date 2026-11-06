import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { createHash } from 'node:crypto';
import { updateCask } from './update-homebrew-cask.mjs';

const bytes = Buffer.from('retained release DMG bytes');
const digest = createHash('sha256').update(bytes).digest('hex');
const release = {
  tagName: 'v0.0.16',
  isPrerelease: false,
  isDraft: false,
  assets: [
    {
      name: 'Curfew-v0.0.16.dmg',
      digest: `sha256:${digest}`,
      url: 'https://github.com/TheHypertextStudio/curfew/releases/download/v0.0.16/Curfew-v0.0.16.dmg',
    },
  ],
};

test('cask updates use verified release bytes and stabilize on repeat execution', async () => {
  const source = await readFile('Casks/curfew.rb', 'utf8');
  const result = updateCask(source, release, bytes);
  assert.match(result, /version "0.0.16"/);
  assert.ok(result.includes(`sha256 "${digest}"`));
  assert.equal(updateCask(result, release, bytes), result);
  assert.ok(result.includes('must_succeed: true'));
  assert.throws(() => updateCask(source, release, Buffer.from('changed')), /checksum/i);
  assert.throws(() => updateCask(source, { ...release, isPrerelease: true }, bytes), /published/i);
});

test('the Homebrew cask installs a released, checksum-pinned app and its CLI', async () => {
  const cask = await readFile('Casks/curfew.rb', 'utf8');
  assert.doesNotMatch(cask, /REPLACE_WITH|Submission checklist/);
  assert.match(cask, /sha256 "[a-f0-9]{64}"/);
  assert.match(cask, /binary "#\{appdir\}\/Curfew\.app\/Contents\/Resources\/curfew-ctl"/);
  assert.match(cask, /binary "#\{appdir\}\/Curfew\.app\/Contents\/Resources\/curfew-mcp"/);
});
