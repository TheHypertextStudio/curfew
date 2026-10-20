import { defineConfig } from 'astro/config';
import { cp } from 'node:fs/promises';
import { loadEnvironment } from '../scripts/deployment-config.mjs';
const deployment = await loadEnvironment(process.env.CURFEW_DEPLOYMENT_MODE || 'production');
export default defineConfig({
  site: deployment.siteOrigin,
  output: 'static',
  build: { format: 'file' },
  trailingSlash: 'never',
  compressHTML: false,
  integrations: [
    {
      name: 'curfew-site-assets',
      hooks: {
        'astro:build:done': async ({ dir }) => {
          await cp(new URL('site-assets/design/', dir), new URL('design/', dir), {
            recursive: true,
          });
        },
      },
    },
  ],
});
