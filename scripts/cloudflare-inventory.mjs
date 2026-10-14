import { spawnSync } from "node:child_process";
import { resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { loadEnvironment } from "./deployment-config.mjs";

/** Capability inventory only: no credentials, account records, or configuration values. */
export function collectInventory(invoke, siteHost) {
  const operations = [
    ["accounts", ["accounts", "list"]],
    ["zone", ["zones", "list", "--name", siteHost]],
    [
      "siteDomains",
      ["pages", "domains", "list", "--project-name", "curfew-landing"],
    ],
    [
      "accountDeployments",
      ["workers", "deployments", "list", "--worker", "curfew-account-platform"],
    ],
    [
      "accountSecretNames",
      ["workers", "secrets", "list", "--worker", "curfew-account-platform"],
    ],
    [
      "licenseSecretNames",
      ["workers", "secrets", "list", "--worker", "curfew-issue-license"],
    ],
  ];
  return operations.map(([operation, args]) => {
    const result = invoke(args);
    if (result.status !== 0)
      return {
        operation,
        status: "unavailable",
        httpStatus: /\b(401|403|404)\b/.exec(result.stderr || "")?.[1] || null,
      };
    try {
      const value = JSON.parse(result.stdout);
      const data = value.result ?? value;
      const rows = Array.isArray(data) ? data : data.deployments;
      if (!Array.isArray(rows)) throw new Error("Unexpected inventory shape");
      return {
        operation,
        status: "available",
        count: rows.length,
        ...(operation === "zone" || operation === "siteDomains"
          ? {
              resources: rows.map(({ id, name, status }) => ({
                id,
                name,
                status,
              })),
            }
          : operation.endsWith("SecretNames")
            ? { names: rows.map(({ name }) => name) }
            : {}),
      };
    } catch {
      return { operation, status: "invalid-response" };
    }
  });
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  if (!process.env.CLOUDFLARE_API_TOKEN || !process.env.CLOUDFLARE_ACCOUNT_ID)
    throw new Error(
      "Existing Cloudflare API token and explicit account are required",
    );
  const config = await loadEnvironment("production");
  const output = collectInventory(
    (args) =>
      spawnSync(resolve("node_modules/.bin/cf"), args, {
        encoding: "utf8",
        env: process.env,
        timeout: 60_000,
      }),
    new URL(config.siteOrigin).host,
  );
  console.log(JSON.stringify(output, null, 2));
}
