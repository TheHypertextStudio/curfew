import { expect, test } from '@playwright/test';

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
  expect(
    await page.locator('.schedule-image').evaluate((node) => node.naturalWidth),
  ).toBeGreaterThan(0);
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
  await page.route('https://curfew-license.hypertext.studio/**', (route) => {
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
  await page.route('https://curfew-license.hypertext.studio/license/activation', (route) => {
    expect(route.request().postDataJSON()).toEqual({ session_id: 'cs_test_purchase' });
    return route.fulfill({ json: { license_key: 'signed-purchase-key', activation_token: token } });
  });
  await page.goto('/success?session_id=cs_test_purchase');
  await expect(page.getByRole('link', { name: 'Activate in Curfew', exact: true })).toHaveAttribute(
    'href',
    `curfew://activate?token=${token}`,
  );
  await expect(page.locator('#license-key')).not.toBeVisible();
  await page.getByText('Enter a license key', { exact: true }).click();
  await expect(page.locator('#license-key')).toHaveText('signed-purchase-key');
});

test('a pending purchase retries delivery and then offers activation', async ({ page }) => {
  let attempts = 0;
  await page.route('https://curfew-license.hypertext.studio/license/activation', (route) => {
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
  await page.route('https://curfew-license.hypertext.studio/license/activation', (route) =>
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
  await page.route('https://curfew-license.hypertext.studio/license/restore', (route) => {
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
    `curfew://activate?token=${token}`,
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
  await expect(page.getByRole('link', { name: 'Download for Mac' }).first()).toBeFocused();
});

test('unknown URLs remain 404', async ({ request }) => {
  expect((await request.get('/this-route-does-not-exist')).status()).toBe(404);
});
