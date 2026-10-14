import assert from "node:assert/strict";
import test from "node:test";

async function configurationAPI() {
  const { access } = await import("node:fs/promises");
  await assert.doesNotReject(
    () => access(new URL("./release-configuration.mjs", import.meta.url)),
    "independent release provenance must not depend on domain migration",
  );
  return import("./release-configuration.mjs");
}

test("release provenance binds unchanged endpoint inputs, resolved feed and source commit", async () => {
  const api = await configurationAPI();
  const input = {
    sourceCommit: "a".repeat(40),
    appcast: "https://curfew.hypertext.studio/appcast.xml",
    sparkleKey: Buffer.alloc(32, 7).toString("base64"),
    inputs: { "Curfew/Info.plist": "b".repeat(64) },
  };
  const artifact = api.createReleaseConfiguration(input);
  assert.equal(artifact.appcast, "https://curfew.hypertext.studio/appcast.xml");
  assert.doesNotThrow(() =>
    api.verifyArtifact(artifact, artifact.sha256, input.sourceCommit),
  );
  for (const change of [
    { sourceCommit: "c".repeat(40) },
    { appcast: "https://thecurfew.app/appcast.xml" },
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

test("unaccepted domain changes and invalid keys cannot enter the safe candidate snapshot", async () => {
  const api = await configurationAPI();
  const input = {
    sourceCommit: "a".repeat(40),
    appcast: "https://curfew.hypertext.studio/appcast.xml",
    sparkleKey: Buffer.alloc(32, 7).toString("base64"),
    inputs: { "Curfew/Info.plist": "b".repeat(64) },
  };
  for (const change of [
    { appcast: "https://thecurfew.app/appcast.xml" },
    { sparkleKey: "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY" },
    { sourceCommit: "HEAD" },
    { inputs: {} },
  ])
    assert.throws(() =>
      api.createReleaseConfiguration({ ...input, ...change }),
    );
});
