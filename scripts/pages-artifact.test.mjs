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
    },
  },
  "a".repeat(40),
);

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), "curfew-pages-artifact-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await mkdir(join(directory, "_worker.js"));
  await writeFile(join(directory, "index.html"), "<h1>Curfew</h1>");
  await writeFile(
    join(directory, "_worker.js/index.js"),
    "export default {fetch(){return new Response('Curfew')}}",
  );
  await writeFile(
    join(directory, "_routes.json"),
    JSON.stringify({ version: 1, include: ["/*"], exclude: [] }),
  );
  return directory;
}
async function api() {
  const value = await import("./pages-artifact.mjs").catch(() => null);
  assert.equal(
    typeof value?.sealWebsite,
    "function",
    "The retained Pages build must have an identity",
  );
  return value;
}

test("Pages sealing binds an alternate-domain build to its configuration and source", async (t) => {
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
test("Pages publication rejects changed assets and a different candidate configuration", async (t) => {
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
test("Pages sealing refuses an absent redirect bundle or routes that bypass middleware", async (t) => {
  const directory = await fixture(t);
  const { sealWebsite } = await api();
  await rm(join(directory, "_worker.js"), { recursive: true });
  await assert.rejects(() => sealWebsite(directory, deployment));
  await mkdir(join(directory, "_worker.js"));
  await writeFile(join(directory, "_worker.js/index.js"), "export default {}");
  await writeFile(
    join(directory, "_routes.json"),
    JSON.stringify({ version: 1, include: ["/*"], exclude: ["/download"] }),
  );
  await assert.rejects(() => sealWebsite(directory, deployment), /middleware/i);
});
