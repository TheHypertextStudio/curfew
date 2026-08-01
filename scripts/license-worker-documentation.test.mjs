import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const operatorDocs = await Promise.all([
  "scripts/release-checklist.md",
  "Documentation/todos.md",
  "Documentation/todo-test-matrix.md",
  "Documentation/RELEASE.md",
].map(path => readFile(path, "utf8")));

test("operator docs name only the envelope-v2 issuer bootstrap", () => {
  const text = operatorDocs.join("\n");
  assert.match(text, /scripts\/license-worker\.mjs/);
  assert.match(text, /web\/worker\/wrangler\.toml\.example/);
  assert.doesNotMatch(text, /scripts\/issue-license\.ts/);
  assert.doesNotMatch(text, /scripts\/gen-license-keypair\.sh/);
  assert.doesNotMatch(text, /licensePublicKeyBase64/);
  assert.doesNotMatch(text, /REPLACE_WITH_CURFEW_PRO_PAYMENT_LINK/);
});
