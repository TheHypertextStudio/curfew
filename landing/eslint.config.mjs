import node from '@thehypertextstudio/web-config/eslint/node';
export default [
  ...node,
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
