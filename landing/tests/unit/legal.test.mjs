import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const content = async (name) =>
  (await readFile(new URL(`../../src/content/${name}.html`, import.meta.url), 'utf8')).replace(
    /\s+/g,
    ' ',
  );

test('policies identify the operator, official contact, notice, and history', async () => {
  for (const name of ['privacy', 'terms', 'refund', 'retention']) {
    const policy = await content(name);
    assert.match(policy, /Hypertext Studio/);
    assert.match(policy, /mailto:legal@hypertext\.studio/);
    assert.match(policy, /1810 East Sahara Avenue STE75246/);
    assert.match(policy, /href="\/legal\/history"/);
    assert.match(policy, /October 14, 2026/);
  }
  assert.match(await content('terms'), /November 13, 2026/);
});

test('terms preserve purchases, open-source rights, and mandatory consumer rights', async () => {
  const terms = await content('terms');
  assert.match(terms, /MIT/);
  assert.match(terms, /lifetime license does not expire/i);
  assert.match(terms, /amount you paid for your license/);
  assert.match(terms, /16/);
  assert.match(terms, /Clark County, Nevada/);
  assert.match(terms, /home jurisdiction/);
  assert.match(terms, /does not retrospectively/);
});

test('refunds cover renewal charges and offline honor-system keys', async () => {
  const refund = await content('refund');
  assert.match(refund, /14 days/);
  assert.match(refund, /most recent renewal/);
  assert.match(refund, /not remotely revocable/);
  assert.match(refund, /stop using.*delete the key/);
});

test('privacy explains task review transfer and avoids unconditional deletion promises', async () => {
  const privacy = await content('privacy');
  const retention = await content('retention');
  assert.match(privacy, /Docket and Athena/);
  assert.match(privacy, /query strings.*fragments/);
  assert.match(privacy, /assistant.*own service/);
  assert.match(retention, /52 weeks/);
  assert.match(retention, /365 days/);
  assert.match(retention, /30 days after/);
  assert.match(retention, /during the deletion request/);
  assert.doesNotMatch(retention, /queued for deletion|temporary hold|within 30 days/);
});

test('native history routes preserve all prior documents', async () => {
  const index = await readFile(
    new URL('../../src/pages/legal/history/index.astro', import.meta.url),
    'utf8',
  );
  assert.match(index, /Experience/);
  for (const name of ['privacy', 'terms', 'refund', 'retention']) {
    const page = await readFile(
      new URL(`../../src/pages/legal/history/2026-10-13/${name}.astro`, import.meta.url),
      'utf8',
    );
    assert.match(page, /content\/legal-history/);
    assert.ok(
      (
        await readFile(
          new URL(`../../src/content/legal-history/2026-10-13/${name}.html`, import.meta.url),
          'utf8',
        )
      ).length > 500,
    );
    assert.match(index, new RegExp(`/legal/history/2026-10-13/${name}`));
  }
});

test('local MCP disclosure includes schedules, budgets, activity and device-attributed summaries', async () => {
  const privacy = await content('privacy');
  const disclosure = privacy.match(/<p>When you run local.*?<\/p>/)?.[0];
  assert.ok(disclosure, 'local assistant disclosure exists');
  for (const category of [
    /schedules/,
    /budgets/,
    /current-week activity/,
    /weekly summaries/,
    /device names/,
    /device attribution/,
    /reflections/,
    /enforcement state/,
  ]) {
    assert.match(disclosure, category);
  }
});

test('organization purchasers must also satisfy the adult purchase requirement', async () => {
  const terms = await content('terms');
  const eligibility = terms.match(/<h2>Eligibility<\/h2>.*?<h2>/)?.[0];
  assert.ok(eligibility, 'eligibility section exists');
  assert.match(
    eligibility,
    /Purchases must be made by an adult[^.]*contractual capacity[^.]*authority/,
  );
  assert.match(eligibility, /organization[^.]*also[^.]*authorized/);
  assert.doesNotMatch(eligibility, /or someone authorized/);
});
