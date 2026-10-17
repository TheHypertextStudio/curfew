import test from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";

const read = (path) => readFile(new URL(`../${path}`, import.meta.url), "utf8");

test("web checks use the signed Studio cache in their own namespace", async () => {
  const config = JSON.parse(await read("web/turbo.json"));
  assert.equal(
    config.remoteCache.apiUrl,
    "https://turbo-cache.hypertext.studio",
  );
  assert.equal(config.remoteCache.teamSlug, "curfew-web");
  assert.equal(config.remoteCache.signature, true);
  assert.equal(config.tasks.deploy.cache, false);
  assert.equal(config.tasks.dev.cache, false);
  const pkg = JSON.parse(await read("web/package.json"));
  assert.equal(pkg.scripts.typecheck, "turbo run typecheck");
});

test("only trusted main web checks receive remote cache credentials", async () => {
  const workflow = await read(".github/workflows/website.yml");
  const license = workflow.split("  license:\n")[1].split("\n  website:")[0];
  assert.match(license, /TURBO_CACHE: local:rw/);
  assert.match(license, /id-token: write/);
  assert.match(license, /TheHypertextStudio\/curfew/);
  assert.match(license, /github\.ref == 'refs\/heads\/main'/);
  assert.match(license, /github\.event_name == 'push'/);
  assert.match(license, /github\.event_name == 'workflow_dispatch'/);
  assert.match(
    license,
    /github\.workflow_ref == 'TheHypertextStudio\/curfew\/\.github\/workflows\/website\.yml@refs\/heads\/main'/,
  );
  assert.match(license, /TURBO_REMOTE_CACHE_SIGNATURE_KEY:/);
  assert.match(
    license,
    /TheHypertextStudio\/release-engineering\/actions\/turbo-cache@[a-f0-9]{40}/,
  );
  assert.match(license, /id: turbo-cache/);
  assert.match(license, /api: \$\{\{ vars\.TURBO_API \}\}/);
  assert.match(license, /team: \$\{\{ vars\.TURBO_TEAM \}\}/);
  assert.match(
    license,
    /service-account: \$\{\{ vars\.GCP_TURBO_CACHE_SERVICE_ACCOUNT \}\}/,
  );
  assert.match(
    license,
    /workload-identity-provider: \$\{\{ vars\.GCP_TURBO_CACHE_WIF_PROVIDER \}\}/,
  );
  assert.match(license, /node --test scripts\/turbo-cache\.test\.mjs/);
  assert.match(license, /pnpm --dir web typecheck/);
  assert.ok(
    license.indexOf("id: turbo-cache") <
      license.indexOf("pnpm --dir web typecheck"),
  );
  const rest = workflow.split("\n  website:")[1];
  assert.doesNotMatch(rest, /id-token: write|TURBO_REMOTE_CACHE_SIGNATURE_KEY/);
});
