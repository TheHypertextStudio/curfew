#!/usr/bin/env node
import { createRequire } from 'node:module';
const require = createRequire(new URL('../web/worker/package.json', import.meta.url));
const manifest = require('./package.json');
const { version } = require('sql-formatter/package.json');
if (version !== manifest.devDependencies['sql-formatter'])
  throw new Error('Install the pinned license SQL formatter');
const { format } = require('sql-formatter');
process.stdin.setEncoding('utf8');
let source = '';
for await (const chunk of process.stdin) source += chunk;
process.stdout.write(
  format(source, { language: 'sqlite', tabWidth: 2, keywordCase: 'upper' }) + '\n',
);
