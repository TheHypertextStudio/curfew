import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, mkdir, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createArtifact } from "./deployment-config.mjs";

const deployment = createArtifact(
  {
    version: 1,
    environments: {
      production: {
        siteOrigin: "https://alternate.example",
        accountOrigin: "https://account.alternate.example",
        syncOrigin: "https://sync.alternate.example",
        licenseOrigin: "https://license.alternate.example",
        passkeyRPID: "alternate.example",
        recoveryEmailFrom: "accounts@alternate.example",
      },
      staging: {
        siteOrigin: "https://staging.alternate.example",
        accountOrigin: "https://account.staging.alternate.example",
        syncOrigin: "https://sync.staging.alternate.example",
        licenseOrigin: "https://license.staging.alternate.example",
        passkeyRPID: "staging.alternate.example",
        recoveryEmailFrom: "accounts@staging.alternate.example",
      },
    },
  },
  "a".repeat(40),
);

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), "curfew-website-artifact-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await writeFile(join(directory, "index.html"), "<h1>Curfew</h1>");
  await purchasePages(directory, "https://license.alternate.example", "curfew");
  return directory;
}
async function api() {
  const value = await import("./website-artifact.mjs").catch(() => null);
  assert.equal(
    typeof value?.sealWebsite,
    "function",
    "The retained static build must have an identity",
  );
  return value;
}

test("Static sealing binds an alternate-domain build to its configuration and source", async (t) => {
  const directory = await fixture(t);
  const { sealWebsite, verifyWebsite } = await api();
  const stamp = await sealWebsite(directory, deployment);
  assert.equal(stamp.sourceCommit, "a".repeat(40));
  assert.equal(stamp.configurationSHA256, deployment.sha256);
  assert.match(stamp.contentSHA256, /^[a-f0-9]{64}$/);
  await verifyWebsite(
    directory,
    stamp,
    deployment,
    deployment.sha256,
    "a".repeat(40),
  );
});
test("Static publication rejects changed assets and a different candidate configuration", async (t) => {
  const directory = await fixture(t);
  const { sealWebsite, verifyWebsite } = await api();
  const stamp = await sealWebsite(directory, deployment);
  await assert.rejects(() =>
    verifyWebsite(directory, stamp, deployment, "b".repeat(64), "a".repeat(40)),
  );
  await writeFile(join(directory, "index.html"), "replacement");
  await assert.rejects(
    () =>
      verifyWebsite(
        directory,
        stamp,
        deployment,
        deployment.sha256,
        "a".repeat(40),
      ),
    /website build/i,
  );
});
test("static sealing refuses missing output and obsolete Pages runtime files", async (t) => {
  const directory = await fixture(t);
  const { sealWebsite } = await api();
  await rm(join(directory, "index.html"));
  await assert.rejects(() => sealWebsite(directory, deployment));
  await writeFile(join(directory, "index.html"), "<h1>Curfew</h1>");
  await purchasePages(directory, "https://license.alternate.example", "curfew");
  await mkdir(join(directory, "_worker.js"));
  await writeFile(join(directory, "_worker.js/index.js"), "export default {}");
  await assert.rejects(() => sealWebsite(directory, deployment), /Pages/i);
  await rm(join(directory, "_worker.js"), { recursive: true });
  await writeFile(join(directory, "_routes.json"), "{}");
  await assert.rejects(() => sealWebsite(directory, deployment), /Pages/i);
});

async function purchasePages(directory, issuer, scheme) {
  for (const [page, mode] of [
    ["success", "checkout"],
    ["restore", "restore"],
  ]) {
    await writeFile(
      join(directory, `${page}.html`),
      `<div data-purchase-mode="${mode}" data-issuer="${issuer}" data-scheme="${scheme}"></div>`,
    );
  }
}
test("staging website sealing rejects production purchase settings", async (t) => {
  const directory = await fixture(t);
  const { sealWebsite } = await api();
  await assert.rejects(
    () => sealWebsite(directory, deployment, "staging"),
    /purchase.*environment/i,
  );
});
test("staging build identity cannot be admitted for production publication", async (t) => {
  const directory = await fixture(t);
  await purchasePages(
    directory,
    "https://license.staging.alternate.example",
    "curfew-studio-dev",
  );
  const { sealWebsite, verifyWebsite } = await api();
  const stamp = await sealWebsite(directory, deployment, "staging");
  assert.equal(stamp.deploymentMode, "staging");
  await verifyWebsite(
    directory,
    stamp,
    deployment,
    deployment.sha256,
    "a".repeat(40),
    "staging",
  );
  await assert.rejects(
    () =>
      verifyWebsite(
        directory,
        stamp,
        deployment,
        deployment.sha256,
        "a".repeat(40),
      ),
    /purchase.*environment|website build/i,
  );
});
test("static sealing checks both checkout and restoration app pairing", async (t) => {
  const directory = await fixture(t);
  const { sealWebsite } = await api();
  await writeFile(
    join(directory, "restore.html"),
    '<div data-purchase-mode="restore" data-issuer="https://license.alternate.example" data-scheme="curfew-studio-dev"></div>',
  );
  await assert.rejects(
    () => sealWebsite(directory, deployment),
    /purchase.*environment/i,
  );
});
