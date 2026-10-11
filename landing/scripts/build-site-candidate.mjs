import { execFileSync } from 'node:child_process';
import { cpSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const output = path.join(root, 'landing/build/site-candidate');
execFileSync('pnpm', ['site:build'], { cwd: root, stdio: 'inherit' });
execFileSync('python3', ['scripts/site-parity.py'], { cwd: root, stdio: 'inherit' });
rmSync(output, { recursive: true, force: true });
mkdirSync(output, { recursive: true });
execFileSync(
  'pnpm',
  [
    'exec',
    'wrangler',
    'deploy',
    '--dry-run',
    '--config',
    'wrangler.site.json',
    '--env',
    'staging',
    '--outdir',
    path.join(output, 'modules'),
  ],
  {
    cwd: path.join(root, 'landing'),
    stdio: 'inherit',
    env: {
      ...process.env,
      WRANGLER_SEND_METRICS: 'false',
      CLOUDFLARE_LOAD_DEV_VARS_FROM_DOT_ENV: 'false',
    },
  },
);
cpSync(path.join(root, 'landing/dist'), path.join(output, 'assets'), { recursive: true });
const config = JSON.parse(readFileSync(path.join(root, 'landing/wrangler.site.json'), 'utf8'));
delete config.$schema;
config.main = 'modules/worker.js';
config.no_bundle = true;
config.assets.directory = 'assets';
writeFileSync(path.join(output, 'wrangler.site.json'), `${JSON.stringify(config, null, 2)}\n`);
console.log('Prebuilt site candidate assembled; no provider deployment performed.');
