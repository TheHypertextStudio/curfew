import { defineWranglerConfig } from 'wrangler/experimental-config';

export default defineWranglerConfig((ctx) => ({
  assetsDirectory:
    ctx.mode === 'production'
      ? process.env.CURFEW_WEBSITE_ASSETS_DIRECTORY || '../dist'
      : '../dist',
}));
