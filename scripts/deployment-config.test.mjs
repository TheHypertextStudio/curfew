import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
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

test("native builds record the same immutable configuration identity as services", async () => {
  const { createArtifact, nativeBuildIdentity } = await config();
  const artifact = createArtifact(
    { version: 1, environments: { production: fixture } },
    "a".repeat(40),
  );
  const identity = nativeBuildIdentity(artifact);
  assert.match(identity, new RegExp(`CURFEW_CONFIGURATION_COMMIT = ${artifact.sourceCommit}`));
  assert.match(identity, new RegExp(`CURFEW_CONFIGURATION_SHA256 = ${artifact.sha256}`));
});
