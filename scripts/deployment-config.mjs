import { createHash } from "node:crypto";
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import { resolve } from "node:path";

export function resolveEnvironment(input, mode) {
  if (!["production", "staging", "local"].includes(mode) || !input)
    throw new Error("Unknown deployment environment");
  const output = { ...input };
  for (const key of [
    "siteOrigin",
    "accountOrigin",
    "syncOrigin",
    "licenseOrigin",
    ...(input.purchasePortalOrigin === undefined
      ? []
      : ["purchasePortalOrigin"]),
  ]) {
    const value = input[key];
    if (typeof value !== "string") throw new Error(`Missing ${key}`);
    const url = new URL(value);
    const local =
      mode === "local" &&
      ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
    if (
      (url.protocol !== "https:" && !(local && url.protocol === "http:")) ||
      url.username ||
      url.password ||
      url.pathname !== "/" ||
      url.search ||
      url.hash ||
      (!local && url.port) ||
      value !== url.origin
    )
      throw new Error(`Invalid ${key}`);
    output[key] = url.origin;
  }
  output.purchasePortalOrigin ??= output.siteOrigin;
  if (input.passkeyRPID !== new URL(output.siteOrigin).hostname)
    throw new Error("Passkey identity must match the approved portal host");
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(input.recoveryEmailFrom))
    throw new Error("Invalid recovery email sender");
  const at = (origin, path) => new URL(path, origin).href;
  return Object.freeze({
    ...output,
    accountPortal: at(output.siteOrigin, "/account"),
    mcpResource: at(output.syncOrigin, "/mcp"),
    remoteCommandJWKS: at(
      output.syncOrigin,
      "/.well-known/curfew-command-jwks.json",
    ),
    nativeCallback: at(output.accountOrigin, "/oauth/callback/native/macos"),
    appcast: at(output.siteOrigin, "/appcast.xml"),
    pricing: at(output.purchasePortalOrigin, "/#plus"),
  });
}

export function createArtifact(manifest, sourceCommit) {
  if (manifest.version !== 1 || !/^[a-f0-9]{40}$/.test(sourceCommit))
    throw new Error("Invalid manifest revision");
  const normalized = { version: 1, environments: {} };
  for (const mode of Object.keys(manifest.environments).sort()) {
    const env = resolveEnvironment(manifest.environments[mode], mode);
    normalized.environments[mode] = Object.fromEntries(
      Object.keys(manifest.environments[mode])
        .sort()
        .map((key) => [key, env[key]]),
    );
  }
  if (normalized.environments.production && normalized.environments.staging) {
    const keys = ["siteOrigin", "accountOrigin", "syncOrigin", "licenseOrigin"];
    const origins = (environment) => [
      ...keys.map((key) => environment[key]),
      environment.purchasePortalOrigin ?? environment.siteOrigin,
    ];
    const production = new Set(origins(normalized.environments.production));
    if (
      origins(normalized.environments.staging).some((origin) =>
        production.has(origin),
      )
    )
      throw new Error("Production and staging origins must be isolated");
  }
  return {
    sourceCommit,
    sha256: createHash("sha256")
      .update(JSON.stringify(normalized))
      .digest("hex"),
    manifest: normalized,
  };
}

export function verifyArtifact(artifact, expectedHash, expectedCommit) {
  const validated = createArtifact(artifact.manifest, artifact.sourceCommit);
  if (
    !/^[a-f0-9]{64}$/.test(expectedHash) ||
    validated.sha256 !== artifact.sha256 ||
    artifact.sha256 !== expectedHash ||
    artifact.sourceCommit !== expectedCommit
  )
    throw new Error("Deployment artifact identity mismatch");
  return artifact;
}

export function nativeBuildIdentity(artifact) {
  verifyArtifact(artifact, artifact.sha256, artifact.sourceCommit);
  return `// Generated build provenance.\nCURFEW_CONFIGURATION_COMMIT = ${artifact.sourceCommit}\nCURFEW_CONFIGURATION_SHA256 = ${artifact.sha256}\n`;
}

export async function loadEnvironment(mode = "production") {
  const manifest = JSON.parse(
    await readFile(
      new URL("../deployment/environments.json", import.meta.url),
      "utf8",
    ),
  );
  return resolveEnvironment(manifest.environments[mode], mode);
}

export async function loadDeploymentArtifact(
  mode,
  {
    artifactPath = process.env.CURFEW_DEPLOYMENT_ARTIFACT,
    expectedHash = process.env.CURFEW_CONFIGURATION_SHA256,
    expectedCommit = process.env.CURFEW_CONFIGURATION_COMMIT,
  } = {},
) {
  if (!artifactPath)
    throw new Error("An approved deployment artifact is required");
  const artifact = verifyArtifact(
    JSON.parse(await readFile(artifactPath, "utf8")),
    expectedHash,
    expectedCommit,
  );
  return Object.freeze({
    ...resolveEnvironment(artifact.manifest.environments[mode], mode),
    sourceCommit: artifact.sourceCommit,
    sha256: artifact.sha256,
  });
}

export async function generateDeployment(
  root = fileURLToPath(new URL("../", import.meta.url)),
) {
  const manifest = JSON.parse(
    await readFile(resolve(root, "deployment/environments.json"), "utf8"),
  );
  const sourceCommit = execFileSync("git", ["rev-parse", "HEAD"], {
    cwd: root,
    encoding: "utf8",
  }).trim();
  const artifact = createArtifact(manifest, sourceCommit);
  await mkdir(resolve(root, "deployment/generated"), { recursive: true });
  await writeFile(
    resolve(root, "deployment/generated/environment-artifact.json"),
    JSON.stringify(artifact, null, 2) + "\n",
  );
  await writeFile(
    resolve(root, "deployment/generated/environments.mjs"),
    "// Generated deployment endpoints.\nexport default " +
      JSON.stringify(
        Object.fromEntries(
          Object.entries(manifest.environments).map(([mode, value]) => [
            mode,
            resolveEnvironment(value, mode),
          ]),
        ),
        null,
        2,
      ) +
      ";\n",
  );
  const production = resolveEnvironment(
    manifest.environments.production,
    "production",
  );
  await writeFile(
    resolve(root, "deployment/generated/CurfewEndpoints.xcconfig"),
    '// Generated deployment configuration.\n#include? "CurfewBuildIdentity.xcconfig"\nCURFEW_APPCAST_URL = ' +
      production.appcast.replace("://", ":/$()/") +
      "\n",
  );
  await writeFile(
    resolve(root, "deployment/generated/CurfewBuildIdentity.xcconfig"),
    nativeBuildIdentity(artifact),
  );
  for (const name of [
    "Curfew/Curfew-Release.entitlements",
    "Curfew/Curfew.entitlements",
  ]) {
    const path = resolve(root, name);
    const original = await readFile(path, "utf8");
    const text = original.replace(
      /(applinks|webcredentials):([^<\s]+)/g,
      (_match, kind) =>
        kind +
        ":" +
        new URL(
          name.includes("Release")
            ? production.accountOrigin
            : manifest.environments.staging.accountOrigin,
        ).host,
    );
    await writeFile(path, text);
  }
  for (const name of ["sitemap.xml", "robots.txt"]) {
    const path = resolve(root, "landing/public", name);
    await writeFile(
      path,
      (await readFile(path, "utf8")).replace(
        /https:\/\/[^/<\s]+/g,
        production.siteOrigin,
      ),
    );
  }
  const profiles = ["production", "staging"]
    .map((mode) => {
      const e = resolveEnvironment(manifest.environments[mode], mode);
      const fields = [
        "siteOrigin",
        "purchasePortalOrigin",
        "accountOrigin",
        "syncOrigin",
        "licenseOrigin",
      ];
      return `    static let ${mode} = DeploymentProfile(\n${fields.map((key) => `        ${key}: ${JSON.stringify(e[key])}`).join(",\n")}\n    )`;
    })
    .join("\n");
  await writeFile(
    resolve(
      root,
      "CurfewKit/Sources/CurfewKit/Sync/DeploymentProfile.generated.swift",
    ),
    `// Generated by scripts/deployment-config.mjs. Edit deployment/environments.json.\nimport Foundation\n\nstruct DeploymentProfile {\n    let siteOrigin: String\n    let purchasePortalOrigin: String\n    let accountOrigin: String\n    let syncOrigin: String\n    let licenseOrigin: String\n${profiles}\n}\n`,
  );
  return artifact;
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  if (process.argv[2] === "generate") await generateDeployment();
  else if (process.argv[2] === "get") {
    const env = await loadEnvironment(
      process.env.CURFEW_DEPLOYMENT_MODE || "production",
    );
    if (!(process.argv[3] in env)) throw new Error("Unknown endpoint");
    process.stdout.write(env[process.argv[3]]);
  } else throw new Error("Use generate or get <endpoint>");
}
