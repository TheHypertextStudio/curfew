import assert from "node:assert/strict";
import test from "node:test";
import { mkdtemp, writeFile, readFile, rm, mkdir } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { createArtifact } from "./deployment-config.mjs";
import { createReleaseConfiguration } from "./release-configuration.mjs";

const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");
async function api() {
  const value = await import("./local-release.mjs").catch(() => null);
  assert.equal(
    typeof value?.verifyLocalEvidence,
    "function",
    "Local publication must verify retained evidence",
  );
  return value;
}
async function evidence(t) {
  const directory = await mkdtemp(join(tmpdir(), "curfew-local-evidence-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const now = Date.now();
  const executionID = "fe840ac6-2162-47dc-83c1-b8e55e46a4e3";
  const candidate = {
    sourceCommit: "a".repeat(40),
    configurationSHA256: "b".repeat(64),
    releaseConfigurationSHA256: "c".repeat(64),
    dmgSHA256: "d".repeat(64),
    appcastSHA256: "e".repeat(64),
    version: "0.0.7",
    team: "T95VDD3A4W",
  };
  const quality = {
    schemaVersion: 1,
    executionID,
    observedAt: new Date(now).toISOString(),
    sourceCommit: candidate.sourceCommit,
    configurationSHA256: candidate.configurationSHA256,
    hostedRunClaimed: false,
    fullAppTests: { passed: 4, failed: 0, skipped: 0 },
    checks: [],
  };
  for (const [i, command] of [
    "just check",
    "swift test --package-path CurfewKit",
    "just build-release",
  ].entries()) {
    const log = `check-${i}.log`;
    const bytes = Buffer.from(`fixture output for ${command}`);
    await writeFile(join(directory, log), bytes);
    quality.checks.push({ command, exitCode: 0, log, sha256: hash(bytes) });
  }
  const signing = {
    verifiedAt: new Date(now).toISOString(),
    sourceCommit: candidate.sourceCommit,
    deploymentSHA256: candidate.configurationSHA256,
    releaseConfigurationSHA256: candidate.releaseConfigurationSHA256,
    version: candidate.version,
    developerIDTeam: candidate.team,
    dmgSHA256: candidate.dmgSHA256,
    appcastSHA256: candidate.appcastSHA256,
    hostedRunClaimed: false,
    notarizationAccepted: true,
    ticketStapled: true,
    gatekeeperAndSourceArtifactVerifierPassed: true,
  };
  await writeFile(join(directory, "quality.json"), JSON.stringify(quality));
  await writeFile(join(directory, "signing.json"), JSON.stringify(signing));
  candidate.provenance = {
    kind: "local",
    executionID,
    qualitySHA256: hash(await readFile(join(directory, "quality.json"))),
    signingSHA256: hash(await readFile(join(directory, "signing.json"))),
  };
  return { directory, now, candidate, quality, signing };
}

test("local admission verifies the actual test logs and the exact distribution identities", async (t) => {
  const { verifyLocalEvidence } = await api();
  const f = await evidence(t);
  await verifyLocalEvidence(f.directory, f.candidate, f.now);
  await writeFile(
    join(f.directory, "check-0.log"),
    "changed after the successful check",
  );
  await assert.rejects(
    () => verifyLocalEvidence(f.directory, f.candidate, f.now),
    /log|digest/i,
  );
});

test("local admission rejects missing, failed, skipped, stale, future, or mismatched evidence", async (t) => {
  const { verifyLocalEvidence } = await api();
  for (const change of [
    (f) => {
      f.quality.checks.pop();
    },
    (f) => {
      f.quality.checks[0].exitCode = 1;
    },
    (f) => {
      f.quality.fullAppTests.skipped = 1;
    },
    (f) => {
      f.quality.fullAppTests.failed = 1;
    },
    (f) => {
      f.quality.observedAt = new Date(f.now - 7 * 86400000 - 1).toISOString();
    },
    (f) => {
      f.quality.observedAt = new Date(f.now + 1).toISOString();
    },
    (f) => {
      f.quality.sourceCommit = "f".repeat(40);
    },
    (f) => {
      f.signing.deploymentSHA256 = "f".repeat(64);
    },
    (f) => {
      f.signing.dmgSHA256 = "f".repeat(64);
    },
    (f) => {
      f.signing.hostedRunClaimed = true;
    },
    (f) => {
      f.quality.checks[0].log = "../outside.log";
    },
  ]) {
    const f = await evidence(t);
    change(f);
    await writeFile(
      join(f.directory, "quality.json"),
      JSON.stringify(f.quality),
    );
    await writeFile(
      join(f.directory, "signing.json"),
      JSON.stringify(f.signing),
    );
    f.candidate.provenance.qualitySHA256 = hash(
      await readFile(join(f.directory, "quality.json")),
    );
    f.candidate.provenance.signingSHA256 = hash(
      await readFile(join(f.directory, "signing.json")),
    );
    await assert.rejects(() =>
      verifyLocalEvidence(f.directory, f.candidate, f.now),
    );
  }
});

test("local publication permits a descendant publication commit only while native source stays identical", async (t) => {
  const { verifyLocalSource } = await api();
  const repo = await mkdtemp(join(tmpdir(), "curfew-local-source-"));
  t.after(() => rm(repo, { recursive: true, force: true }));
  const gitInput = (args, input) =>
    execFileSync("git", args, {
      cwd: repo,
      input,
      encoding: "utf8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
  const git = (...args) => gitInput(args);
  git("init", "-q");
  git("config", "user.name", "Release test fixture");
  git("config", "user.email", "fixture@example.invalid");
  await mkdir(join(repo, "Curfew"));
  await writeFile(join(repo, "Curfew", "App.swift"), "retained native source");
  // Build disposable history directly, without staging or bypassing real commit hooks.
  const blob = (text) => gitInput(["hash-object", "-w", "--stdin"], text);
  const tree = (text) => gitInput(["mktree"], text);
  const commit = (root, parent) => {
    const id = gitInput(
      ["commit-tree", root, ...(parent ? ["-p", parent] : [])],
      "Disposable release fixture\n",
    );
    git("update-ref", "HEAD", id);
    git("read-tree", id);
    return id;
  };
  const native = tree(
    `100644 blob ${blob("retained native source")}\tApp.swift\n`,
  );
  const source = commit(tree(`040000 tree ${native}\tCurfew\n`));
  const frozen = await mkdtemp(join(tmpdir(), "curfew-frozen-source-"));
  t.after(() => rm(frozen, { recursive: true, force: true }));
  execFileSync("git", ["clone", "--quiet", repo, frozen]);
  await writeFile(join(repo, "publication.txt"), "reviewed publication change");
  const publicationBlob = blob("reviewed publication change");
  const publication = commit(
    tree(
      `040000 tree ${native}\tCurfew\n100644 blob ${publicationBlob}\tpublication.txt\n`,
    ),
    source,
  );
  verifyLocalSource(repo, source, publication);
  const { verifyLocalRepositories } = await api();
  verifyLocalRepositories(repo, frozen, source, publication);
  assert.throws(
    () => verifyLocalRepositories(repo, repo, source, publication),
    /source/i,
  );
  await writeFile(join(frozen, "unreviewed-verifier.mjs"), "altered verifier");
  assert.throws(
    () => verifyLocalRepositories(repo, frozen, source, publication),
    /clean/i,
  );
  await rm(join(frozen, "unreviewed-verifier.mjs"));
  await mkdir(join(repo, "scripts"));
  await writeFile(
    join(repo, "scripts/release-entitlements.mjs"),
    "weakened verifier",
  );
  const changedVerifier = tree(
    `100644 blob ${blob("weakened verifier")}\trelease-entitlements.mjs\n`,
  );
  const verifierPublication = commit(
    tree(
      `040000 tree ${native}\tCurfew\n100644 blob ${publicationBlob}\tpublication.txt\n040000 tree ${changedVerifier}\tscripts\n`,
    ),
    publication,
  );
  assert.throws(
    () => verifyLocalSource(repo, source, verifierPublication),
    /native|source/i,
  );
  await rm(join(repo, "scripts"), { recursive: true });
  git("update-ref", "HEAD", publication);
  git("read-tree", publication);
  await writeFile(
    join(repo, "Curfew", "App.swift"),
    "unvalidated native change",
  );
  assert.throws(
    () => verifyLocalSource(repo, source, publication),
    /clean|source/i,
  );
  const changedNative = tree(
    `100644 blob ${blob("unvalidated native change")}\tApp.swift\n`,
  );
  commit(
    tree(
      `040000 tree ${changedNative}\tCurfew\n100644 blob ${publicationBlob}\tpublication.txt\n`,
    ),
    publication,
  );
  assert.throws(
    () => verifyLocalSource(repo, source, git("rev-parse", "HEAD")),
    /native|source/i,
  );
  assert.throws(() => verifyLocalSource(repo, publication, source));
});

test("local distribution rechecks notarization and the mounted app, then unmounts even on rejection", async (t) => {
  const { verifyLocalDistribution } = await api();
  assert.equal(typeof verifyLocalDistribution, "function");
  const f = await evidence(t);
  const dmg = Buffer.from("test-only distribution");
  const appcast = Buffer.from("test-only feed");
  const deployment = createArtifact(
    {
      version: 1,
      environments: {
        production: {
          siteOrigin: "https://fixture.invalid",
          accountOrigin: "https://account.fixture.invalid",
          syncOrigin: "https://sync.fixture.invalid",
          licenseOrigin: "https://license.fixture.invalid",
          passkeyRPID: "fixture.invalid",
          recoveryEmailFrom: "accounts@fixture.invalid",
        },
      },
    },
    f.candidate.sourceCommit,
  );
  const configuration = createReleaseConfiguration({
    sourceCommit: f.candidate.sourceCommit,
    deployment,
    appcast: "https://fixture.invalid/appcast.xml",
    sparkleKey: "A".repeat(43) + "=",
    inputs: { "Curfew/Info.plist": "a".repeat(64) },
  });
  f.candidate.releaseConfigurationSHA256 = configuration.sha256;
  f.candidate.dmgSHA256 = hash(dmg);
  f.candidate.appcastSHA256 = hash(appcast);
  await writeFile(join(f.directory, "Curfew-v0.0.7.dmg"), dmg);
  await writeFile(join(f.directory, "appcast.xml"), appcast);
  await writeFile(
    join(f.directory, "release-configuration.json"),
    JSON.stringify(configuration),
  );
  await writeFile(
    join(f.directory, "environment-artifact.json"),
    JSON.stringify(deployment),
  );
  for (const denied of [false, true]) {
    const calls = [];
    const invoke = (command, args) => {
      calls.push([command, args]);
      if (command === "/bin/bash" && denied)
        throw Error("Gatekeeper rejected fixture");
      return "fixture tool output";
    };
    const verify = () =>
      verifyLocalDistribution(
        f.directory,
        f.candidate,
        "/trusted-source",
        invoke,
      );
    if (denied) await assert.rejects(verify, /Gatekeeper/);
    else await verify();
    assert.equal(calls[0][0], "/usr/bin/xcrun");
    assert.deepEqual(calls[0][1].slice(0, 2), ["stapler", "validate"]);
    assert.ok(
      calls.some(
        ([cmd, args]) =>
          cmd === "/usr/bin/hdiutil" &&
          args.includes("-readonly") &&
          args.includes("-mountpoint"),
      ),
    );
    const appCheck = calls.find(([cmd]) => cmd === "/bin/bash");
    assert.equal(
      appCheck[1][0],
      "/trusted-source/scripts/verify-release-artifact.sh",
    );
    assert.ok(appCheck[1][1].endsWith("/Curfew.app"));
    assert.equal(calls.at(-1)[1][0], "detach");
  }
  await writeFile(join(f.directory, "Curfew-v0.0.7.dmg"), "changed image");
  await assert.rejects(
    () =>
      verifyLocalDistribution(
        f.directory,
        f.candidate,
        "/trusted-source",
        () => {
          throw Error("Must reject before invoking a tool");
        },
      ),
    /digest/i,
  );
});
