import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const landing = path.join(root, 'landing');

async function html(name) {
  return readFile(path.join(landing, 'src/pages', name.replace(/\.html$/, '.astro')), 'utf8');
}

function compact(source) {
  return source.replace(/\s+/g, ' ');
}

test('every public page header offers the same account entry point', async () => {
  const names = (await readdir(path.join(landing, 'src/pages'))).filter((name) => name.endsWith('.astro')).map((name) => name.replace(/\.astro$/, '.html'));
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

test('the download surface announces Android without claiming it is available', async () => {
  const source = await html('index.html');
  const download = source.match(/<section class="download(?: [^"\n]*)?"[^>]*>[\s\S]*?<\/section>/)?.[0] ?? '';
  assert.match(download, /Android support is coming soon\./);
  assert.doesNotMatch(download, /download[^<]*Android/i);
});

test('account-era legal pages state the privacy, security, recovery, and purchase boundaries', async () => {
  const privacy = compact(await html('privacy.html'));
  const terms = compact(await html('terms.html'));
  const security = compact(await html('security.html'));
  const retention = compact(await html('retention.html'));

  assert.match(privacy, /Accounts are optional\./);
  assert.match(privacy, /end-to-end encrypted/i);
  assert.match(privacy, /unavoidable metadata/i);
  assert.match(privacy, /Google Play Services/i);
  assert.match(privacy, /remote unlock/i);
  assert.match(terms, /lifetime license or subscription/i);
  assert.match(terms, /payment processor/i);
  assert.doesNotMatch(terms, /merchant of record/i);
  assert.match(security, /backup codes recover sign-in only/i);
  assert.match(security, /Curfew Recovery Key/i);
  assert.match(security, /fresh two-factor authentication/i);
  assert.match(retention, /delete your Curfew account/i);
  assert.match(retention, /export/i);
});
