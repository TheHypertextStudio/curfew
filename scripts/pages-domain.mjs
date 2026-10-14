import { spawnSync } from "node:child_process";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export function preparePagesDomain(invoke, { siteOrigin, project, action }) {
  const url = new URL(siteOrigin);
  if (
    url.protocol !== "https:" ||
    siteOrigin !== url.origin ||
    url.username ||
    url.password ||
    url.port
  )
    throw new Error("A configured HTTPS website origin is required");
  if (
    !["status", "preview", "attach"].includes(action) ||
    !/^[a-z0-9][a-z0-9-]*$/.test(project)
  )
    throw new Error("Invalid Pages operation");
  const hostname = url.hostname;
  const domains = invoke([
    "pages",
    "domains",
    "list",
    "--project-name",
    project,
  ]);
  if (!Array.isArray(domains)) throw new Error("Invalid Pages inventory");
  const existing = domains.some((domain) => domain.name === hostname);
  if (!existing && action === "status")
    return { hostname, status: "absent", changed: false };
  if (!existing && action === "preview") {
    invoke([
      "pages",
      "domains",
      "create",
      project,
      "--name",
      hostname,
      "--dry-run",
    ]);
    return { hostname, status: "preview", changed: false };
  }
  if (!existing)
    invoke(["pages", "domains", "create", project, "--name", hostname]);
  const domain = invoke([
    "pages",
    "domains",
    "get",
    hostname,
    "--project-name",
    project,
  ]);
  if (
    domain?.name !== hostname ||
    typeof domain.status !== "string" ||
    !domain.status
  )
    throw new Error("Invalid Pages domain readback");
  return { hostname, status: domain.status, changed: !existing };
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  if (!process.env.CLOUDFLARE_API_TOKEN || !process.env.CLOUDFLARE_ACCOUNT_ID)
    throw new Error("An approved API token and explicit account are required");
  const source = resolve(
    process.env.CURFEW_CONFIGURATION_SOURCE || ".configuration-source",
  );
  const { verifyArtifact } = await import(
    pathToFileURL(resolve(source, "scripts/deployment-config.mjs"))
  );
  const artifact = verifyArtifact(
    JSON.parse(
      await readFile(
        resolve(source, "deployment/generated/environment-artifact.json"),
        "utf8",
      ),
    ),
    process.env.CURFEW_CONFIGURATION_SHA256,
    process.env.CURFEW_CONFIGURATION_COMMIT,
  );
  const invoke = (args) => {
    const result = spawnSync(resolve(source, "node_modules/.bin/cf"), args, {
      cwd: source,
      env: process.env,
      encoding: "utf8",
      timeout: 60_000,
    });
    if (result.status !== 0) {
      const status = /\b(401|403|404)\b/.exec(result.stderr || "")?.[1];
      throw new Error(
        `cf Pages operation failed${status ? ` (HTTP ${status})` : ""}`,
      );
    }
    if (args.includes("--dry-run")) return null;
    const value = JSON.parse(result.stdout);
    return value.result ?? value;
  };
  console.log(
    JSON.stringify({
      ...preparePagesDomain(invoke, {
        siteOrigin: artifact.manifest.environments.production.siteOrigin,
        project: "curfew-landing",
        action: process.argv[2],
      }),
      configurationCommit: artifact.sourceCommit,
      configurationSHA256: artifact.sha256,
    }),
  );
}
