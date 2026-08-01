import assert from "node:assert/strict";
import { access, mkdtemp, readFile, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import { spawnSync } from "node:child_process";

test("keygen writes a private seed only to the caller-selected mode-600 path", async () => {
  const directory = await mkdtemp(join(tmpdir(), "curfew-license-test-"));
  const privateKeyFile = join(directory, "license-private.seed");

  try {
    const result = spawnSync(
      process.execPath,
      ["scripts/license-worker.mjs", "keygen", "--private-key-file", privateKeyFile],
      { encoding: "utf8" }
    );

    assert.equal(result.status, 0, result.stderr);
    assert.match(result.stdout, /^CURFEW_LICENSE_PUBLIC_KEY=[A-Za-z0-9+/]{43}=$/m);
    assert.match(await readFile(privateKeyFile, "utf8"), /^[A-Za-z0-9_-]{43}$/);
    assert.equal((await stat(privateKeyFile)).mode & 0o777, 0o600);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("config validation fails closed when required deployment values are absent", () => {
  const result = spawnSync(process.execPath, ["scripts/license-worker.mjs", "validate-config"], {
    encoding: "utf8",
    env: {},
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /missing required configuration/);
});

test("rendered config resolves the Worker entry point from a caller-selected path", async () => {
  const directory = await mkdtemp(join(tmpdir(), "curfew-license-config-test-"));
  const configFile = join(directory, "wrangler.toml");

  try {
    const result = spawnSync(
      process.execPath,
      ["scripts/license-worker.mjs", "render-config", "--output", configFile],
      {
        encoding: "utf8",
        env: {
          CURFEW_LICENSE_WORKER_NAME: "curfew-license",
          CURFEW_LICENSE_KV_NAMESPACE_ID: "00000000000000000000000000000000",
          CURFEW_LICENSE_HOSTNAME: "license.example.com",
        },
      }
    );

    assert.equal(result.status, 0, result.stderr);
    assert.match(
      await readFile(configFile, "utf8"),
      /^main = ".*\/web\/worker\/src\/index\.ts"$/m
    );
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("workers.dev staging config omits production custom-domain routing", async () => {
  const directory = await mkdtemp(join(tmpdir(), "curfew-license-workers-dev-test-"));
  const configFile = join(directory, "wrangler.toml");

  try {
    const result = spawnSync(
      process.execPath,
      ["scripts/license-worker.mjs", "render-config", "--workers-dev", "--output", configFile],
      {
        encoding: "utf8",
        env: {
          CURFEW_LICENSE_WORKER_NAME: "curfew-license-staging",
          CURFEW_LICENSE_KV_NAMESPACE_ID: "00000000000000000000000000000000",
          CURFEW_LICENSE_HOSTNAME: "curfew-license-staging.example.workers.dev",
        },
      }
    );

    assert.equal(result.status, 0, result.stderr);
    const config = await readFile(configFile, "utf8");
    assert.match(config, /^workers_dev = true$/m);
    assert.doesNotMatch(config, /^routes = /m);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("only the envelope-v2 Worker bootstrap remains deployable", async () => {
  for (const legacyPath of [
    "scripts/issue-license.ts",
    "scripts/gen-license-keypair.sh",
    "wrangler.toml",
  ]) {
    await assert.rejects(access(legacyPath));
  }
  await access("scripts/license-worker.mjs");
  await access("web/worker/wrangler.toml.example");
});
