import node from '@thehypertextstudio/web-config/eslint/node';
import browser from '@thehypertextstudio/web-config/eslint/browser';
export default [
  ...node,
  ...browser.map((config) => ({ ...config, files: ['public/purchase.js'] })),
  {
    ignores: [
      'node_modules/**',
      'landing/dist/**',
      'landing/.astro/**',
      'landing/build/**',
      'build/**',
    ],
  },
];
