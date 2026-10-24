import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const landing = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const root = path.resolve(landing, '..');

test('landing and staged commits use the same Astro formatter release', async () => {
  const require = createRequire(path.join(landing, 'package.json'));
  const entry = require.resolve('@thehypertextstudio/web-config/prettier/astro');
  const preset = JSON.parse(
    await readFile(path.resolve(path.dirname(entry), '../package.json'), 'utf8'),
  );
  const tools = JSON.parse(
    await readFile(path.join(root, '.hypertext/formatter-tools/tools.json'), 'utf8'),
  );
  assert.equal(
    tools.npm['prettier-plugin-astro'],
    preset.dependencies['prettier-plugin-astro'],
    'the staged formatter must use the installed shared Astro preset release',
  );
});
