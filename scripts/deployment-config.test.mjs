import test from "node:test";
import assert from "node:assert/strict";
import { readFile, mkdtemp, writeFile, rm, mkdir, copyFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
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
  assert.equal(result.purchasePortalOrigin, fixture.siteOrigin);
});
test("a separate purchase website preserves account and passkey identity", async () => {
  const { resolveEnvironment } = await config();
  const result = resolveEnvironment(
    { ...fixture, purchasePortalOrigin: "https://website.example.net" },
    "staging",
  );
  assert.equal(result.purchasePortalOrigin, "https://website.example.net");
  assert.equal(result.pricing, "https://website.example.net/#plus");
  assert.equal(result.accountPortal, "https://example.net/account");
  assert.equal(result.passkeyRPID, "example.net");
  for (const purchasePortalOrigin of [
    "http://website.example.net",
    "https://website.example.net/restore",
    "https://user:password@website.example.net",
    "https://website.example.net?q=x",
  ]) {
    assert.throws(
      () => resolveEnvironment({ ...fixture, purchasePortalOrigin }, "staging"),
      /purchasePortalOrigin/,
    );
  }
});
test("staging purchase websites cannot use a production service origin", async () => {
  const { createArtifact } = await config();
  for (const purchasePortalOrigin of [
    fixture.siteOrigin,
    fixture.licenseOrigin,
  ]) {
    assert.throws(
      () =>
        createArtifact(
          {
            version: 1,
            environments: {
              production: fixture,
              staging: {
                siteOrigin: "https://staging.example.net",
                accountOrigin: "https://account.staging.example.net",
                syncOrigin: "https://sync.staging.example.net",
                licenseOrigin: "https://license.staging.example.net",
                passkeyRPID: "staging.example.net",
                recoveryEmailFrom: "accounts@staging.example.net",
                purchasePortalOrigin,
              },
            },
          },
          "a".repeat(40),
        ),
      /isolated/,
    );
  }
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
  assert.match(
    workflow,
    /node --test scripts\/turbo-cache\.test\.mjs web\/worker\/test\/\*\.node\.mjs/,
  );
  assert.match(workflow, /pnpm --dir web\/worker test/);
  assert.match(workflow, /pnpm --dir web typecheck/);
  assert.match(
    workflow,
    /pnpm --dir web\/worker exec cf build --mode production/,
  );
  assert.match(
    workflow,
    /pnpm --dir web\/worker exec cf deploy --prebuilt --mode production --dry-run/,
  );
});

test("website PR validation does not receive production deployment credentials", async () => {
  const workflow = await readFile(
    new URL("../.github/workflows/website.yml", import.meta.url),
    "utf8",
  );
  assert.doesNotMatch(
    workflow,
    /\$\{\{\s*secrets\.CLOUDFLARE_API_TOKEN\s*\}\}/,
  );
});

test("signed app flavors retain the default Keychain access group used by existing credentials", async () => {
  for (const [path, expected] of [
    [
      "Curfew/Curfew.entitlements",
      "$(AppIdentifierPrefix)studio.hypertext.curfew.dev",
    ],
    [
      "Curfew/Curfew-StudioDev.entitlements",
      "$(AppIdentifierPrefix)studio.hypertext.curfew.studio.dev",
    ],
    [
      "Curfew/Curfew-Release.entitlements",
      "$(AppIdentifierPrefix)studio.hypertext.curfew",
    ],
  ]) {
    const entitlements = JSON.parse(
      execFileSync("plutil", ["-convert", "json", "-o", "-", path], {
        encoding: "utf8",
      }),
    );
    assert.deepEqual(entitlements["keychain-access-groups"], [expected], path);
  }
});

test("deployment generation preserves the retained Keychain group when rewriting account associations", async (t) => {
  const { generateDeployment } = await config();
  // Keep the fixture under the source checkout so provenance resolves from its real Git parent.
  const root = await mkdtemp(join(process.cwd(), ".keychain-generation-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const folder of [
    "deployment",
    "Curfew",
    "landing/public",
    "CurfewKit/Sources/CurfewKit/Sync",
  ])
    await mkdir(join(root, folder), { recursive: true });
  const manifest = JSON.parse(
    await readFile("deployment/environments.json", "utf8"),
  );
  manifest.environments.production.accountOrigin =
    "https://account.updated.example.net";
  await writeFile(
    join(root, "deployment/environments.json"),
    JSON.stringify(manifest),
  );
  for (const path of [
    "Curfew/Curfew-Release.entitlements",
    "Curfew/Curfew.entitlements",
    "landing/public/sitemap.xml",
    "landing/public/robots.txt",
  ])
    await copyFile(path, join(root, path));
  await generateDeployment(root);
  for (const [path, expected] of [
    [
      "Curfew/Curfew-Release.entitlements",
      "$(AppIdentifierPrefix)studio.hypertext.curfew",
    ],
    [
      "Curfew/Curfew.entitlements",
      "$(AppIdentifierPrefix)studio.hypertext.curfew.dev",
    ],
  ]) {
    const entitlements = JSON.parse(
      execFileSync("plutil", ["-convert", "json", "-o", "-", join(root, path)], {
        encoding: "utf8",
      }),
    );
    assert.deepEqual(entitlements["keychain-access-groups"], [expected]);
    assert.ok(
      entitlements["com.apple.developer.associated-domains"].includes(
        "applinks:account.updated.example.net",
      ),
    );
  }
});
