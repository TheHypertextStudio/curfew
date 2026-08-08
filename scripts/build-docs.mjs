#!/usr/bin/env node
// Builds the Mintlify project in docs/ into the marketing site's `landing/`
// tree so curfew.hypertext.studio/docs is served by the same Cloudflare Pages
// deploy as the marketing page. Run it before `wrangler pages deploy landing`.
//
// Mintlify's own hosting serves a subpath only behind a reverse proxy, which
// would mean a second platform in front of a site that is already static. The
// CLI's `mint export` emits a self-contained Next.js static site instead, so
// the only work left is to move it under /docs.
//
// Two transforms make that work:
//
//   1. Rebase. Every URL the export emits is root-absolute (`/_next/…`,
//      `/mcp`). Mounted at /docs they would resolve against the marketing
//      site. Each one is rewritten to `/docs/…`. The prefixes come from the
//      export's own top-level entries, so a page added to docs.json is picked
//      up without touching this script. The rewrite has to step around the
//      length-prefixed rows in Next.js's inlined RSC payload — see
//      scripts/lib/rebase-export.mjs.
//
//   2. Flatten. `mint export` writes `mcp/index.html`. Cloudflare Pages
//      answers `/docs/mcp` from that only after a 308 to `/docs/mcp/`, which
//      does not match the extensionless links the export emits. Written as
//      `mcp.html` instead, Pages serves `/docs/mcp` directly with a 200.
//
// Usage: node scripts/build-docs.mjs [--keep-temp]

import { execFileSync } from 'node:child_process';
import {
  cpSync,
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  readdirSync,
  renameSync,
  rmSync,
  statSync,
  writeFileSync
} from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

import { assertFlightIntact, rebase } from './lib/rebase-export.mjs';

const repoRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const docsSource = join(repoRoot, 'docs');
const landing = join(repoRoot, 'landing');
const outputDirectory = join(landing, 'docs');
const outputHome = join(landing, 'docs.html');
const basePath = '/docs';
const keepTemp = process.argv.includes('--keep-temp');

// Shipped by `mint export` for running the docs off a local filesystem. They
// have no meaning on a hosted site.
const LOCAL_SERVE_ARTIFACTS = ['serve.js', 'Start Docs.command', 'Start Docs.bat'];

function log(message) {
  process.stdout.write(`build-docs: ${message}\n`);
}

function exportDocs(destination) {
  const archive = join(destination, 'export.zip');
  log('running mint export (this pulls the Mintlify CLI on first run)');
  execFileSync('npx', ['--yes', 'mint@latest', 'export', '--output', archive], {
    cwd: docsSource,
    stdio: 'inherit'
  });
  const unpacked = join(destination, 'site');
  mkdirSync(unpacked, { recursive: true });
  execFileSync('unzip', ['-q', archive, '-d', unpacked]);
  return unpacked;
}

// The set of path prefixes that live at the export's root. Anything matching
// one of these has to move under `basePath`.
function rootPrefixes(site) {
  const prefixes = new Set();
  for (const entry of readdirSync(site)) {
    if (entry.startsWith('.') || LOCAL_SERVE_ARTIFACTS.includes(entry)) {
      continue;
    }
    prefixes.add(entry);
    if (entry.endsWith('.html')) {
      prefixes.add(entry.slice(0, -5));
    }
  }
  // `index` is the home page's alias, and it is deleted before this runs.
  prefixes.delete('index');
  // Emitted as links but not as files. Rebasing them keeps the docs from
  // pointing at marketing-site paths that will never exist.
  prefixes.add('llms.txt');
  prefixes.add('sitemap.xml');
  return [...prefixes].sort((a, b) => b.length - a.length);
}

// `page/index.html` -> `page.html`, so Pages serves /docs/page with a 200
// rather than redirecting to /docs/page/.
function flatten(site) {
  let flattened = 0;
  const directories = readdirSync(site).filter((entry) => {
    if (entry === '_next') {
      return false;
    }
    return statSync(join(site, entry)).isDirectory();
  });
  for (const directory of directories) {
    const nested = join(site, directory, 'index.html');
    if (!existsSync(nested)) {
      continue;
    }
    renameSync(nested, join(site, `${directory}.html`));
    const remaining = readdirSync(join(site, directory));
    if (remaining.length === 0) {
      rmSync(join(site, directory), { recursive: true });
    }
    flattened += 1;
  }
  return flattened;
}

function install(site) {
  rmSync(outputDirectory, { recursive: true, force: true });
  rmSync(outputHome, { force: true });
  mkdirSync(outputDirectory, { recursive: true });

  for (const entry of readdirSync(site)) {
    if (entry === 'index.html') {
      // The docs home is served at /docs, which Pages answers from
      // landing/docs.html. It cannot also be landing/docs/index.html, or the
      // two compete for the same path.
      cpSync(join(site, entry), outputHome);
      continue;
    }
    cpSync(join(site, entry), join(outputDirectory, entry), { recursive: true });
  }
}

function main() {
  if (!existsSync(join(docsSource, 'docs.json'))) {
    throw new Error(`no docs.json in ${docsSource}`);
  }

  const temp = mkdtempSync(join(tmpdir(), 'curfew-docs-'));
  try {
    const site = exportDocs(temp);

    for (const artifact of LOCAL_SERVE_ARTIFACTS) {
      rmSync(join(site, artifact), { force: true });
    }
    // A duplicate of the home page reachable at /index. Dropping it keeps
    // /docs unambiguous.
    rmSync(join(site, 'index'), { recursive: true, force: true });

    const prefixes = rootPrefixes(site);
    log(`rebasing onto ${basePath}: ${prefixes.join(', ')}`);
    log(`rewrote ${rebase(site, prefixes, basePath)} files`);
    assertFlightIntact(site);
    log(`flattened ${flatten(site)} page directories`);

    install(site);

    const pages = readdirSync(outputDirectory)
      .filter((entry) => entry.endsWith('.html'))
      .map((entry) => `${basePath}/${entry.slice(0, -5)}`);
    log(`wrote ${relative(repoRoot, outputHome)} and ${pages.length} more pages`);
    log(`pages: ${basePath}, ${pages.join(', ')}`);
  } finally {
    if (keepTemp) {
      log(`kept ${temp}`);
    } else {
      rmSync(temp, { recursive: true, force: true });
    }
  }
}

main();
