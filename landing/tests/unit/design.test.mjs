import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('landing uses the shared Curfew design and work-life balance story', async () => {
  const page = await readFile(new URL('../../src/pages/index.astro', import.meta.url), 'utf8');
  const content = await readFile(new URL('../../src/content/home.html', import.meta.url), 'utf8');
  const tokens = await readFile(new URL('../../public/design/tokens.css', import.meta.url), 'utf8');
  assert.match(page, /Call it a day\./);
  assert.match(content, /work leaves room for the rest of your life/);
  assert.match(content, /Claude, ChatGPT, or Codex/);
  assert.doesNotMatch(content, /mcp-controls(?:-compact|-dark)?\.png|assistant-example/);
  assert.match(tokens, /--brand-orange/);
});

test('legal pages use the same design shell while retaining their policy text', async () => {
  for (const name of ['privacy', 'terms', 'refund', 'security', 'retention']) {
    const page = await readFile(new URL(`../../src/pages/${name}.astro`, import.meta.url), 'utf8');
    assert.match(page, /Experience/);
    const content = await readFile(
      new URL(`../../src/content/${name}.html`, import.meta.url),
      'utf8',
    );
    assert.match(content, /<h1/);
  }
});

test('primary navigation destinations have real pages', async () => {
  for (const name of ['download', 'support']) {
    const page = await readFile(new URL(`../../src/pages/${name}.astro`, import.meta.url), 'utf8');
    assert.match(page, /Experience/);
  }
});
