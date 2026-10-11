import { defineConfig } from 'astro/config';
export default defineConfig({
  site: 'https://curfew.hypertext.studio',
  output: 'static',
  build: { format: 'file' },
  trailingSlash: 'never',
  compressHTML: false,
});
