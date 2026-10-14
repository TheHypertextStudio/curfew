import test from "node:test";
import assert from "node:assert/strict";
import { readFile, mkdtemp, writeFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
const implementation = new URL("./deployment-config.mjs", import.meta.url);
async function config() {
  await assert.doesNotReject(
    () => readFile(implementation),
    "deployment configuration loader must exist",
  );
  return import(implementation.href);
}
const fixture = {
  siteOrigin: "https://example.net",
  accountOrigin: "https://account.example.net",
  syncOrigin: "https://sync.example.net",
  licenseOrigin: "https://license.example.net",
  passkeyRPID: "example.net",
  recoveryEmailFrom: "accounts@example.net",
};
test("derives all endpoint consumers from a different approved deployment", async () => {
  const { resolveEnvironment } = await config();
  const result = resolveEnvironment(fixture, "production");
  assert.equal(result.accountPortal, "https://example.net/account");
  assert.equal(result.mcpResource, "https://sync.example.net/mcp");
  assert.equal(
    result.remoteCommandJWKS,
    "https://sync.example.net/.well-known/curfew-command-jwks.json",
  );
  assert.equal(
    result.nativeCallback,
    "https://account.example.net/oauth/callback/native/macos",
  );
  assert.equal(result.appcast, "https://example.net/appcast.xml");
  assert.equal(result.pricing, "https://example.net/#plus");
});
test("rejects insecure or ambiguous trust configuration", async () => {
  const { resolveEnvironment } = await config();
  for (const siteOrigin of [
    "http://example.net",
    "https://user:secret@example.net",
    "https://example.net/path",
    "https://example.net?q=x",
    "https://example.net#x",
    "https://example.net:8443",
  ]) {
    assert.throws(() =>
      resolveEnvironment({ ...fixture, siteOrigin }, "production"),
    );
  }
  assert.throws(() =>
    resolveEnvironment({ ...fixture, passkeyRPID: "evil.net" }, "production"),
  );
  assert.throws(() =>
    resolveEnvironment({ ...fixture, syncOrigin: undefined }, "production"),
  );
});
test("permits HTTP only on loopback in the explicit local profile", async () => {
  const { resolveEnvironment } = await config();
  const local = {
    ...fixture,
    siteOrigin: "http://localhost:4321",
    accountOrigin: "http://localhost:8787",
    syncOrigin: "http://localhost:8787",
    licenseOrigin: "http://localhost:8788",
    passkeyRPID: "localhost",
  };
  assert.equal(
    resolveEnvironment(local, "local").mcpResource,
    "http://localhost:8787/mcp",
  );
  assert.throws(() =>
    resolveEnvironment({ ...local, syncOrigin: "http://example.net" }, "local"),
  );
});
test("configuration artifacts are deterministic and bind content to source revision", async () => {
  const { createArtifact, verifyArtifact } = await config();
  const manifest = { version: 1, environments: { production: fixture } };
  const artifact = createArtifact(manifest, "a".repeat(40));
  assert.deepEqual(artifact, createArtifact(manifest, "a".repeat(40)));
  assert.equal(
    artifact.sha256,
    createHash("sha256")
      .update(JSON.stringify(artifact.manifest))
      .digest("hex"),
  );
  verifyArtifact(artifact, artifact.sha256, artifact.sourceCommit);
  assert.throws(() =>
    verifyArtifact(
      { ...artifact, manifest: { version: 999 } },
      artifact.sha256,
      artifact.sourceCommit,
    ),
  );
  assert.throws(() =>
    verifyArtifact(artifact, artifact.sha256, "b".repeat(40)),
  );
});

test("artifact generation rejects production origins reused by staging", async () => {
  const { createArtifact } = await config();
  assert.throws(
    () =>
      createArtifact(
        {
          version: 1,
          environments: {
            production: fixture,
            staging: {
              ...fixture,
              siteOrigin: "https://staging.example.net",
              passkeyRPID: "staging.example.net",
            },
          },
        },
        "a".repeat(40),
      ),
    /isolated/,
  );
});

test("native builds record the same immutable configuration identity as services", async () => {
  const { createArtifact, nativeBuildIdentity } = await config();
  const artifact = createArtifact(
    { version: 1, environments: { production: fixture } },
    "a".repeat(40),
  );
  const identity = nativeBuildIdentity(artifact);
  assert.match(
    identity,
    new RegExp(`CURFEW_CONFIGURATION_COMMIT = ${artifact.sourceCommit}`),
  );
  assert.match(
    identity,
    new RegExp(`CURFEW_CONFIGURATION_SHA256 = ${artifact.sha256}`),
  );
});

test("service builds load only the independently approved artifact identity", async (t) => {
  const { createArtifact, loadDeploymentArtifact } = await config();
  const directory = await mkdtemp(join(tmpdir(), "curfew-artifact-loader-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const artifact = createArtifact(
    { version: 1, environments: { production: fixture } },
    "a".repeat(40),
  );
  const artifactPath = join(directory, "environment.json");
  await writeFile(artifactPath, JSON.stringify(artifact));
  const identity = {
    artifactPath,
    expectedHash: artifact.sha256,
    expectedCommit: artifact.sourceCommit,
  };
  const result = await loadDeploymentArtifact("production", identity);
  assert.equal(result.licenseOrigin, fixture.licenseOrigin);
  assert.equal(result.sha256, artifact.sha256);
  assert.equal(result.sourceCommit, artifact.sourceCommit);
  assert.ok(Object.isFrozen(result));
  await assert.rejects(() =>
    loadDeploymentArtifact("production", {
      ...identity,
      expectedCommit: "b".repeat(40),
    }),
  );
  await assert.rejects(() =>
    loadDeploymentArtifact("production", {
      ...identity,
      expectedHash: "b".repeat(64),
    }),
  );
  await assert.rejects(() =>
    loadDeploymentArtifact("production", {
      ...identity,
      artifactPath: undefined,
    }),
  );
  await assert.rejects(() => loadDeploymentArtifact("staging", identity));
});

test("license CI verifies the artifact-bound cf build and actual Worker tests", async () => {
  const workflow = await readFile(
    new URL("../.github/workflows/website.yml", import.meta.url),
    "utf8",
  );
  assert.match(workflow, /node --test web\/worker\/test\/deployment.node.mjs/);
  assert.match(workflow, /pnpm --dir web\/worker test/);
  assert.match(workflow, /pnpm --dir web\/worker typecheck/);
  assert.match(
    workflow,
    /pnpm --dir web\/worker exec cf build --mode production/,
  );
  assert.match(
    workflow,
    /pnpm --dir web\/worker exec cf deploy --prebuilt --mode production --dry-run/,
  );
});
