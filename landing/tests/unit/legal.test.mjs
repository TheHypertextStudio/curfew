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

test('current policies and help pages use product contact roles without replacing legal notices', async () => {
  for (const name of ['privacy', 'terms', 'refund', 'retention']) {
    const policy = await content(name);
    assert.match(policy, /mailto:support@thecurfew\.app/);
    assert.match(policy, /mailto:contact@thecurfew\.app/);
    assert.match(policy, /mailto:legal@hypertext\.studio/);
    assert.doesNotMatch(policy, /hello@hypertext\.studio/);
  }
  const support = await content('support');
  assert.match(support, /mailto:support@thecurfew\.app/);
  assert.match(support, /mailto:contact@thecurfew\.app/);
  assert.match(support, /mailto:legal@hypertext\.studio/);
  assert.match(await content('security'), /mailto:support@thecurfew\.app/);
  const success = await readFile(new URL('../../src/pages/success.astro', import.meta.url), 'utf8');
  assert.match(success, /mailto:support@thecurfew\.app/);
  assert.doesNotMatch(success, /hello@hypertext\.studio/);
});

test('mobile policy tables retain column labels alongside every value', async () => {
  const { labelPolicyTables } = await import('../../src/lib/policy-tables.mjs');
  const source =
    '<table class="privacy-table"><thead><tr><th>Data</th><th>Where</th><th>Retention</th></tr></thead><tbody><tr><td>Activity</td><td>On device</td><td>52 weeks</td></tr><tr><td>Settings</td><td>Preferences</td><td>Until removed</td></tr></tbody></table>';
  const rendered = labelPolicyTables(source);
  for (const label of ['Data', 'Where', 'Retention']) {
    assert.equal(
      rendered.split(`<span class="cell-label" aria-hidden="true">${label}</span>`).length - 1,
      2,
    );
  }
  assert.match(
    rendered,
    /<thead><tr><th>Data<\/th><th>Where<\/th><th>Retention<\/th><\/tr><\/thead>/,
  );
  assert.match(rendered, /52 weeks/);
  assert.equal(labelPolicyTables('<p>No table here.</p>'), '<p>No table here.</p>');
  const permissions =
    '<table class="privacy-table"><thead><tr><th>Permission</th><th>Why</th></tr></thead><tbody><tr><td>Calendars</td><td>Show events</td></tr></tbody></table>';
  assert.match(labelPolicyTables(permissions), /aria-hidden="true">Why<\/span>Show events/);
});

test('current policy headings group their readable publication metadata', async () => {
  for (const name of ['privacy', 'terms', 'refund', 'retention']) {
    const policy = await content(name);
    const header = policy.match(/<header class="policy-header">.*?<\/header>/)?.[0];
    assert.ok(header, `${name} has a grouped policy header`);
    assert.match(header, /<h1>/);
    assert.match(header, /class="policy-meta"/);
    assert.equal((header.match(/datetime="2026-10-14"/g) ?? []).length, 1);
    assert.match(header, /href="\/legal\/history"/);
    assert.doesNotMatch(header.match(/class="privacy-lede">.*?<\/p>/)?.[0] ?? '', /Published/);
  }
});
