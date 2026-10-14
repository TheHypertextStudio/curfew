import { defineConfig } from 'astro/config';
import { loadEnvironment } from '../scripts/deployment-config.mjs';
const deployment = await loadEnvironment(process.env.CURFEW_DEPLOYMENT_MODE || 'production');
export default defineConfig({
  site: deployment.siteOrigin,
  output: 'static',
  build: { format: 'file' },
  trailingSlash: 'never',
  compressHTML: false,
});
