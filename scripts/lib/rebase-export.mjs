// Rewrites the root-absolute URLs in a `mint export` tree so the site can be
// mounted at a subpath such as /docs.
//
// The hard part is the React Server Components payload that Next.js inlines
// into every page as a series of `self.__next_f.push([1,"…"])` calls. That
// payload is a flight stream of newline-delimited rows, and its text rows
// carry a length prefix:
//
//     44:Tee2,"use strict";const{Fragment:_Fragment,…
//
// Those rows hold the page's compiled MDX, which is what the client actually
// renders, so the links inside them have to be rewritten too and the length
// prefix has to be corrected to match. `0xee2` counts **UTF-8 bytes**, not
// JavaScript characters. Docs prose is full of em dashes, arrows, and the
// command glyph, so the two differ; a parser that assumes characters walks
// off the end of the first non-ASCII row, misses every row after it, and
// corrupts the stream. The page then renders Mintlify's "Error loading page"
// where the docs should be.
//
// So the payload is parsed in byte space, rewritten row by row, and re-emitted
// with corrected lengths. `parse` returns nothing unless the rows it produced
// reassemble into the original payload exactly, and `assertFlightIntact`
// re-checks every page afterwards, so a future Next.js that changes the
// stream shape fails the build instead of shipping a blank docs site.

import { readFileSync, readdirSync, statSync, writeFileSync } from 'node:fs';
import { extname, join } from 'node:path';

const REWRITABLE = new Set(['.html', '.js', '.mjs', '.css', '.json', '.txt', '.md', '.xml']);
const PUSH_PATTERN = /self\.__next_f\.push\(\[1,("(?:[^"\\]|\\.)*")\]\)/g;

const NEWLINE = 0x0a;
const COLON = 0x3a;
const COMMA = 0x2c;
const CAPITAL_T = 0x54;

export function walk(directory, accumulator = []) {
  for (const entry of readdirSync(directory)) {
    const path = join(directory, entry);
    if (statSync(path).isDirectory()) {
      walk(path, accumulator);
    } else {
      accumulator.push(path);
    }
  }
  return accumulator;
}

function replacer(prefixes, basePath) {
  const patterns = prefixes.map((prefix) => {
    const escaped = prefix.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    // Only match where a URL can begin — after a quote, a backtick, an
    // opening paren, or an `=`. A bare "/mcp" in prose must stay put.
    return [new RegExp(`(["'\`(=])\\/${escaped}(?=["'\`)/?#]|$)`, 'g'), `$1${basePath}/${prefix}`];
  });
  return (text) => {
    let out = text;
    for (const [pattern, replacement] of patterns) {
      out = out.replace(pattern, replacement);
    }
    // The docs home is linked as a bare root path.
    return out.replace(/(href=)(["'])\/\2/g, `$1$2${basePath}$2`);
  };
}

/// Re-encodes a payload chunk as a JS string literal safe to sit inside an
/// inline `<script>`. `JSON.stringify` alone is not enough: Next.js escapes
/// `<`, `>`, `&`, and the two Unicode line separators, and dropping that
/// escaping would let a `</script>` in the data terminate the script early.
function encodeChunk(chunk) {
  return JSON.stringify(chunk)
    .replace(/</g, '\\u003c')
    .replace(/>/g, '\\u003e')
    .replace(/&/g, '\\u0026')
    .replace(/\u2028/g, '\\u2028')
    .replace(/\u2029/g, '\\u2029');
}

function serialize(rows) {
  let out = '';
  for (const row of rows) {
    out += row.text
      ? `${row.header}${Buffer.byteLength(row.body, 'utf8').toString(16)},${row.body}`
      : row.body;
    if (row.newline) {
      out += '\n';
    }
  }
  return out;
}

/// Splits a flight payload into rows, working in bytes. Returns null unless
/// the rows reassemble into `buffer` exactly.
function parse(buffer) {
  const rows = [];
  let index = 0;
  while (index < buffer.length) {
    const colon = buffer.indexOf(COLON, index);
    if (colon < 0) {
      return null;
    }
    if (buffer[colon + 1] === CAPITAL_T) {
      const comma = buffer.indexOf(COMMA, colon + 2);
      if (comma < 0) {
        return null;
      }
      const length = Number.parseInt(buffer.toString('utf8', colon + 2, comma), 16);
      if (!Number.isFinite(length)) {
        return null;
      }
      const bodyStart = comma + 1;
      const bodyEnd = bodyStart + length;
      if (bodyEnd > buffer.length) {
        return null;
      }
      rows.push({
        text: true,
        header: buffer.toString('utf8', index, colon + 2),
        body: buffer.toString('utf8', bodyStart, bodyEnd),
        // The final row can arrive without its terminating newline.
        newline: buffer[bodyEnd] === NEWLINE
      });
      index = bodyEnd + (buffer[bodyEnd] === NEWLINE ? 1 : 0);
    } else {
      const newline = buffer.indexOf(NEWLINE, colon);
      const end = newline < 0 ? buffer.length : newline;
      rows.push({
        text: false,
        body: buffer.toString('utf8', index, end),
        newline: newline >= 0
      });
      index = end + (newline >= 0 ? 1 : 0);
    }
  }
  return serialize(rows) === buffer.toString('utf8') ? rows : null;
}

function payloadOf(html) {
  PUSH_PATTERN.lastIndex = 0;
  const pushes = [...html.matchAll(PUSH_PATTERN)];
  return { pushes, payload: pushes.map((match) => JSON.parse(match[1])).join('') };
}

function rewriteHTML(html, rewrite) {
  const { pushes, payload } = payloadOf(html);
  if (pushes.length === 0) {
    return rewrite(html);
  }

  const rows = parse(Buffer.from(payload, 'utf8'));
  // Without a trustworthy parse, leave the payload alone. The page still
  // renders; only the rewrite inside it is skipped, and assertFlightIntact
  // still guards the result.
  const updated = rows
    ? serialize(rows.map((row) => ({ ...row, body: rewrite(row.body) })))
    : payload;

  // Correcting a length prefix moves every byte after it, so the original
  // chunk boundaries no longer hold. The stream is reassembled by plain
  // concatenation, so one chunk carrying everything is equivalent.
  let result = '';
  let last = 0;
  pushes.forEach((match, index) => {
    result += rewrite(html.slice(last, match.index));
    if (index === 0) {
      result += `self.__next_f.push([1,${encodeChunk(updated)}])`;
    }
    last = match.index + match[0].length;
  });
  return result + rewrite(html.slice(last));
}

/// Rewrites every text file under `site`. Returns the number changed.
export function rebase(site, prefixes, basePath) {
  const rewrite = replacer(prefixes, basePath);
  let changed = 0;
  for (const file of walk(site)) {
    if (!REWRITABLE.has(extname(file))) {
      continue;
    }
    const original = readFileSync(file, 'utf8');
    const updated = extname(file) === '.html' ? rewriteHTML(original, rewrite) : rewrite(original);
    if (updated !== original) {
      writeFileSync(file, updated);
      changed += 1;
    }
  }
  return changed;
}

/// Throws when a page's flight payload no longer parses, which means a row
/// length stopped matching its body.
export function assertFlightIntact(site) {
  for (const file of walk(site)) {
    if (extname(file) !== '.html') {
      continue;
    }
    const { pushes, payload } = payloadOf(readFileSync(file, 'utf8'));
    if (pushes.length === 0) {
      continue;
    }
    if (!parse(Buffer.from(payload, 'utf8'))) {
      throw new Error(`${file}: RSC flight payload does not round-trip after rewriting`);
    }
  }
}
