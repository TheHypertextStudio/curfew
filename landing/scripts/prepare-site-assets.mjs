import { cpSync, existsSync, lstatSync, mkdirSync, readdirSync, rmSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const landing = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
if (args.length > 1 || (args.length === 1 && args[0] !== '--pages')) {
  throw new Error('Expected no arguments or --pages');
}
const pages = args[0] === '--pages';
const output = path.join(landing, pages ? '.pages-output' : '.site-assets');
// The physical Pages files remain canonical until its publisher is retired.
// Copy only public inputs, never the frontend toolchain, source, or prior builds.
rmSync(output, { recursive: true, force: true });
mkdirSync(output, { recursive: true });
const required = ['images', 'style.css', 'sky.js', 'reveal.js', 'robots.txt', 'sitemap.xml'];
if (pages) {
  required.push(
    'index.html',
    'docs.html',
    'mcp.html',
    'privacy.html',
    'refund.html',
    'retention.html',
    'security.html',
    'success.html',
    'terms.html',
    'functions',
  );
}
function validateInput(source) {
  const entry = lstatSync(source);
  if (entry.isSymbolicLink()) throw new Error(`Public input must not be a symlink: ${source}`);
  if (entry.isDirectory()) {
    for (const name of readdirSync(source).sort()) validateInput(path.join(source, name));
  } else if (!entry.isFile()) {
    throw new Error(`Public input must be a regular file: ${source}`);
  }
}
for (const name of [
  ...required,
  '_headers',
  '_redirects',
  '_routes.json',
  '404.html',
  'appcast.xml',
]) {
  const source = path.join(landing, name);
  if (!existsSync(source)) {
    if (required.includes(name)) throw new Error(`Missing canonical public input: ${name}`);
    continue;
  }
  validateInput(source);
  cpSync(source, path.join(output, name), { recursive: true });
}
