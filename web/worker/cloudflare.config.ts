import { bindings, defineConfig } from "cf/config";
import { loadDeploymentArtifact } from "../../scripts/deployment-config.mjs";

export default defineConfig(async (ctx) => {
  if (!["production", "staging"].includes(ctx.mode || ""))
    throw new Error("Explicit license deployment mode required");
  const config = await loadDeploymentArtifact(ctx.mode);
  const production = ctx.mode === "production";
  const id = production
    ? "4313ea07769f4578a8fdd412620a412e"
    : process.env.CURFEW_LICENSE_KV_NAMESPACE_ID;
  if (!id || !/^[a-f0-9]{32}$/.test(id))
    throw new Error("Provisioned license KV namespace ID required");
  const retiredHosts = (config.retiredLicenseOrigins || []).map(
    (origin) => new URL(origin).host,
  );
  return {
    accountId: "2500680a3b2b0fe6a011c1c25fed5008",
    worker: {
      name: production
        ? "curfew-issue-license"
        : process.env.CURFEW_LICENSE_WORKER_NAME,
      entrypoint: "src/index.ts",
      compatibilityDate: "2026-07-31",
      workersDev: false,
      observability: { enabled: true },
      domains: [new URL(config.licenseOrigin).host, ...retiredHosts],
      env: {
        LICENSE_KV: bindings.kv({ id }),
        LICENSE_ORIGIN: bindings.text(config.licenseOrigin),
        CONFIGURATION_SHA256: bindings.text(config.sha256),
        CONFIGURATION_COMMIT: bindings.text(config.sourceCommit),
        RETIRED_LICENSE_HOSTS: bindings.text(JSON.stringify(retiredHosts)),
      },
    },
  };
});
