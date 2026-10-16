import test from "node:test";
import assert from "node:assert/strict";
import {
  mkdtemp,
  mkdir,
  copyFile,
  writeFile,
  readFile,
  rm,
} from "node:fs/promises";
import { join, delimiter } from "node:path";
import { tmpdir } from "node:os";
import { spawnSync } from "node:child_process";

async function setupFixture(t, key, args) {
  const root = await mkdtemp(join(tmpdir(), "curfew-setup-plan-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const path of ["scripts", "deployment/generated", "web/worker", "bin"]) {
    await mkdir(join(root, path), { recursive: true });
  }
  await copyFile(
    new URL("./setup.mjs", import.meta.url),
    join(root, "scripts/setup.mjs"),
  );
  await writeFile(
    join(root, "deployment/generated/environments.mjs"),
    `export default { production: { siteOrigin: 'https://account.example.net', purchasePortalOrigin: 'https://website.example.net', licenseOrigin: 'https://license.example.net' } };`,
  );
  await writeFile(
    join(root, "bin/pnpm"),
    `#!/usr/bin/env node
import { appendFileSync } from 'node:fs';
appendFileSync(${JSON.stringify(join(root, "provider-commands"))}, JSON.stringify(process.argv.slice(2)) + '\\n');
console.log('Hypertext Studio 00000000000000000000000000000000');
`,
    { mode: 0o755 },
  );
  const result = spawnSync(
    process.execPath,
    [join(root, "scripts/setup.mjs"), ...args],
    {
      cwd: root,
      encoding: "utf8",
      env: {
        PATH: join(root, "bin") + delimiter + process.env.PATH,
        STRIPE_API_KEY: key,
        SKIP_WORKER: "1",
        SKIP_KEYPAIR: "1",
        SKIP_STRIPE: "1",
      },
    },
  );
  return { result, root };
}

test("production setup review names the purchase website's checkout confirmation", async (t) => {
  const { result } = await setupFixture(t, "sk_live_fixture", ["--live"]);
  assert.equal(result.status, 0, result.stderr);
  assert.ok(
    result.stdout.includes(
      "https://website.example.net/success.html?session_id={CHECKOUT_SESSION_ID}",
    ),
  );
  assert.ok(
    !result.stdout.includes("https://account.example.net/success.html"),
  );
});

test("the legacy production bootstrap rejects test payment credentials before provider access", async (t) => {
  const { result, root } = await setupFixture(t, "sk_test_fixture", ["--yes"]);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /production.*test|test.*production/i);
  await assert.rejects(readFile(join(root, "provider-commands")), {
    code: "ENOENT",
  });
});
