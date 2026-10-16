import test from "node:test";
import assert from "node:assert/strict";
import { mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createArtifact } from "../../../scripts/deployment-config.mjs";
import licenseConfig from "../cloudflare.config.ts";

const keys = [
  "CURFEW_DEPLOYMENT_ARTIFACT",
  "CURFEW_CONFIGURATION_SHA256",
  "CURFEW_CONFIGURATION_COMMIT",
  "CURFEW_LICENSE_KV_NAMESPACE_ID",
  "CURFEW_LICENSE_WORKER_NAME",
];
test("license cf configuration rejects an unapproved build", async (t) => {
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  for (const key of keys) delete process.env[key];
  t.after(() => {
    for (const key of keys)
      saved[key] === undefined
        ? delete process.env[key]
        : (process.env[key] = saved[key]);
  });
  await assert.rejects(() => licenseConfig({ mode: "production" }));
});

test("license cf configuration uses the shared artifact and retains resource identity", async (t) => {
  const directory = await mkdtemp(join(tmpdir(), "curfew-license-deployment-"));
  const saved = Object.fromEntries(keys.map((key) => [key, process.env[key]]));
  t.after(async () => {
    for (const key of keys)
      saved[key] === undefined
        ? delete process.env[key]
        : (process.env[key] = saved[key]);
    await rm(directory, { recursive: true, force: true });
  });
  const artifact = createArtifact(
    {
      version: 1,
      environments: {
        production: {
          siteOrigin: "https://other.example",
          accountOrigin: "https://account.other.example",
          syncOrigin: "https://sync.other.example",
          licenseOrigin: "https://license.other.example",
          passkeyRPID: "other.example",
          recoveryEmailFrom: "accounts@other.example",
          retiredLicenseOrigins: ["https://old-license.example"],
        },
        staging: {
          siteOrigin: "https://staging.other.example",
          purchasePortalOrigin: "https://website.staging.other.example",
          accountOrigin: "https://account.staging.other.example",
          syncOrigin: "https://sync.staging.other.example",
          licenseOrigin: "https://license.staging.other.example",
          passkeyRPID: "staging.other.example",
          recoveryEmailFrom: "accounts@staging.other.example",
        },
      },
    },
    "a".repeat(40),
  );
  process.env.CURFEW_DEPLOYMENT_ARTIFACT = join(directory, "environment.json");
  process.env.CURFEW_CONFIGURATION_SHA256 = artifact.sha256;
  process.env.CURFEW_CONFIGURATION_COMMIT = artifact.sourceCommit;
  await writeFile(
    process.env.CURFEW_DEPLOYMENT_ARTIFACT,
    JSON.stringify(artifact),
  );
  const config = await licenseConfig({ mode: "production" });
  assert.equal(config.accountId, "2500680a3b2b0fe6a011c1c25fed5008");
  assert.equal(config.worker.name, "curfew-issue-license");
  assert.deepEqual(config.worker.domains, [
    "license.other.example",
    "old-license.example",
  ]);
  assert.equal(
    config.worker.env.LICENSE_KV.id,
    "4313ea07769f4578a8fdd412620a412e",
  );
  assert.equal(config.worker.env.STRIPE_MODE?.value, "live");
  assert.deepEqual(config.worker.env.EMAIL?.allowedSenderAddresses, [
    "purchases@curfew.hypertext.studio",
  ]);
  assert.equal(
    config.worker.env.RESTORE_EMAIL_FROM?.value,
    "purchases@curfew.hypertext.studio",
  );
  assert.equal(
    config.worker.env.PURCHASE_PORTAL_URL?.value,
    "https://other.example",
  );
  assert.equal(config.worker.env.RESTORE_IP_LIMIT?.namespace, "1781921001");
  assert.deepEqual(config.worker.env.RESTORE_IP_LIMIT?.simple, {
    limit: 5,
    period: 60,
  });
  assert.equal(config.worker.env.RESTORE_EMAIL_LIMIT?.namespace, "1781921002");
  assert.deepEqual(config.worker.env.RESTORE_EMAIL_LIMIT?.simple, {
    limit: 1,
    period: 60,
  });
  process.env.CURFEW_LICENSE_KV_NAMESPACE_ID =
    "f533e31c946f4960898e09ef285bd743";
  process.env.CURFEW_LICENSE_WORKER_NAME = "curfew-issue-license-staging";
  const staging = await licenseConfig({ mode: "staging" });
  assert.equal(staging.worker.env.STRIPE_MODE?.value, "test");
  assert.equal(
    staging.worker.env.PURCHASE_PORTAL_URL?.value,
    "https://website.staging.other.example",
  );
  assert.equal(staging.worker.env.RESTORE_IP_LIMIT?.namespace, "1781921101");
  assert.equal(staging.worker.env.RESTORE_EMAIL_LIMIT?.namespace, "1781921102");
  assert.notEqual(
    staging.worker.env.LICENSE_KV.id,
    config.worker.env.LICENSE_KV.id,
  );
  process.env.CURFEW_LICENSE_KV_NAMESPACE_ID = config.worker.env.LICENSE_KV.id;
  await assert.rejects(
    () => licenseConfig({ mode: "staging" }),
    /staging.*production/i,
  );
  process.env.CURFEW_LICENSE_KV_NAMESPACE_ID =
    "f533e31c946f4960898e09ef285bd743";
  process.env.CURFEW_LICENSE_WORKER_NAME = "curfew-issue-license";
  await assert.rejects(
    () => licenseConfig({ mode: "staging" }),
    /staging.*production/i,
  );
  assert.equal(config.worker.env.CONFIGURATION_SHA256.value, artifact.sha256);
  assert.equal(
    config.worker.env.CONFIGURATION_COMMIT.value,
    artifact.sourceCommit,
  );
  process.env.CURFEW_CONFIGURATION_SHA256 = "b".repeat(64);
  await assert.rejects(() => licenseConfig({ mode: "production" }));
});
