import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const landing = path.join(root, 'landing');

async function html(name) {
  return readFile(path.join(landing, 'src/pages', name.replace(/\.html$/, '.astro')), 'utf8');
}

function compact(source) {
  return source.replace(/\s+/g, ' ');
}

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

test('every public page header offers the same account entry point', async () => {
  const sharedHeader = await readFile(
    path.join(landing, 'public/site-assets/design/components.mjs'),
    'utf8',
  );
  assert.ok(sharedHeader.includes('href="/account"'));
  const names = (await readdir(path.join(landing, 'src/pages')))
    .filter((name) => name.endsWith('.astro'))
    .map((name) => name.replace(/\.astro$/, '.html'));
  for (const name of names) {
    const source = await html(name);
    if (!source.includes('<header class="site-header">')) continue;
    assert.match(
      source,
      /<a class="nav-account" href="\/account">Open Account<\/a>/,
      `${name} must link to the same-origin account portal`,
    );
  }
});

test('the product story describes current Mac support and future cross-platform sync', async () => {
  const source = await readFile(path.join(landing, 'src/content/home.html'), 'utf8');
  assert.match(source, /available for Mac only/);
  assert.match(source, /Cross-platform functionality is coming/);
  assert.doesNotMatch(source, /download[^<]*Android/i);
});

test('account-era legal pages state the privacy, security, recovery, and purchase boundaries', async () => {
  const policy = async (name) =>
    compact(await readFile(path.join(landing, 'src/content', name + '.html'), 'utf8'));
  const privacy = await policy('privacy');
  const terms = await policy('terms');
  const security = await policy('security');
  const retention = await policy('retention');

  assert.match(privacy, /Accounts are optional\./);
  assert.match(privacy, /end-to-end encrypted/i);
  assert.match(
    privacy,
    /account identity, purchase records, device connections, and security activity/i,
  );
  assert.match(privacy, /Cloudflare forwards support email to Google Workspace/i);
  assert.match(privacy, /remote unlock/i);
  assert.match(terms, /lifetime license or subscription/i);
  assert.match(terms, /Stripe handles payment details and receipts/i);
  assert.doesNotMatch(terms, /merchant of record/i);
  assert.match(security, /backup codes recover sign-in only/i);
  assert.match(security, /Curfew Recovery Key/i);
  assert.match(security, /fresh two-factor authentication/i);
  assert.match(retention, /delete your Curfew account/i);
  assert.match(retention, /export/i);
});
