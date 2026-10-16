import { expect, test } from '@playwright/test';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';

const purchase =
  process.env.CURFEW_PURCHASE_TEST_MODE === 'staging'
    ? { issuer: 'https://curfew-license-staging.hypertext.studio', scheme: 'curfew-studio-dev' }
    : { issuer: 'https://license.thecurfew.app', scheme: 'curfew' };
test.beforeEach(async ({ page }) => {
  await page.route('**/license/**', (route) => route.abort());
});

test('retained routes and HTML aliases survive direct visits and refresh', async ({ page }) => {
  for (const name of [
    'privacy',
    'terms',
    'security',
    'retention',
    'refund',
    'docs',
    'success',
    'download',
    'support',
  ]) {
    for (const suffix of ['', '.html']) {
      const response = await page.goto(`/${name}${suffix}`);
      expect([200, 304], `${name}${suffix}`).toContain(response.status());
      await expect(page.locator('main h1')).toBeVisible();
    }
    expect([200, 304]).toContain((await page.reload()).status());
  }
});

test('the landing communicates the curfew and retains the shared design', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Call it a day.' })).toBeVisible();
  await expect(page.getByRole('link', { name: 'Account', exact: true })).toHaveAttribute(
    'href',
    '/account',
  );
  await expect(page.getByText(/Cross-platform sync is coming soon/)).toBeVisible();
  expect(await page.locator('h1').evaluate((node) => getComputedStyle(node).fontFamily)).toContain(
    'Calistoga',
  );
  await page.locator('.schedule-image').scrollIntoViewIfNeeded();
  await expect
    .poll(() => page.locator('.schedule-image').evaluate((node) => node.naturalWidth))
    .toBeGreaterThan(0);
  await expect(page.locator('.assistant-example')).toHaveCount(0);
});

test('published guides are linked and the retained HTML guide keeps its anchors', async ({
  page,
}) => {
  await page.goto('/');
  await expect(page.getByRole('link', { name: 'Guides', exact: true }).first()).toHaveAttribute(
    'href',
    'https://curfew.mintlify.site/docs',
  );
  await page.goto('/docs');
  await expect(page.locator('#claude-desktop')).toBeVisible();
  await page.locator('.docs-sidebar a[href="#command-line"]').click();
  await expect(page).toHaveURL(/#command-line$/);
  await page.goBack();
  await expect(page).toHaveURL(/\/docs(?:\.html)?$/);
  await page.goBack();
  await expect(page).toHaveURL(/\/$/);
  await page.goForward();
  await expect(page.locator('#overview')).toBeVisible();
});

test('an invalid purchase link fails without contacting the licensing backend', async ({
  page,
}) => {
  let requested = false;
  await page.route('**/license/**', (route) => {
    requested = true;
    return route.abort();
  });
  await page.goto('/success?session_id=invalid');
  await expect(page.locator('#state-error')).toBeVisible();
  expect(requested).toBe(false);
});

test('a paid confirmation offers one activation click and a separate manual-key fallback', async ({
  page,
}) => {
  const token = 'a'.repeat(43);
  await page.route(`${purchase.issuer}/license/activation`, (route) => {
    expect(route.request().postDataJSON()).toEqual({ session_id: 'cs_test_purchase' });
    return route.fulfill({ json: { license_key: 'signed-purchase-key', activation_token: token } });
  });
  await page.goto('/success?session_id=cs_test_purchase');
  await expect(page.getByRole('link', { name: 'Activate in Curfew', exact: true })).toHaveAttribute(
    'href',
    `${purchase.scheme}://activate?token=${token}`,
  );
  await expect(page.locator('#license-key')).not.toBeVisible();
  await page.getByText('Enter a license key', { exact: true }).click();
  await expect(page.locator('#license-key')).toHaveText('signed-purchase-key');
});

test('a pending purchase retries delivery and then offers activation', async ({ page }) => {
  let attempts = 0;
  await page.route(`${purchase.issuer}/license/activation`, (route) => {
    attempts += 1;
    return route.fulfill(
      attempts === 1
        ? { status: 404, json: { error: 'purchase_pending' } }
        : { json: { license_key: 'signed-purchase-key', activation_token: 'b'.repeat(43) } },
    );
  });
  await page.goto('/success?session_id=cs_test_purchase');
  await expect(page.getByRole('link', { name: 'Activate in Curfew', exact: true })).toBeVisible();
  expect(attempts).toBe(2);
});

test('service failure offers retry without claiming the purchase is processing', async ({
  page,
}) => {
  await page.route(`${purchase.issuer}/license/activation`, (route) =>
    route.fulfill({ status: 503, json: { error: 'unavailable' } }),
  );
  await page.goto('/success?session_id=cs_test_purchase');
  await expect(page.locator('#state-error')).toBeVisible();
  await expect(page.locator('#error-detail')).toContainText("Couldn't reach the purchase service");
  await expect(
    page.getByRole('link', { name: 'Activate in Curfew', exact: true }),
  ).not.toBeVisible();
});

test('restore requests proof at the purchase inbox and keeps its link out of server requests', async ({
  page,
}) => {
  await page.route(`${purchase.issuer}/license/restore`, (route) => {
    expect(route.request().postDataJSON()).toEqual({ email: 'buyer@example.com' });
    return route.fulfill({ status: 202, json: { status: 'check_email' } });
  });
  await page.goto('/restore');
  await page.getByLabel('Purchase email').fill('buyer@example.com');
  await page.getByRole('button', { name: 'Send Restore Link', exact: true }).click();
  await expect(page.getByRole('status')).toContainText('Check buyer@example.com');
  const token = 'c'.repeat(43);
  await page.goto(`/restore#token=${token}`);
  await expect(page.getByRole('link', { name: 'Restore in Curfew', exact: true })).toHaveAttribute(
    'href',
    `${purchase.scheme}://activate?token=${token}`,
  );
  await expect(page).not.toHaveURL(/token=/);
});

test('keyboard access and reduced motion use the same real links', async ({
  page,
  browserName,
}) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  // WebKit on macOS uses Option+Tab to include links when Full Keyboard Access is off.
  const nextLink = browserName === 'webkit' ? 'Alt+Tab' : 'Tab';
  const account = page.getByRole('link', { name: 'Account', exact: true });
  await account.focus();
  await expect(account).toBeFocused();
  await page.keyboard.press(nextLink);
  await expect(page.getByRole('link', { name: 'Read the changes', exact: true })).toBeFocused();
  await page.keyboard.press(nextLink);
  await expect(page.getByRole('link', { name: 'Get Curfew', exact: true })).toBeFocused();
});

test('the app Plus link reaches visible availability information', async ({ page }) => {
  await page.goto('/#plus');
  const heading = page.getByRole('heading', { name: 'Curfew Plus', exact: true });
  await expect(heading).toBeVisible();
  await expect
    .poll(() =>
      heading.evaluate((node) => {
        const bounds = node.getBoundingClientRect();
        return bounds.top >= 0 && bounds.bottom <= innerHeight;
      }),
    )
    .toBe(true);
  await expect(page.locator('#plus')).toContainText('Plus is not available for purchase yet.');
});

test('unknown URLs remain 404', async ({ request }) => {
  for (const path of ['/this-route-does-not-exist', '/missing/nested/page']) {
    const response = await request.get(path);
    expect(response.status()).toBe(404);
    const html = await response.text();
    expect(html).toContain('<title>404: Page not found — Curfew</title>');
    expect(html).toContain('<a href="/" rel="home">Home</a>');
  }
});

test('current policies expose the notice, official contact, and preserved refund promise', async ({
  page,
}) => {
  await page.goto('/');
  await expect(page.getByRole('complementary', { name: 'Policy update' })).toContainText(
    'November 13',
  );
  for (const name of ['privacy', 'terms', 'refund', 'retention']) {
    await page.goto(`/${name}`);
    await expect(page.getByRole('complementary', { name: 'Policy update' })).toBeVisible();
    await expect(page.locator('main .policy-header h1')).toBeVisible();
    await expect(
      page.locator('main .policy-header .policy-meta time[datetime="2026-10-14"]'),
    ).toHaveCount(1);
    await expect(page.locator('main .policy-header .privacy-lede')).not.toContainText('Published');
    await expect(page.locator('main a[href="mailto:legal@hypertext.studio"]')).toHaveCount(1);
    await expect(page.locator('main')).toContainText('1810 East Sahara Avenue STE75246');
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    ).toBe(true);
  }
  await page.goto('/refund');
  await expect(page.locator('main')).toContainText('most recent renewal charge');
  await expect(page.locator('main')).toContainText('14 days');
  await expect(page.locator('main')).toContainText('not remotely revocable');
  await page.locator('main a[href="/legal/history"]').first().click();
  await expect(page.getByRole('heading', { name: 'Policy history', exact: true })).toBeVisible();
});

test('policy history routes render previous documents with their original contacts', async ({
  page,
}) => {
  await page.goto('/legal/history');
  for (const name of ['privacy', 'terms', 'refund', 'retention']) {
    const response = await page.goto(`/legal/history/2026-10-13/${name}`);
    expect(response.status()).toBe(200);
    await expect(page.locator('main h1')).toBeVisible();
    await expect(page.locator('main')).toContainText('Archived policy.');
    await expect(
      page.locator('main a[href="mailto:hello@hypertext.studio"]').first(),
    ).toBeVisible();
    await page.locator(`main a[href="/${name}"]`).click();
    await expect(page.getByRole('complementary', { name: 'Policy update' })).toBeVisible();
  }
});

test('legal notices and history remain usable on narrow screens', async ({ page }) => {
  for (const width of [320, 390]) {
    await page.setViewportSize({ width, height: 844 });
    for (const name of ['privacy', 'terms', 'refund', 'retention', 'legal/history']) {
      await page.goto(`/${name}`);
      await expect(page.locator('main h1')).toBeVisible();
      expect(
        await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
      ).toBe(true);
    }
    await page.goto('/legal/history/2026-10-13/privacy');
    const tables = page.locator('.privacy-table');
    for (const [index, labels] of [
      [0, ['Data', 'Where', 'Retention']],
      [1, ['Permission', 'Why']],
    ]) {
      const firstRow = tables.nth(index).locator('tbody tr').first();
      for (const label of labels) {
        await expect(firstRow.getByText(label, { exact: true })).toBeVisible();
      }
    }
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    ).toBe(true);
    await page.goto('/retention');
    await page.locator('details summary').click();
    await expect(page.locator('details')).toHaveAttribute('open', '');
    expect(
      await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth),
    ).toBe(true);
  }
});

test('product help and general inquiries use separate mail links', async ({ page }) => {
  await page.goto('/support');
  for (const email of [
    'support@thecurfew.app',
    'contact@thecurfew.app',
    'legal@hypertext.studio',
  ]) {
    await expect(page.locator(`main a[href="mailto:${email}"]`)).toBeVisible();
  }
  await page.goto('/security');
  await expect(page.locator('main a[href="mailto:support@thecurfew.app"]')).toBeVisible();
  await page.goto('/success');
  await expect(page.locator('#state-error a[href="mailto:support@thecurfew.app"]')).toBeVisible();
  for (const policy of ['privacy', 'terms', 'refund', 'retention']) {
    await page.goto(`/${policy}`);
    await expect(page.locator('main a[href="mailto:support@thecurfew.app"]').first()).toBeVisible();
    await expect(page.locator('main a[href="mailto:contact@thecurfew.app"]')).toBeVisible();
    await expect(page.locator('main a[href="mailto:legal@hypertext.studio"]')).toBeVisible();
  }
});

test('home policy announcement clears the header and hero at desktop and mobile sizes', async ({
  page,
}) => {
  for (const width of [1920, 390, 320]) {
    await page.setViewportSize({ width, height: 1080 });
    await page.goto('/');
    const version = createHash('sha256')
      .update(await readFile(new URL('../../public/curfew.css', import.meta.url)))
      .digest('hex')
      .slice(0, 12);
    await expect(page.locator('link[href^="/curfew.css"]')).toHaveAttribute(
      'href',
      `/curfew.css?v=${version}`,
    );
    const header = await page.locator('.site-header').boundingBox();
    const notice = await page.getByRole('complementary', { name: 'Policy update' }).boundingBox();
    const hero = await page.locator('.hero').boundingBox();
    expect(notice.y, `notice clears header at ${width}px`).toBeGreaterThanOrEqual(
      header.y + header.height,
    );
    expect(hero.y, `hero clears announcement at ${width}px`).toBeGreaterThanOrEqual(
      notice.y + notice.height,
    );
    const announcement = page.getByRole('complementary', { name: 'Policy update' });
    expect(await announcement.evaluate((node) => getComputedStyle(node).borderTopWidth)).toBe(
      '0px',
    );
    await expect(announcement.locator('time[datetime="2026-10-14"]')).toHaveCount(1);
    await expect(announcement.locator('time[datetime="2026-11-13"]')).toHaveCount(1);
    const link = page.getByRole('link', { name: 'Read the changes', exact: true });
    expect(await link.evaluate((node) => getComputedStyle(node).textDecorationLine)).toContain(
      'underline',
    );
    await link.focus();
    await expect(link).toBeFocused();
    await link.click();
    await expect(page.getByRole('heading', { name: 'Policy history', exact: true })).toBeVisible();
  }
});
