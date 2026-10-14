import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
const url = new URL("./check-deployment-hosts.mjs", import.meta.url);
test("source guard catches deployment literals without banning unrelated Studio services", async () => {
  await assert.doesNotReject(() => readFile(url));
  const { deploymentHostLiterals } = await import(url.href);
  assert.deepEqual(
    deploymentHostLiterals('const x="https://sync.thecurfew.app/mcp";'),
    ["sync.thecurfew.app"],
  );
  assert.deepEqual(
    deploymentHostLiterals('let x = "https://curfew-license.hypertext.studio"'),
    ["curfew-license.hypertext.studio"],
  );
  assert.deepEqual(
    deploymentHostLiterals(
      'const studio="https://hypertext.studio"; const docket="https://docket-staging.hypertext.studio";',
    ),
    [],
  );
});
