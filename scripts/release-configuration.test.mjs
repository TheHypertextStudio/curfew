import assert from "node:assert/strict";
import test from "node:test";
import { createArtifact, resolveEnvironment } from "./deployment-config.mjs";

const manifest = JSON.parse(
  await (
    await import("node:fs/promises")
  ).readFile("deployment/environments.json", "utf8"),
);
const deployment = createArtifact(manifest, "a".repeat(40));
const appcast = resolveEnvironment(
  manifest.environments.production,
  "production",
).appcast;

async function configurationAPI() {
  const { access } = await import("node:fs/promises");
  await assert.doesNotReject(
    () => access(new URL("./release-configuration.mjs", import.meta.url)),
    "release provenance must bind the shared deployment artifact",
  );
  return import("./release-configuration.mjs");
}

test("release provenance binds unchanged endpoint inputs, resolved feed and source commit", async () => {
  const api = await configurationAPI();
  const input = {
    sourceCommit: "a".repeat(40),
    appcast,
    deployment,
    sparkleKey: Buffer.alloc(32, 7).toString("base64"),
    inputs: { "Curfew/Info.plist": "b".repeat(64) },
  };
  const artifact = api.createReleaseConfiguration(input);
  assert.equal(artifact.appcast, appcast);
  assert.equal(artifact.deployment.sha256, deployment.sha256);
  assert.doesNotThrow(() =>
    api.verifyArtifact(artifact, artifact.sha256, input.sourceCommit),
  );
  for (const change of [
    { sourceCommit: "c".repeat(40) },
    { appcast: "https://unapproved.example/appcast.xml" },
    { inputs: { "Curfew/Info.plist": "d".repeat(64) } },
  ])
    assert.throws(() =>
      api.verifyArtifact(
        { ...artifact, ...change },
        artifact.sha256,
        input.sourceCommit,
      ),
    );
});

test("unconfigured destinations and invalid keys cannot enter the candidate snapshot", async () => {
  const api = await configurationAPI();
  const input = {
    sourceCommit: "a".repeat(40),
    appcast,
    deployment,
    sparkleKey: Buffer.alloc(32, 7).toString("base64"),
    inputs: { "Curfew/Info.plist": "b".repeat(64) },
  };
  for (const change of [
    { appcast: "https://unapproved.example/appcast.xml" },
    { sparkleKey: "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY" },
    { sourceCommit: "HEAD" },
    { inputs: {} },
  ])
    assert.throws(() =>
      api.createReleaseConfiguration({ ...input, ...change }),
    );
});

test("candidate provenance accepts a second configured domain without source changes", async () => {
  const api = await configurationAPI();
  const alternate = structuredClone(manifest);
  alternate.environments.production.siteOrigin = "https://other.example";
  alternate.environments.production.passkeyRPID = "other.example";
  const configured = createArtifact(alternate, "a".repeat(40));
  const artifact = api.createReleaseConfiguration({
    sourceCommit: configured.sourceCommit,
    deployment: configured,
    appcast: "https://other.example/appcast.xml",
    sparkleKey: Buffer.alloc(32, 7).toString("base64"),
    inputs: { "Curfew/Info.plist": "b".repeat(64) },
  });
  assert.equal(artifact.deployment.sha256, configured.sha256);
  assert.throws(() =>
    api.createReleaseConfiguration({
      ...artifact,
      deployment: { ...configured, sha256: "0".repeat(64) },
    }),
  );
  assert.throws(() =>
    api.createReleaseConfiguration({
      ...artifact,
      sourceCommit: "c".repeat(40),
    }),
  );
});
