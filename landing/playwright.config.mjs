import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { acceptanceConfig } from '@thehypertextstudio/web-config/playwright';
export default acceptanceConfig({
  baseURL: 'http://127.0.0.1:4325',
  testDir: './tests/acceptance',
  outputDir: '../test-results/website',
  webServer: {
    cwd: path.dirname(fileURLToPath(import.meta.url)),
    command:
      process.env.CURFEW_WEBSITE_PREVIEW === 'astro'
        ? 'ASTRO_DEV_BACKGROUND=1 pnpm dev --port 4325'
        : 'pnpm --dir hosting exec cf dev --mode local --port 4325',
    url: 'http://127.0.0.1:4325',
    reuseExistingServer: false,
    timeout: 60000,
  },
});
