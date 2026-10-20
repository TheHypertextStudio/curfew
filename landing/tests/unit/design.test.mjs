import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

test('landing uses the shared Curfew design and work-life balance story', async () => {
  const page = await readFile(new URL('../../src/pages/index.astro', import.meta.url), 'utf8');
  const content = await readFile(new URL('../../src/content/home.html', import.meta.url), 'utf8');
  const tokens = await readFile(
    new URL('../../public/site-assets/design/tokens.css', import.meta.url),
    'utf8',
  );
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

test('download entry explains availability before sending visitors to GitHub', async () => {
  const home = await readFile(new URL('../../src/content/home.html', import.meta.url), 'utf8');
  const download = await readFile(
    new URL('../../src/content/download.html', import.meta.url),
    'utf8',
  );
  assert.match(home, /href="\/download"/);
  assert.match(download, /public Mac download is coming soon/i);
  for (const source of [home, download]) {
    assert.doesNotMatch(
      source,
      /releases\/latest|Download for Mac|Download the latest Mac release/,
    );
  }
});

test('the app pricing link has a visible Plus availability destination', async () => {
  const home = await readFile(new URL('../../src/content/home.html', import.meta.url), 'utf8');
  assert.match(home, /<article id="plus">/);
  assert.match(home, /Plus is not available for purchase yet/);
});

test('guide links point to published Mintlify pages', async () => {
  const home = await readFile(new URL('../../src/content/home.html', import.meta.url), 'utf8');
  const support = await readFile(
    new URL('../../src/content/support.html', import.meta.url),
    'utf8',
  );
  const download = await readFile(
    new URL('../../src/content/download.html', import.meta.url),
    'utf8',
  );
  const components = await readFile(
    new URL('../../public/site-assets/design/components.mjs', import.meta.url),
    'utf8',
  );
  const docs = JSON.parse(
    await readFile(new URL('../../../web/docs/docs.json', import.meta.url), 'utf8'),
  );
  const published = new Set(docs.navigation.groups.flatMap((group) => group.pages));
  const links = [home, support, download, components].flatMap((source) =>
    [...source.matchAll(/href=["'](https:\/\/curfew\.mintlify\.site\/docs(?:\/[^"']*)?)["']/g)].map(
      (match) => new URL(match[1]),
    ),
  );
  assert.ok(links.length >= 9, 'all prominent guide links use Mintlify');
  for (const link of links) {
    const slug = link.pathname.slice('/docs/'.length);
    if (slug && slug !== '/docs') assert.ok(published.has(slug), `missing guide: ${slug}`);
  }
  for (const source of [home, support, download, components]) {
    assert.doesNotMatch(source, /href=["']\/docs(?:\/|["'])/);
  }
});
