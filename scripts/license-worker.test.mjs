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
          CURFEW_LICENSE_HOSTNAME: "curfew-license.hypertext.studio",
          CURFEW_LICENSE_STRIPE_MODE: "live",
        },
      }
    );

    assert.equal(result.status, 0, result.stderr);
    const config = await readFile(configFile, "utf8");
    assert.match(config, /STRIPE_MODE = "live"/);
    assert.match(config, /^main = ".*\/web\/worker\/src\/index\.ts"$/m);
    assert.match(config, /^routes = \[\{ pattern = "curfew-license\.hypertext\.studio", custom_domain = true \}\]$/m);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("staging also uses an approved curfew-prefixed Hypertext Studio hostname", async () => {
  const directory = await mkdtemp(join(tmpdir(), "curfew-license-staging-test-"));
  const configFile = join(directory, "wrangler.toml");

  try {
    const result = spawnSync(
      process.execPath,
      ["scripts/license-worker.mjs", "render-config", "--output", configFile],
      {
        encoding: "utf8",
        env: {
          CURFEW_LICENSE_WORKER_NAME: "curfew-license-staging",
          CURFEW_LICENSE_KV_NAMESPACE_ID: "00000000000000000000000000000000",
          CURFEW_LICENSE_HOSTNAME: "curfew-license-staging.hypertext.studio",
          CURFEW_LICENSE_STRIPE_MODE: "test",
        },
      }
    );

    assert.equal(result.status, 0, result.stderr);
    const config = await readFile(configFile, "utf8");
    assert.match(config, /STRIPE_MODE = "test"/);
    assert.match(config, /^routes = \[\{ pattern = "curfew-license-staging\.hypertext\.studio", custom_domain = true \}\]$/m);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test("config validation rejects hostnames outside the Curfew service namespace", () => {
  const result = spawnSync(process.execPath, ["scripts/license-worker.mjs", "validate-config"], {
    encoding: "utf8",
    env: {
      CURFEW_LICENSE_WORKER_NAME: "curfew-license",
      CURFEW_LICENSE_KV_NAMESPACE_ID: "00000000000000000000000000000000",
      CURFEW_LICENSE_HOSTNAME: "license.example.com",
      CURFEW_LICENSE_STRIPE_MODE: "test",
    },
  });

  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /approved deployment manifest/);
});

test("the retired workers.dev rendering mode is rejected", async () => {
  const directory = await mkdtemp(join(tmpdir(), "curfew-license-retired-route-test-"));
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
          CURFEW_LICENSE_HOSTNAME: "curfew-license-staging.hypertext.studio",
          CURFEW_LICENSE_STRIPE_MODE: "test",
        },
      },
    );
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /workers.dev routing is not supported/);
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

test("license bootstrap accepts the hostname selected by the production manifest", () => {
  const result = spawnSync(process.execPath, ["scripts/license-worker.mjs", "validate-config"], {
    encoding: "utf8",
    env: { CURFEW_LICENSE_WORKER_NAME: "curfew-issue-license", CURFEW_LICENSE_KV_NAMESPACE_ID: "4313ea07769f4578a8fdd412620a412e", CURFEW_LICENSE_HOSTNAME: "license.thecurfew.app", CURFEW_LICENSE_STRIPE_MODE: "live" },
  });
  assert.equal(result.status, 0, result.stderr);
});

test("recovery deployment fails closed until its sender, portal, and rate limits are selected", async () => {
  const directory = await mkdtemp(join(tmpdir(), "curfew-recovery-config-"));
  const configFile = join(directory, "wrangler.toml");
  try {
    const result = spawnSync(process.execPath, ["scripts/license-worker.mjs", "render-config", "--output", configFile], {
      encoding: "utf8", env: {
        CURFEW_LICENSE_WORKER_NAME: "curfew-issue-license",
        CURFEW_LICENSE_KV_NAMESPACE_ID: "00000000000000000000000000000000",
        CURFEW_LICENSE_HOSTNAME: "curfew-license.hypertext.studio",
        CURFEW_LICENSE_STRIPE_MODE: "live",
        CURFEW_LICENSE_RESTORE_ENABLED: "1",
      },
    });
    assert.notEqual(result.status, 0);
    await assert.rejects(access(configFile));
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test("recovery deployment renders a restricted sender and both environment-specific rate limits", async () => {
  const directory = await mkdtemp(join(tmpdir(), "curfew-recovery-config-"));
  const configFile = join(directory, "wrangler.toml");
  try {
    const result = spawnSync(process.execPath, ["scripts/license-worker.mjs", "render-config", "--output", configFile], {
      encoding: "utf8", env: {
        CURFEW_LICENSE_WORKER_NAME: "curfew-issue-license",
        CURFEW_LICENSE_KV_NAMESPACE_ID: "00000000000000000000000000000000",
        CURFEW_LICENSE_HOSTNAME: "curfew-license.hypertext.studio",
        CURFEW_LICENSE_STRIPE_MODE: "live",
        CURFEW_LICENSE_RESTORE_ENABLED: "1",
        CURFEW_LICENSE_RESTORE_FROM: "purchases@curfew.hypertext.studio",
        CURFEW_LICENSE_PORTAL_URL: "https://curfew.hypertext.studio",
        CURFEW_LICENSE_RESTORE_IP_NAMESPACE_ID: "1781921001",
        CURFEW_LICENSE_RESTORE_EMAIL_NAMESPACE_ID: "1781921002",
      },
    });
    assert.equal(result.status, 0, result.stderr);
    const config = await readFile(configFile, "utf8");
    assert.match(config, /allowed_sender_addresses = \["purchases@curfew.hypertext.studio"\]/);
    assert.match(config, /PURCHASE_PORTAL_URL = "https:\/\/curfew.hypertext.studio"/);
    assert.match(config, /name = "RESTORE_IP_LIMIT"\nnamespace_id = "1781921001"\nsimple = \{ limit = 5, period = 60 \}/);
    assert.match(config, /name = "RESTORE_EMAIL_LIMIT"\nnamespace_id = "1781921002"\nsimple = \{ limit = 1, period = 60 \}/);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

for (const [mode, host] of [
  [undefined, "curfew-license.hypertext.studio"],
  ["production", "curfew-license.hypertext.studio"],
  ["test", "curfew-license.hypertext.studio"],
  ["live", "curfew-license-staging.hypertext.studio"],
]) {
  test(`rendering refuses Stripe mode ${String(mode)} for ${host}`, async () => {
    const directory = await mkdtemp(join(tmpdir(), "curfew-stripe-mode-config-"));
    const configFile = join(directory, "wrangler.toml");
    try {
      const result = spawnSync(process.execPath, ["scripts/license-worker.mjs", "render-config", "--output", configFile], {
        encoding: "utf8", env: {
          CURFEW_LICENSE_WORKER_NAME: "curfew-license",
          CURFEW_LICENSE_KV_NAMESPACE_ID: "00000000000000000000000000000000",
          CURFEW_LICENSE_HOSTNAME: host,
          ...(mode === undefined ? {} : { CURFEW_LICENSE_STRIPE_MODE: mode }),
        },
      });
      assert.notEqual(result.status, 0);
      assert.match(result.stderr, /Stripe mode|required configuration/);
      await assert.rejects(access(configFile));
    } finally { await rm(directory, { recursive: true, force: true }); }
  });
}

for (const [host, mode, portal, accepted] of [
  ["license.thecurfew.app", "live", "https://thecurfew.app", true],
  ["curfew-license-staging.hypertext.studio", "test", "https://curfew-site-staging.hypertext.studio", false],
  ["curfew-license-staging.hypertext.studio", "test", "https://curfew-staging.hypertext.studio", true],
  ["license.thecurfew.app", "live", "https://curfew-staging.hypertext.studio", false],
  ["curfew-license-staging.hypertext.studio", "test", "https://curfew.hypertext.studio", false],
]) {
  test(`recovery pairs ${host} with portal ${portal}`, () => {
    const result = spawnSync(process.execPath, ["scripts/license-worker.mjs", "validate-config"], { encoding: "utf8", env: {
      CURFEW_LICENSE_WORKER_NAME: "curfew-license-test", CURFEW_LICENSE_KV_NAMESPACE_ID: "00000000000000000000000000000000",
      CURFEW_LICENSE_HOSTNAME: host, CURFEW_LICENSE_STRIPE_MODE: mode, CURFEW_LICENSE_RESTORE_ENABLED: "1",
      CURFEW_LICENSE_RESTORE_FROM: "purchases@curfew.hypertext.studio", CURFEW_LICENSE_PORTAL_URL: portal,
      CURFEW_LICENSE_RESTORE_IP_NAMESPACE_ID: "1781921101", CURFEW_LICENSE_RESTORE_EMAIL_NAMESPACE_ID: "1781921102",
    }});
    if (accepted) assert.equal(result.status, 0, result.stderr);
    else { assert.notEqual(result.status, 0); assert.match(result.stderr, /Recovery portal/); }
  });
}
