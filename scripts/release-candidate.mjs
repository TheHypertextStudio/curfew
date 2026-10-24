import {
  createHash,
  createPrivateKey,
  createPublicKey,
  verify,
} from "node:crypto";
import { readFile, writeFile, lstat } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { execFileSync, spawnSync } from "node:child_process";
import { isDeepStrictEqual } from "node:util";
import { verifyArtifact } from "./release-configuration.mjs";

export const activationGates = Object.freeze([
  "signedDevice",
  "retainedDataRecovery",
  "providerIdentity",
  "backendCutover",
  "assistantReconnect",
  "rollback",
  "commercialScope",
]);
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");

export async function verifyEmbeddedToolPackaging(app) {
  const tools = [
    "curfew-ctl",
    "curfew-mcp",
    "curfew-daemon",
    "studio.hypertext.curfew.browser",
    "curfew-supervisor",
  ];
  for (const tool of tools) {
    let entry;
    try {
      entry = await lstat(resolve(app, "Contents/Resources", tool));
    } catch {
      throw new Error(`Missing embedded executable: ${tool}`);
    }
    if (!entry.isFile() || !(entry.mode & 0o111))
      throw new Error(`Invalid embedded executable: ${tool}`);
  }
  // Distribution supports both Apple silicon and Intel. Do not let a narrowed
  // app or host-only SwiftPM product pass the signed artifact gate.
  const executablePaths = [
    resolve(app, "Contents/MacOS/Curfew"),
    ...tools.map((tool) => resolve(app, "Contents/Resources", tool)),
  ];
  let appArchitectures;
  for (const executable of executablePaths) {
    const architectures = execFileSync("/usr/bin/lipo", ["-archs", executable], {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    }).trim().split(/\s+/);
    appArchitectures ??= architectures;
    for (const required of new Set(["arm64", "x86_64", ...appArchitectures])) {
      if (!architectures.includes(required))
        throw new Error(`Missing architecture in ${executable}: ${required}`);
    }
  }
  return tools;
}

export function sparklePublicKey(seed) {
  if (typeof seed !== "string" || !/^[A-Za-z0-9+/]{43}=$/.test(seed))
    throw new Error("Sparkle private seed is unavailable or invalid");
  const raw = Buffer.from(seed, "base64");
  if (raw.length !== 32)
    throw new Error("Sparkle private seed is unavailable or invalid");
  const privateKey = createPrivateKey({
    key: Buffer.concat([
      Buffer.from("302e020100300506032b657004220420", "hex"),
      raw,
    ]),
    type: "pkcs8",
    format: "der",
  });
  return createPublicKey(privateKey)
    .export({ type: "spki", format: "der" })
    .subarray(-32)
    .toString("base64");
}

export function validateReleaseUpdateKey(settings, seed) {
  const app = settings.filter((value) => value.target === "Curfew");
  if (
    app.length !== 1 ||
    app[0].buildSettings.CONFIGURATION !== "Release" ||
    app[0].buildSettings.INFOPLIST_KEY_SUPublicEDKey !== sparklePublicKey(seed)
  )
    throw new Error(
      "Resolved Release Sparkle key does not match the configured signing seed",
    );
}

export function validateAppIdentity(info, signature, configuration, version) {
  verifyArtifact(
    configuration,
    configuration.sha256,
    configuration.sourceCommit,
  );
  const feed = configuration.appcast;
  if (
    !/^0\.0\.(0|[1-9]\d*)$/.test(version) ||
    !/^Authority=Developer ID Application: .+ \(T95VDD3A4W\)$/m.test(
      signature,
    ) ||
    !/^TeamIdentifier=T95VDD3A4W$/m.test(signature) ||
    info.CFBundleIdentifier !== "studio.hypertext.apps.curfew" ||
    info.CFBundleShortVersionString !== version ||
    info.CFBundleVersion !== version ||
    info.CurfewConfigurationCommit !== configuration.sourceCommit ||
    info.CurfewConfigurationSHA256 !== configuration.deployment.sha256 ||
    info.SUPublicEDKey !== configuration.sparkleKey ||
    info.SUFeedURL !== feed
  )
    throw new Error("Signed app identity/configuration mismatch");
}

export function createCandidate({
  dmg,
  appcast,
  configuration,
  version,
  team,
  sparkleKey,
  runID,
  provenance,
}) {
  const local = provenance?.kind === "local";
  const localKeys = ["executionID", "kind", "qualitySHA256", "signingSHA256"];
  if (
    !/^0\.0\.(0|[1-9]\d*)$/.test(version) ||
    team !== "T95VDD3A4W" ||
    (local
      ? runID !== undefined ||
        !isDeepStrictEqual(Object.keys(provenance).sort(), localKeys) ||
        !/^[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/.test(
          provenance.executionID,
        ) ||
        !/^[a-f0-9]{64}$/.test(provenance.qualitySHA256) ||
        !/^[a-f0-9]{64}$/.test(provenance.signingSHA256)
      : provenance !== undefined || !/^[1-9]\d*$/.test(runID))
  )
    throw new Error(
      "Candidate requires a 0.0.x version, Studio team and explicit valid provenance",
    );
  verifyArtifact(
    configuration,
    configuration.sha256,
    configuration.sourceCommit,
  );
  const feed = configuration.appcast;
  const xml = appcast.toString("utf8");
  if (sparkleKey !== configuration.sparkleKey)
    throw new Error(
      "Candidate public key does not match the resolved source snapshot",
    );
  const enclosures = [...xml.matchAll(/<enclosure\s+([^>]+)\/?\s*>/g)];
  const versions = [
    ...xml.matchAll(/<sparkle:version>([^<]+)<\/sparkle:version>/g),
  ];
  if (
    enclosures.length !== 1 ||
    versions.length !== 1 ||
    versions[0][1] !== version ||
    !xml.includes(`<link>${feed}</link>`)
  )
    throw new Error("Appcast identity mismatch");
  const attributes = Object.fromEntries(
    [...enclosures[0][1].matchAll(/([\w:]+)="([^"]*)"/g)].map((m) => [
      m[1],
      m[2],
    ]),
  );
  if (
    attributes.url !==
      `https://github.com/TheHypertextStudio/curfew/releases/download/v${version}/Curfew-v${version}.dmg` ||
    attributes.length !== String(dmg.length)
  )
    throw new Error("Appcast artifact mismatch");
  const rawKey = Buffer.from(sparkleKey, "base64");
  if (rawKey.length !== 32) throw new Error("Invalid Sparkle public key");
  const key = createPublicKey({
    key: Buffer.concat([
      Buffer.from("302a300506032b6570032100", "hex"),
      rawKey,
    ]),
    type: "spki",
    format: "der",
  });
  if (
    !verify(
      null,
      dmg,
      key,
      Buffer.from(attributes["sparkle:edSignature"] || "", "base64"),
    )
  )
    throw new Error(
      "Sparkle update signature does not match candidate bytes and app key",
    );
  return Object.freeze({
    schemaVersion: local ? 2 : 1,
    version,
    team,
    ...(local ? { provenance: Object.freeze({ ...provenance }) } : { runID }),
    sourceCommit: configuration.sourceCommit,
    configurationSHA256: configuration.deployment.sha256,
    releaseConfigurationSHA256: configuration.sha256,
    dmgSHA256: hash(dmg),
    appcastSHA256: hash(appcast),
    sparkleKey,
  });
}

export function verifyCandidate({ candidate, dmg, appcast, configuration }) {
  const actual = createCandidate({ ...candidate, dmg, appcast, configuration });
  if (
    Object.keys(candidate).length !== Object.keys(actual).length ||
    Object.entries(actual).some(
      ([key, value]) => !isDeepStrictEqual(candidate[key], value),
    )
  )
    throw new Error("Retained candidate identity mismatch");
  return actual;
}

export function inspectActivation(input, receipt) {
  const candidate = verifyCandidate(input);
  if (
    !receipt ||
    !receipt.operator?.trim() ||
    !Number.isFinite(Date.parse(receipt.observedAt)) ||
    !receipt.candidate ||
    Object.entries(candidate).some(
      ([key, value]) => !isDeepStrictEqual(receipt.candidate[key], value),
    )
  )
    throw new Error("Missing or mismatched owner acceptance receipt");
  for (const gate of activationGates) {
    if (
      receipt.gates?.[gate]?.outcome !== "pass" ||
      !receipt.gates[gate].evidence?.trim()
    )
      throw new Error(
        `Activation withheld: ${gate} requires actual acceptance evidence`,
      );
  }
  return {
    status: "eligible-for-owner-controlled-activation",
    candidate,
    warning:
      "Receipt references require owner review. This is not production verification and performs no publication or deployment.",
  };
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const [command, directory, receiptPath] = process.argv.slice(2);
  if (command === "embedded-tools") {
    process.stdout.write(
      (await verifyEmbeddedToolPackaging(directory)).join("\n") + "\n",
    );
    process.exit(0);
  }
  if (command === "derive-update-key") {
    // Only the public key leaves the process. Never log or persist the seed.
    process.stdout.write(sparklePublicKey(process.env.SPARKLE_PRIVATE_KEY));
    process.exit(0);
  }
  if (command === "verify-update-key") {
    validateReleaseUpdateKey(
      JSON.parse(await readFile(directory, "utf8")),
      process.env.SPARKLE_PRIVATE_KEY,
    );
    process.stdout.write("Resolved Release update key verified\n");
    process.exit(0);
  }
  if (command === "verify-app") {
    const configuration = JSON.parse(await readFile(receiptPath, "utf8"));
    const info = JSON.parse(
      execFileSync(
        "/usr/bin/plutil",
        [
          "-convert",
          "json",
          "-o",
          "-",
          resolve(directory, "Contents/Info.plist"),
        ],
        { encoding: "utf8" },
      ),
    );
    const signing = spawnSync(
      "/usr/bin/codesign",
      ["-dv", "--verbose=4", directory],
      { encoding: "utf8" },
    );
    if (signing.status !== 0)
      throw new Error("Cannot read signed app identity");
    validateAppIdentity(info, signing.stderr, configuration, process.argv[5]);
    process.stdout.write("Signed app identity and configuration verified\n");
    process.exit(0);
  }
  if (!["record", "inspect"].includes(command) || !directory)
    throw new Error(
      "Use record <candidate-directory> or inspect <candidate-directory> <owner-receipt.json>",
    );
  const configuration = JSON.parse(
    await readFile(resolve(directory, "release-configuration.json"), "utf8"),
  );
  const candidate =
    command === "inspect"
      ? JSON.parse(await readFile(resolve(directory, "candidate.json"), "utf8"))
      : {
          version: process.env.VERSION,
          team: process.env.CANDIDATE_TEAM,
          sparkleKey: process.env.SPARKLE_PUBLIC_KEY,
          runID: process.env.GITHUB_RUN_ID,
        };
  const input = {
    candidate,
    configuration,
    dmg: await readFile(resolve(directory, `Curfew-v${candidate.version}.dmg`)),
    appcast: await readFile(resolve(directory, "appcast.xml")),
  };
  if (command === "record") {
    const result = createCandidate({ ...candidate, ...input });
    await writeFile(
      resolve(directory, "candidate.json"),
      JSON.stringify(result, null, 2) + "\n",
      { flag: "wx" },
    );
  } else {
    const receipt = JSON.parse(await readFile(receiptPath, "utf8"));
    process.stdout.write(
      JSON.stringify(inspectActivation(input, receipt), null, 2) + "\n",
    );
  }
}
