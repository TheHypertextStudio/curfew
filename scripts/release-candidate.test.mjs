import assert from "node:assert/strict";
import {
  readFile,
  mkdtemp,
  mkdir,
  writeFile,
  rm,
  access,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { generateKeyPairSync, sign } from "node:crypto";
import test from "node:test";
import { createArtifact } from "./deployment-config.mjs";
const deploymentManifest = JSON.parse(
  await readFile("deployment/environments.json", "utf8"),
);
const deployment = createArtifact(deploymentManifest, "a".repeat(40));

// Catch a tag restoring public release/feed/site writes before owner acceptance.
test("a version tag can retain a candidate but cannot publish or deploy it", () => {
  const workflow = JSON.parse(
    execFileSync(
      "ruby",
      [
        "-rjson",
        "-ryaml",
        "-e",
        "puts JSON.generate(YAML.load_file(ARGV[0]))",
        ".github/workflows/release.yml",
      ],
      { encoding: "utf8" },
    ),
  );
  for (const job of Object.values(workflow.jobs)) {
    assert.notEqual(
      job.permissions?.contents,
      "write",
      "candidate job must not write public releases",
    );
    for (const step of job.steps) {
      assert.ok(
        !step.uses?.startsWith("softprops/action-gh-release"),
        "tag must not publish a GitHub Release",
      );
      assert.doesNotMatch(
        step.run || "",
        /\bgh release\b|\bdeploy(?::pages|:worker|\s+--|\s+dist)|\bwrangler pages deploy\b/,
        "tag must not deploy the site/feed or public release",
      );
    }
    assert.ok(
      job.steps.some(
        (step) =>
          step.uses?.startsWith("actions/upload-artifact") &&
          step.with?.name === "curfew-signed-candidate",
      ),
      "signed candidate bytes must be retained together",
    );
  }
});

test("every explicitly signed Xcode configuration selects the Studio team", () => {
  const project = JSON.parse(
    execFileSync(
      "plutil",
      ["-convert", "json", "-o", "-", "Curfew.xcodeproj/project.pbxproj"],
      { encoding: "utf8" },
    ),
  );
  const configurations = Object.values(project.objects).filter(
    (object) =>
      object.isa === "XCBuildConfiguration" &&
      object.buildSettings.DEVELOPMENT_TEAM,
  );
  assert.ok(configurations.length > 0);
  for (const configuration of configurations)
    assert.equal(
      configuration.buildSettings.DEVELOPMENT_TEAM,
      "T95VDD3A4W",
      `${configuration.name} selects a non-Studio signing team`,
    );
});

test("candidate quality gate is unsigned without weakening the Release archive", () => {
  const workflow = JSON.parse(
    execFileSync(
      "ruby",
      [
        "-rjson",
        "-ryaml",
        "-e",
        "puts JSON.generate(YAML.load_file(ARGV[0]))",
        ".github/workflows/release.yml",
      ],
      { encoding: "utf8" },
    ),
  );
  const steps = workflow.jobs.release.steps;
  const quality = steps.find((step) => step.run === "just check");
  assert.equal(
    quality.env?.CURFEW_XCODEBUILD_SETTINGS,
    "CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO",
  );
  const archive = steps.find((step) =>
    /xcodebuild archive/.test(step.run || ""),
  );
  assert.equal(archive.env?.CURFEW_XCODEBUILD_SETTINGS, undefined);
  assert.doesNotMatch(
    archive.run,
    /CODE_SIGNING_ALLOWED=NO|CODE_SIGNING_REQUIRED=NO/,
  );
});

test("unsigned quality checks finish before Developer ID material is imported", () => {
  const workflow = JSON.parse(
    execFileSync(
      "ruby",
      [
        "-rjson",
        "-ryaml",
        "-e",
        "puts JSON.generate(YAML.load_file(ARGV[0]))",
        ".github/workflows/release.yml",
      ],
      { encoding: "utf8" },
    ),
  );
  const steps = workflow.jobs.release.steps;
  const qualityIndex = steps.findIndex(
    (step) => step.name === "Run quality gate",
  );
  const importIndex = steps.findIndex(
    (step) => step.name === "Import Developer ID certificate",
  );
  const archiveIndex = steps.findIndex((step) => step.name === "Archive");
  assert.ok(qualityIndex >= 0 && importIndex >= 0 && archiveIndex >= 0);
  assert.ok(
    qualityIndex < importIndex && importIndex < archiveIndex,
    "unsigned quality checks must finish before the signing keychain is created",
  );
  assert.doesNotMatch(
    JSON.stringify(workflow.jobs.release.env || {}),
    /secrets\.APPLE_CERTIFICATE(?:_PASSWORD)?/,
  );
  for (const step of steps.slice(0, qualityIndex + 1)) {
    assert.doesNotMatch(
      JSON.stringify(step.env || {}),
      /secrets\.APPLE_CERTIFICATE(?:_PASSWORD)?/,
    );
    assert.doesNotMatch(
      step.run || "",
      /\bsecurity\s+(?:create-keychain|import|set-key-partition-list)\b/,
    );
  }
});

test("public candidate retention requires explicit exposure approval before signing", () => {
  const workflow = JSON.parse(
    execFileSync(
      "ruby",
      [
        "-rjson",
        "-ryaml",
        "-e",
        "puts JSON.generate(YAML.load_file(ARGV[0]))",
        ".github/workflows/release.yml",
      ],
      { encoding: "utf8" },
    ),
  );
  const admission = workflow.jobs.release.steps.find(
    (step) => step.name === "Validate candidate identity",
  );
  for (const [approval, expected] of [
    ["", 1],
    ["false", 1],
    ["true", 0],
  ]) {
    const result = spawnSync("bash", ["-e", "-c", admission.run], {
      env: {
        ...process.env,
        RELEASE_TAG: "v0.0.1",
        APPLE_TEAM_ID: "T95VDD3A4W",
        PUBLIC_RETENTION_APPROVED: approval,
      },
    });
    assert.equal(
      result.status,
      expected,
      "public exposure must be an explicit owner choice",
    );
  }
});

test("artifact upload is immutable and follows successful transient credential cleanup", async () => {
  const workflow = JSON.parse(
    execFileSync(
      "ruby",
      [
        "-rjson",
        "-ryaml",
        "-e",
        "puts JSON.generate(YAML.load_file(ARGV[0]))",
        ".github/workflows/release.yml",
      ],
      { encoding: "utf8" },
    ),
  );
  const steps = workflow.jobs.release.steps;
  const cleanupIndex = steps.findIndex(
    (step) => step.name === "Remove transient signing credentials",
  );
  assert.ok(
    cleanupIndex >= 0,
    "temporary signing credentials must be removed before artifact code executes",
  );
  const cleanup = steps[cleanupIndex];
  assert.equal(cleanup.if, "always()");
  for (const [index, step] of steps.entries()) {
    if (!step.uses?.startsWith("actions/upload-artifact@")) continue;
    assert.match(step.uses, /^actions\/upload-artifact@[a-f0-9]{40}$/);
    assert.ok(index > cleanupIndex);
    assert.ok(
      !step.if || step.if === "success()",
      "cleanup failure must block artifact upload",
    );
  }
  for (const failure of [false, true]) {
    const root = await mkdtemp(join(tmpdir(), "curfew-signing-cleanup-"));
    try {
      const bin = join(root, "bin");
      await mkdir(bin);
      await writeFile(
        join(bin, "security"),
        '#!/bin/bash\n[[ "$1" == delete-keychain ]] || exit 66\n[[ "${FAKE_SECURITY_FAIL:-0}" == 0 ]] || exit 7\nrm -f -- "$2"\n',
        { mode: 0o700 },
      );
      for (const name of [
        "signing.keychain-db",
        "certificate.p12",
        "AuthKey.p8",
      ])
        await writeFile(join(root, name), "synthetic credential fixture");
      const result = spawnSync("bash", ["-c", cleanup.run], {
        encoding: "utf8",
        env: {
          ...process.env,
          PATH: `${bin}:${process.env.PATH}`,
          RUNNER_TEMP: root,
          FAKE_SECURITY_FAIL: failure ? "1" : "0",
        },
      });
      assert.equal(result.status, failure ? 1 : 0);
      for (const name of [
        "signing.keychain-db",
        "certificate.p12",
        "AuthKey.p8",
      ]) {
        if (failure) await assert.doesNotReject(() => access(join(root, name)));
        else await assert.rejects(() => access(join(root, name)));
      }
      assert.ok(
        !result.stdout.includes(root) && !result.stderr.includes(root),
        "cleanup diagnostics must not expose secret paths",
      );
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  }
});

test("resolved Release update key must match the existing private seed before archive", async () => {
  const api = await import("./release-candidate.mjs");
  assert.equal(
    typeof api.validateReleaseUpdateKey,
    "function",
    "resolved Release settings need a prearchive key-pair gate",
  );
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const seed = privateKey
    .export({ type: "pkcs8", format: "der" })
    .subarray(-32)
    .toString("base64");
  const publicValue = publicKey
    .export({ type: "spki", format: "der" })
    .subarray(-32)
    .toString("base64");
  assert.equal(api.sparklePublicKey(seed), publicValue);
  const settings = [
    {
      target: "Curfew",
      buildSettings: {
        CONFIGURATION: "Release",
        INFOPLIST_KEY_SUPublicEDKey: publicValue,
      },
    },
  ];
  assert.doesNotThrow(() => api.validateReleaseUpdateKey(settings, seed));
  for (const value of [
    "REPLACE_WITH_SPARKLE_PUBLIC_ED_KEY",
    "$(INFOPLIST_KEY_SUPublicEDKey)",
    "A".repeat(43) + "=",
  ])
    assert.throws(() =>
      api.validateReleaseUpdateKey(
        [
          {
            target: "Curfew",
            buildSettings: {
              CONFIGURATION: "Release",
              INFOPLIST_KEY_SUPublicEDKey: value,
            },
          },
        ],
        seed,
      ),
    );
  assert.throws(() => api.validateReleaseUpdateKey(settings, "invalid"));
  assert.throws(() => api.validateReleaseUpdateKey([], seed));
});

async function fixture() {
  const api = await import("./release-candidate.mjs");
  const dmg = Buffer.from("test signed disk image bytes");
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const sparkleKey = publicKey
    .export({ type: "spki", format: "der" })
    .subarray(-32)
    .toString("base64");
  const { createReleaseConfiguration } =
    await import("./release-configuration.mjs");
  const configuration = createReleaseConfiguration({
    sourceCommit: "a".repeat(40),
    appcast: "https://thecurfew.app/appcast.xml",
    deployment,
    sparkleKey,
    inputs: { "Curfew/Info.plist": "b".repeat(64) },
  });
  const signature = sign(null, dmg, privateKey).toString("base64");
  const appcast = Buffer.from(
    `<rss><channel><link>https://thecurfew.app/appcast.xml</link><item><sparkle:version>0.0.1</sparkle:version><enclosure url="https://github.com/TheHypertextStudio/curfew/releases/download/v0.0.1/Curfew-v0.0.1.dmg" length="${dmg.length}" sparkle:edSignature="${signature}" /></item></channel></rss>`,
  );
  const candidate = api.createCandidate({
    dmg,
    appcast,
    configuration,
    version: "0.0.1",
    team: "T95VDD3A4W",
    sparkleKey,
    runID: "123",
  });
  assert.equal(candidate.configurationSHA256, deployment.sha256);
  assert.equal(candidate.releaseConfigurationSHA256, configuration.sha256);
  return { api, dmg, appcast, configuration, candidate };
}

test("a local candidate records explicit evidence identities without claiming a hosted run", async () => {
  const f = await fixture();
  const provenance = {
    kind: "local",
    executionID: "fe840ac6-2162-47dc-83c1-b8e55e46a4e3",
    qualitySHA256: "c".repeat(64),
    signingSHA256: "d".repeat(64),
  };
  const input = { ...f, ...f.candidate, runID: undefined, provenance };
  const candidate = f.api.createCandidate(input);
  assert.equal(candidate.schemaVersion, 2);
  assert.deepEqual(candidate.provenance, provenance);
  assert.equal(Object.hasOwn(candidate, "runID"), false);
  assert.deepEqual(f.api.verifyCandidate({ ...input, candidate }), candidate);
  for (const mutate of [
    (x) => {
      x.runID = "123";
    },
    (x) => {
      x.provenance.kind = "github";
    },
    (x) => {
      x.provenance.qualitySHA256 = "missing";
    },
    (x) => {
      x.provenance.signingSHA256 = "missing";
    },
    (x) => {
      x.provenance.executionID = "123";
    },
    (x) => {
      x.provenance.hostedRunClaimed = true;
    },
    (x) => {
      x.dmg = Buffer.from("substituted bytes");
    },
  ]) {
    const changed = { ...input, provenance: { ...provenance } };
    mutate(changed);
    assert.throws(() => f.api.createCandidate(changed));
  }
});

test("candidate packaging refuses an absent or non-executable browser native host", async () => {
  const api = await import("./release-candidate.mjs");
  assert.equal(
    typeof api.verifyEmbeddedToolPackaging,
    "function",
    "candidate packaging must validate every embedded executable before signature checks",
  );
  const root = await mkdtemp(join(tmpdir(), "curfew-candidate-packaging-"));
  try {
    const resources = join(root, "Contents/Resources");
    await mkdir(resources, { recursive: true });
    for (const name of ["curfew-ctl", "curfew-mcp", "curfew-daemon", "curfew-supervisor"])
      await writeFile(join(resources, name), "test executable", {
        mode: 0o700,
      });
    await assert.rejects(
      () => api.verifyEmbeddedToolPackaging(root),
      /studio.hypertext.curfew.browser/,
    );
    await writeFile(
      join(resources, "studio.hypertext.curfew.browser"),
      "test executable",
      { mode: 0o600 },
    );
    await assert.rejects(
      () => api.verifyEmbeddedToolPackaging(root),
      /executable/,
    );
    await rm(join(resources, "studio.hypertext.curfew.browser"));
    await writeFile(
      join(resources, "studio.hypertext.curfew.browser"),
      "test executable",
      { mode: 0o700 },
    );
    // File presence alone cannot establish a valid universal executable.
    await assert.rejects(() => api.verifyEmbeddedToolPackaging(root));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});

// Catch a substituted DMG/feed/config or a receipt for a different candidate.
test("candidate verification binds bytes, Studio identity, configuration and update signature", async () => {
  const f = await fixture();
  assert.doesNotThrow(() => f.api.verifyCandidate(f));
  for (const change of [
    { dmg: Buffer.from("replacement") },
    { appcast: Buffer.from("replacement") },
    { candidate: { ...f.candidate, team: "39AB9DY3K8" } },
    { candidate: { ...f.candidate, version: "1.0.0" } },
    { configuration: { ...f.configuration, sourceCommit: "b".repeat(40) } },
  ])
    assert.throws(() => f.api.verifyCandidate({ ...f, ...change }));
});

test("candidate creation rejects a mismatched Sparkle signature and non-0.0.x version", async () => {
  const f = await fixture();
  assert.throws(() =>
    f.api.createCandidate({ ...f.candidate, ...f, dmg: Buffer.from("other") }),
  );
  assert.throws(() =>
    f.api.createCandidate({ ...f.candidate, ...f, version: "0.1.0" }),
  );
});

test("activation inspection withholds missing failed or mismatched owner evidence", async () => {
  const f = await fixture();
  const receipt = {
    candidate: f.candidate,
    operator: "owner",
    observedAt: "2026-10-14T01:00:00Z",
    gates: Object.fromEntries(
      f.api.activationGates.map((name) => [
        name,
        { outcome: "pass", evidence: "owner-recorded evidence reference" },
      ]),
    ),
  };
  assert.equal(
    f.api.inspectActivation(f, receipt).status,
    "eligible-for-owner-controlled-activation",
  );
  for (const bad of [
    null,
    {
      ...receipt,
      candidate: { ...f.candidate, configurationSHA256: "0".repeat(64) },
    },
    { ...receipt, gates: {} },
    {
      ...receipt,
      gates: {
        ...receipt.gates,
        signedDevice: { outcome: "pending", evidence: "pending" },
      },
    },
  ]) {
    assert.throws(() => f.api.inspectActivation(f, bad));
  }
});

test("signed app identity rejects Development signing, old team, and wrong embedded configuration", async () => {
  const f = await fixture();
  const info = {
    CFBundleIdentifier: "studio.hypertext.apps.curfew",
    CFBundleShortVersionString: "0.0.1",
    CFBundleVersion: "0.0.1",
    CurfewConfigurationCommit: f.configuration.sourceCommit,
    CurfewConfigurationSHA256: f.configuration.deployment.sha256,
    SUFeedURL: "https://thecurfew.app/appcast.xml",
    SUPublicEDKey: f.candidate.sparkleKey,
  };
  const signature =
    "Authority=Developer ID Application: Hypertext Studio, LLC (T95VDD3A4W)\nTeamIdentifier=T95VDD3A4W\n";
  assert.doesNotThrow(() =>
    f.api.validateAppIdentity(info, signature, f.configuration, "0.0.1"),
  );
  for (const [properties, signing] of [
    [info, signature.replace("Developer ID Application", "Apple Development")],
    [info, signature.replaceAll("T95VDD3A4W", "39AB9DY3K8")],
    [{ ...info, CurfewConfigurationSHA256: "b".repeat(64) }, signature],
    [{ ...info, CurfewConfigurationCommit: "b".repeat(40) }, signature],
    [{ ...info, CFBundleVersion: "1" }, signature],
    [
      { ...info, SUPublicEDKey: Buffer.alloc(32, 8).toString("base64") },
      signature,
    ],
    [
      { ...info, SUFeedURL: "https://unapproved.example/appcast.xml" },
      signature,
    ],
  ])
    assert.throws(() =>
      f.api.validateAppIdentity(properties, signing, f.configuration, "0.0.1"),
    );
});

test("candidate and signed app must use the public key in the immutable source snapshot", async () => {
  const f = await fixture();
  const { createReleaseConfiguration } =
    await import("./release-configuration.mjs");
  const configuration = createReleaseConfiguration({
    ...f.configuration,
    sparkleKey: Buffer.alloc(32, 8).toString("base64"),
  });
  assert.throws(() =>
    f.api.createCandidate({ ...f.candidate, ...f, configuration }),
  );
});
