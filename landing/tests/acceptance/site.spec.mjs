import { expect, test } from '@playwright/test';

test('retained routes and HTML aliases survive direct visits and refresh', async ({ page }) => {
  for (const name of ['privacy', 'terms', 'security', 'retention', 'refund', 'docs', 'success']) {
    for (const suffix of ['', '.html']) {
      const response = await page.goto(`/${name}${suffix}`);
      expect([200, 304], `${name}${suffix}`).toContain(response.status());
      await expect(page.locator('main h1')).toBeVisible();
    }
    expect([200, 304]).toContain((await page.reload()).status());
  }
});

test('marketing content, download boundaries and original styles remain', async ({ page }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'A hard stop for your Mac.' })).toBeVisible();
  await expect(page.locator('.nav-account')).toHaveAttribute('href', '/account');
  await expect(page.locator('#download')).toContainText('Android support is coming soon.');
  expect(
    await page.locator('body').evaluate((node) => getComputedStyle(node).fontFamily),
  ).toContain('sans-serif');
  expect(await page.locator('.lockout-shot').evaluate((node) => node.naturalWidth)).toBeGreaterThan(
    0,
  );
  expect(await page.locator('script').count()).toBe(3);
});

test('existing HTML guide keeps anchors and navigation history', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('link', { name: 'Docs', exact: true }).click();
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

test('license delivery fails safely without contacting or mutating the licensing backend', async ({
  page,
}) => {
  const requests = [];
  page.on('request', (request) => {
    if (request.resourceType() === 'fetch' || request.resourceType() === 'xhr')
      requests.push(request.url());
  });
  await page.goto('/success?session_id=test-not-a-real-checkout');
  await expect(page.locator('#state-error')).toBeVisible();
  await expect(page.locator('#error-detail')).toContainText(
    'License delivery is not configured yet.',
  );
  expect(requests).toEqual([]);
});

test('keyboard access and reduced motion use the same real links', async ({
  page,
  browserName,
}) => {
  await page.emulateMedia({ reducedMotion: 'reduce' });
  await page.goto('/');
  // WebKit on macOS uses Option+Tab to include links when Full Keyboard Access is off.
  const nextLink = browserName === 'webkit' ? 'Alt+Tab' : 'Tab';
  await page.keyboard.press(nextLink);
  await expect(page.locator('.nav-account')).toBeFocused();
  await page.keyboard.press(nextLink);
  await page.keyboard.press(nextLink);
  await expect(page.getByRole('link', { name: 'Download free', exact: true })).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(page).toHaveURL(/#download$/);
});

test('unknown URLs remain 404', async ({ request }) => {
  expect((await request.get('/this-route-does-not-exist')).status()).toBe(404);
});
