import { createHash } from "node:crypto";
import { readFile, writeFile } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";

import {
  verifyArtifact as verifyDeployment,
  resolveEnvironment,
} from "./deployment-config.mjs";

const digest = (bytes) => createHash("sha256").update(bytes).digest("hex");
export function createReleaseConfiguration({
  sourceCommit,
  appcast,
  sparkleKey,
  inputs,
  deployment,
}) {
  if (!deployment) throw new Error("Shared deployment artifact required");
  verifyDeployment(deployment, deployment.sha256, sourceCommit);
  const endpoint = resolveEnvironment(
    deployment.manifest.environments.production,
    "production",
  ).appcast;
  if (
    !/^[a-f0-9]{40}$/.test(sourceCommit) ||
    appcast !== endpoint ||
    typeof sparkleKey !== "string" ||
    !/^[A-Za-z0-9+/]{43}=$/.test(sparkleKey) ||
    Buffer.from(sparkleKey, "base64").length !== 32 ||
    !inputs ||
    !Object.keys(inputs).length
  )
    throw new Error(
      "Invalid release configuration; resolved feed must match the shared deployment",
    );
  const normalizedInputs = Object.fromEntries(
    Object.entries(inputs).sort(([a], [b]) => a.localeCompare(b)),
  );
  for (const [path, hash] of Object.entries(normalizedInputs))
    if (
      path.startsWith("/") ||
      path.includes("..") ||
      !/^[a-f0-9]{64}$/.test(hash)
    )
      throw new Error("Invalid release configuration source input");
  const identity = {
    schemaVersion: 1,
    sourceCommit,
    appcast,
    sparkleKey,
    inputs: normalizedInputs,
    deployment,
  };
  return Object.freeze({
    ...identity,
    sha256: digest(JSON.stringify(identity)),
  });
}

export function verifyArtifact(artifact, expectedHash, expectedCommit) {
  const actual = createReleaseConfiguration(artifact);
  if (
    artifact.schemaVersion !== 1 ||
    Object.keys(artifact).length !== Object.keys(actual).length ||
    actual.sha256 !== artifact.sha256 ||
    actual.sha256 !== expectedHash ||
    actual.sourceCommit !== expectedCommit
  )
    throw new Error("Release configuration identity mismatch");
  return actual;
}

// Seal signing identity and source bytes alongside the shared endpoint artifact.
export async function recordReleaseConfiguration(
  settings,
  root = fileURLToPath(new URL("../", import.meta.url)),
) {
  execFileSync("git", ["diff", "--quiet", "HEAD", "--"], { cwd: root });
  const app = settings.filter((value) => value.target === "Curfew");
  if (
    app.length !== 1 ||
    app[0].buildSettings.CONFIGURATION !== "Release" ||
    app[0].buildSettings.PRODUCT_BUNDLE_IDENTIFIER !== "studio.hypertext.apps.curfew"
  )
    throw new Error("Resolved production Release settings required");
  const sourceCommit = execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: root,
    encoding: "utf8",
  }).trim();
  const deployment = JSON.parse(
    await readFile(
      resolve(root, "deployment/generated/environment-artifact.json"),
      "utf8",
    ),
  );
  const inputs = {};
  for (const path of [
    "deployment/environments.json",
    "deployment/generated/CurfewEndpoints.xcconfig",
    "CurfewKit/Sources/CurfewKit/Sync/DeploymentProfile.generated.swift",
    "CurfewKit/Sources/CurfewKit/Sync/CurfewServiceEndpoints.swift",
    "Curfew/Core/Features/LicenseRefresher.swift",
    "Curfew.xcodeproj/project.pbxproj",
    "Curfew/Info.plist",
    "Curfew/Curfew-Release.entitlements",
    "CurfewWidget/CurfewWidget.entitlements",
    "CurfewKit/Package.swift",
    "CurfewKit/Package.resolved",
    "Curfew.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved",
  ])
    inputs[path] = digest(await readFile(resolve(root, path)));
  return createReleaseConfiguration({
    sourceCommit,
    inputs,
    deployment,
    appcast: app[0].buildSettings.INFOPLIST_KEY_SUFeedURL,
    sparkleKey: app[0].buildSettings.INFOPLIST_KEY_SUPublicEDKey,
  });
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  if (process.argv[2] !== "record" || !process.argv[3] || !process.argv[4])
    throw new Error(
      "Use record <resolved-release-settings.json> <release-configuration.json>",
    );
  const artifact = await recordReleaseConfiguration(
    JSON.parse(await readFile(process.argv[3], "utf8")),
  );
  await writeFile(process.argv[4], JSON.stringify(artifact, null, 2) + "\n", {
    flag: "wx",
  });
  process.stdout.write(artifact.sha256);
}
