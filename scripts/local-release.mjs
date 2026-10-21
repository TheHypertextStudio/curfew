import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  readFile,
  lstat,
  mkdtemp,
  mkdir,
  rm,
  writeFile,
} from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { join, resolve } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { verifyArtifact } from "./release-configuration.mjs";
import { createCandidate } from "./release-candidate.mjs";

export const localEvidenceHash = (bytes) =>
  createHash("sha256").update(bytes).digest("hex");

function fresh(time, now) {
  const observed = Date.parse(time);
  assert.ok(
    Number.isFinite(observed) &&
      observed <= now &&
      now - observed <= 7 * 86400000,
    "Local evidence is stale or future dated",
  );
}

async function sealedJSON(directory, name, expected) {
  const path = join(directory, name);
  assert.ok((await lstat(path)).isFile(), "Evidence must be a regular file");
  const bytes = await readFile(path);
  assert.equal(
    localEvidenceHash(bytes),
    expected,
    "Local evidence digest mismatch",
  );
  return JSON.parse(bytes);
}

/** Evidence stays private; the public candidate contains only its digests. */
export async function verifyLocalEvidence(
  directory,
  candidate,
  now = Date.now(),
) {
  assert.equal(candidate.provenance?.kind, "local");
  const quality = await sealedJSON(
    directory,
    "quality.json",
    candidate.provenance.qualitySHA256,
  );
  const signing = await sealedJSON(
    directory,
    "signing.json",
    candidate.provenance.signingSHA256,
  );
  assert.equal(quality.schemaVersion, 1);
  assert.equal(quality.executionID, candidate.provenance.executionID);
  assert.equal(quality.hostedRunClaimed, false);
  assert.equal(quality.sourceCommit, candidate.sourceCommit);
  assert.equal(quality.configurationSHA256, candidate.configurationSHA256);
  fresh(quality.observedAt, now);
  assert.ok(
    Number.isSafeInteger(quality.fullAppTests?.passed) &&
      quality.fullAppTests.passed > 0,
    "Full native tests are required",
  );
  assert.equal(quality.fullAppTests.failed, 0);
  assert.equal(quality.fullAppTests.skipped, 0);
  assert.deepEqual(quality.checks.map((x) => x.command).sort(), [
    "just build-release",
    "just check",
    "swift test --package-path CurfewKit",
  ]);
  for (const check of quality.checks) {
    assert.equal(check.exitCode, 0, "A local quality check failed");
    assert.match(
      check.log,
      /^[A-Za-z0-9][A-Za-z0-9_-]*\.log$/,
      "Evidence logs must be local filenames",
    );
    const path = join(directory, check.log);
    assert.ok(
      (await lstat(path)).isFile(),
      "Evidence logs must be regular files",
    );
    const bytes = await readFile(path);
    assert.ok(bytes.length > 0, "An empty test log cannot establish success");
    assert.equal(
      localEvidenceHash(bytes),
      check.sha256,
      "Local test log digest mismatch",
    );
  }
  fresh(signing.verifiedAt, now);
  assert.equal(signing.hostedRunClaimed, false);
  for (const [key, expected] of Object.entries({
    sourceCommit: candidate.sourceCommit,
    deploymentSHA256: candidate.configurationSHA256,
    releaseConfigurationSHA256: candidate.releaseConfigurationSHA256,
    version: candidate.version,
    developerIDTeam: candidate.team,
    dmgSHA256: candidate.dmgSHA256,
    appcastSHA256: candidate.appcastSHA256,
    notarizationAccepted: true,
    ticketStapled: true,
    gatekeeperAndSourceArtifactVerifierPassed: true,
  }))
    assert.equal(
      signing[key],
      expected,
      `Local signing evidence mismatch: ${key}`,
    );
}

/** A publishing fix may land later; an unvalidated native change may not. */
export function verifyLocalSource(repository, sourceCommit, publicationCommit) {
  assert.match(sourceCommit, /^[a-f0-9]{40}$/);
  assert.match(publicationCommit, /^[a-f0-9]{40}$/);
  const git = (...args) =>
    execFileSync("git", args, {
      cwd: repository,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim();
  assert.equal(
    git("rev-parse", "HEAD"),
    publicationCommit,
    "Publication source mismatch",
  );
  assert.equal(
    git("status", "--porcelain"),
    "",
    "Publication source must be clean",
  );
  try {
    git("merge-base", "--is-ancestor", sourceCommit, publicationCommit);
    git(
      "diff",
      "--exit-code",
      sourceCommit,
      publicationCommit,
      "--",
      "Curfew",
      "CurfewKit",
      "CurfewWidget",
      "Curfew.xcodeproj",
      "CurfewTests",
      "CurfewUITests",
      "deployment",
      ".github/workflows/release.yml",
      "scripts/verify-release-artifact.sh",
      "scripts/release-entitlements.mjs",
      "scripts/build-dmg.sh",
    );
  } catch (cause) {
    throw new Error(
      "Native source changed or publication is not a descendant of the candidate",
      { cause },
    );
  }
}

/** Run the verifier and all its transitive inputs from the original clean source. */
export function verifyLocalRepositories(
  repository,
  nativeRepository,
  sourceCommit,
  publicationCommit,
) {
  verifyLocalSource(repository, sourceCommit, publicationCommit);
  verifyLocalSource(nativeRepository, sourceCommit, sourceCommit);
}

/** Recheck real OS trust on the exact mounted bytes; receipts alone are insufficient. */
export async function verifyLocalDistribution(
  directory,
  candidate,
  repository,
  invoke = execFileSync,
) {
  const dmg = join(directory, `Curfew-v${candidate.version}.dmg`);
  assert.equal(
    localEvidenceHash(await readFile(dmg)),
    candidate.dmgSHA256,
    "Local DMG digest mismatch",
  );
  assert.equal(
    localEvidenceHash(await readFile(join(directory, "appcast.xml"))),
    candidate.appcastSHA256,
    "Local feed digest mismatch",
  );
  const configurationPath = join(directory, "release-configuration.json");
  const configuration = JSON.parse(await readFile(configurationPath, "utf8"));
  verifyArtifact(
    configuration,
    candidate.releaseConfigurationSHA256,
    candidate.sourceCommit,
  );
  const deploymentPath = join(directory, "environment-artifact.json");
  assert.deepEqual(
    JSON.parse(await readFile(deploymentPath, "utf8")),
    configuration.deployment,
  );
  const options = {
    cwd: repository,
    encoding: "utf8",
    timeout: 180000,
    stdio: ["ignore", "pipe", "pipe"],
    env: {
      ...process.env,
      CURFEW_DEPLOYMENT_ARTIFACT: deploymentPath,
      CURFEW_CONFIGURATION_COMMIT: candidate.sourceCommit,
      CURFEW_CONFIGURATION_SHA256: candidate.configurationSHA256,
    },
  };
  invoke("/usr/bin/xcrun", ["stapler", "validate", dmg], options);
  const temporary = await mkdtemp(join(tmpdir(), "curfew-local-distribution-"));
  const volume = join(temporary, "volume");
  await mkdir(volume);
  let mounted = false;
  try {
    invoke(
      "/usr/bin/hdiutil",
      ["attach", "-readonly", "-nobrowse", "-mountpoint", volume, dmg],
      options,
    );
    mounted = true;
    invoke(
      "/bin/bash",
      [
        join(repository, "scripts/verify-release-artifact.sh"),
        join(volume, "Curfew.app"),
        configurationPath,
        candidate.version,
      ],
      options,
    );
  } finally {
    if (mounted) invoke("/usr/bin/hdiutil", ["detach", volume], options);
    await rm(temporary, { recursive: true, force: true });
  }
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const [command, candidatePath, evidencePath, nativeSourcePath] =
    process.argv.slice(2);
  assert.ok(
    command === "record" && candidatePath && evidencePath && nativeSourcePath,
    "Use record <candidate-directory> <private-evidence-directory> <native-source-checkout>",
  );
  const directory = resolve(candidatePath);
  const evidenceDirectory = resolve(evidencePath);
  const repository = fileURLToPath(new URL("../", import.meta.url));
  const nativeRepository = resolve(nativeSourcePath);
  const qualityBytes = await readFile(join(evidenceDirectory, "quality.json"));
  const signingBytes = await readFile(join(evidenceDirectory, "signing.json"));
  const quality = JSON.parse(qualityBytes);
  const signing = JSON.parse(signingBytes);
  assert.match(signing.version, /^0\.0\.(0|[1-9]\d*)$/);
  const configuration = JSON.parse(
    await readFile(join(directory, "release-configuration.json"), "utf8"),
  );
  const candidate = createCandidate({
    dmg: await readFile(join(directory, `Curfew-v${signing.version}.dmg`)),
    appcast: await readFile(join(directory, "appcast.xml")),
    configuration,
    version: signing.version,
    team: signing.developerIDTeam,
    sparkleKey: configuration.sparkleKey,
    provenance: {
      kind: "local",
      executionID: quality.executionID,
      qualitySHA256: localEvidenceHash(qualityBytes),
      signingSHA256: localEvidenceHash(signingBytes),
    },
  });
  const publicationCommit = execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: repository,
    encoding: "utf8",
  }).trim();
  verifyLocalRepositories(
    repository,
    nativeRepository,
    candidate.sourceCommit,
    publicationCommit,
  );
  await verifyLocalEvidence(evidenceDirectory, candidate);
  await verifyLocalDistribution(directory, candidate, nativeRepository);
  await writeFile(
    join(directory, "candidate.json"),
    JSON.stringify(candidate, null, 2) + "\n",
    { flag: "wx", mode: 0o600 },
  );
  console.log(
    "Local candidate recorded from verified retained bytes; no publication performed",
  );
}
