import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// Astro builds run from the landing package root. Read source bytes before
// publishing; the helper itself is never shipped to the browser.
export function stylesheet(name) {
  const bytes = readFileSync(resolve('public', name));
  const version = createHash('sha256').update(bytes).digest('hex').slice(0, 12);
  return `/${name}?v=${version}`;
}
