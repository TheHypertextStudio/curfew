import { spawnSync } from "node:child_process";
import { loadEnvironment } from "./deployment-config.mjs";
const mode = process.argv[2] || "preflight";
if (!["preflight", "attach-site"].includes(mode))
  throw new Error("Use preflight or attach-site");
if (!process.env.CLOUDFLARE_API_TOKEN || !process.env.CLOUDFLARE_ACCOUNT_ID)
  throw new Error(
    "Cloudflare API token and explicit account ID required; interactive authentication is disabled",
  );
const config = await loadEnvironment("production");
const host = new URL(config.siteOrigin).host;
function cf(args) {
  const result = spawnSync("pnpm", ["exec", "cf", ...args], {
    encoding: "utf8",
    env: process.env,
  });
  if (result.status !== 0)
    throw new Error(`cf operation failed: ${args.slice(0, 3).join(" ")}`);
  return JSON.parse(result.stdout);
}
const zones = cf(["zones", "list", "--name", host]);
const zone = (Array.isArray(zones) ? zones : zones.result)?.find(
  (zone) => zone.name === host,
);
if (!zone || zone.status !== "active")
  throw new Error(
    "The new Cloudflare zone is absent or not active; configure registrar delegation first",
  );
const domains = cf([
  "pages",
  "domains",
  "list",
  "--project-name",
  "curfew-landing",
]);
const existing = (Array.isArray(domains) ? domains : domains.result)?.find(
  (domain) => domain.name === host,
);
if (mode === "attach-site" && !existing)
  cf(["pages", "domains", "create", "curfew-landing", "--name", host]);
console.log(
  JSON.stringify({
    mode,
    zoneId: zone.id,
    siteHost: host,
    domainStatus: existing?.status || "activation-required",
  }),
);
