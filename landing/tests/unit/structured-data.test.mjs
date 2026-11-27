import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { homeStructuredData } from '../../src/lib/structured-data.mjs';

const siteOrigin = 'https://thecurfew.app';
const home = await readFile(new URL('../../src/content/home.html', import.meta.url), 'utf8');
const visibleQuestions = [...home.matchAll(/<summary>\s*([^<]+?)\s*<svg/g)].map(
  (match) => match[1],
);

const graph = () => JSON.parse(homeStructuredData({ siteOrigin, content: home }))['@graph'];
const node = (type) => graph().find((entry) => entry['@type'] === type);

test('the home page describes Curfew as a free macOS app on its own site', () => {
  const app = node('SoftwareApplication');
  assert.equal(app.name, 'Curfew');
  assert.equal(app.operatingSystem, 'macOS 26');
  assert.equal(app.url, `${siteOrigin}/`);
  assert.equal(app.downloadUrl, `${siteOrigin}/download`);
  assert.equal(app.license, 'https://opensource.org/license/mit');
  assert.equal(app.publisher.name, 'Hypertext Studio');
  assert.ok(app.screenshot.startsWith(`${siteOrigin}/`));
  assert.deepEqual(app.offers, [{ '@type': 'Offer', price: '0', priceCurrency: 'USD' }]);
  assert.match(home, /Curfew Plus is not available for\s+purchase yet/);
});

test('the FAQ data repeats exactly the questions the page shows', () => {
  const faq = node('FAQPage').mainEntity;
  assert.ok(visibleQuestions.length > 0, 'the home page must show its FAQ');
  assert.deepEqual(
    faq.map((entry) => entry.name),
    visibleQuestions,
  );
  for (const entry of faq) {
    assert.equal(entry['@type'], 'Question');
    assert.equal(entry.acceptedAnswer['@type'], 'Answer');
    assert.ok(entry.acceptedAnswer.text.length > 0);
    assert.doesNotMatch(entry.acceptedAnswer.text, /[<>]|&amp;|\s{2}/);
  }
  const install = faq.find((entry) => entry.name === 'How do I install it?');
  assert.match(install.acceptedAnswer.text, /Check the download page for availability/);
});

test('the serialized data cannot close its script element early', () => {
  const content = home.replace(
    'No. You can set',
    'No. </script><script>alert(1)</script> You can set',
  );
  const serialized = homeStructuredData({ siteOrigin, content });
  assert.doesNotMatch(serialized, /</);
  assert.match(JSON.parse(serialized)['@graph'][1].mainEntity[2].acceptedAnswer.text, /<\/script>/);
});

test('the home layout publishes the data and other pages do not', async () => {
  const layout = await readFile(
    new URL('../../src/layouts/Experience.astro', import.meta.url),
    'utf8',
  );
  assert.match(layout, /homeStructuredData\(/);
  assert.match(layout, /type="application\/ld\+json"/);
  assert.match(layout, /home && content/);
});
