import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  cp,
  lstat,
  readFile,
  readdir,
  rename,
  rm,
  writeFile,
} from "node:fs/promises";
import { join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createArtifact, resolveEnvironment } from "./deployment-config.mjs";
import { sealWebsite, verifyWebsite } from "./pages-artifact.mjs";

const options = () => ({
  redirect: "manual",
  cache: "no-store",
  signal: AbortSignal.timeout(15_000),
});
const hash = (bytes) => createHash("sha256").update(bytes).digest("hex");

function configuration(deployment) {
  const config = resolveEnvironment(
    deployment.manifest.environments.production,
    "production",
  );
  const legacy = new URL(config.legacySiteOrigin);
  assert.equal(legacy.protocol, "https:");
  assert.equal(legacy.origin, config.legacySiteOrigin);
  assert.notEqual(config.siteOrigin, legacy.origin);
  return config;
}

/** Publish the public site while preserving the existing service and app release. */
export async function preparePublicWebsite(input, fetcher = fetch) {
  const { website, websiteRun: run, currentMainCommit } = input;
  assert.equal(run.repository?.full_name, "TheHypertextStudio/curfew");
  assert.equal(run.status, "completed");
  assert.equal(run.conclusion, "success");
  assert.equal(run.event, "push");
  assert.equal(run.path, ".github/workflows/website.yml");
  assert.equal(run.head_branch, "main");
  assert.equal(run.head_sha, currentMainCommit);
  await verifyWebsite(
    website.directory,
    website.stamp,
    website.deployment,
    input.configurationSHA256 ?? website.deployment.sha256,
    currentMainCommit,
  );
  const config = configuration(website.deployment);
  for (const origin of [config.siteOrigin, config.legacySiteOrigin])
    assert.ok(
      input.domains.some(
        (domain) =>
          domain.name === new URL(origin).host && domain.status === "active",
      ),
      "Both Pages domains must be active",
    );
  assert.equal(
    (await fetcher(config.siteOrigin, { ...options(), method: "HEAD" })).status,
    200,
    "Website TLS and routing must be ready",
  );
  const accountPortal = new URL("/account", config.legacySiteOrigin).href;
  assert.equal(
    (await fetcher(accountPortal, options())).status,
    200,
    "Keep the existing account portal available",
  );
  const response = await fetcher(config.appcast, options());
  assert.ok(
    [200, 404].includes(response.status),
    "Cannot establish the existing native update feed",
  );
  let bytes;
  const feed = { status: response.status };
  if (response.status === 200) {
    bytes = Buffer.from(await response.arrayBuffer());
    assert.ok(
      bytes.length <= 2 * 1024 * 1024 &&
        /<rss(?:\s|>)/.test(bytes.toString("utf8")),
      "Existing appcast must be RSS",
    );
    feed.sha256 = hash(bytes);
  }
  await assert.rejects(
    () => lstat(input.destination),
    { code: "ENOENT" },
    "Publication output must be a fresh directory",
  );
  await cp(website.directory, input.destination, {
    recursive: true,
    force: false,
    errorOnExist: true,
  });
  const visit = async (directory) => {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      const path = join(directory, entry.name);
      if (entry.isDirectory()) await visit(path);
      else if (entry.name.endsWith(".html")) {
        const original = await readFile(path, "utf8");
        const updated = original.replace(
          /href=(["'])(\/account(?:[/?#][^"']*)?)\1/g,
          (_, quote, route) =>
            `href=${quote}${config.legacySiteOrigin}${route}${quote}`,
        );
        if (updated !== original) await writeFile(path, updated);
      }
    }
  };
  await visit(input.destination);
  const workerDirectory = join(input.destination, "_worker.js");
  await rename(
    join(workerDirectory, "index.js"),
    join(workerDirectory, "retained.js"),
  );
  await writeFile(
    join(workerDirectory, "index.js"),
    `import worker from './retained.js';
export default {...worker, fetch(request, env, context) {
  return worker.fetch(request, {...env, CURFEW_PUBLIC_SITE_ONLY: 'true'}, context);
}};
`,
    { flag: "wx" },
  );
  if (bytes) await writeFile(join(input.destination, "appcast.xml"), bytes);
  else await rm(join(input.destination, "appcast.xml"), { force: true });
  return {
    sourceCommit: currentMainCommit,
    configurationSHA256: website.deployment.sha256,
    accountPortal,
    feed,
    siteStamp: await sealWebsite(input.destination, website.deployment),
  };
}

export async function verifyPublicWebsite(
  deployment,
  publication,
  fetcher = fetch,
) {
  const config = configuration(deployment);
  assert.equal(publication.sourceCommit, deployment.sourceCommit);
  assert.equal(publication.configurationSHA256, deployment.sha256);
  const homepage = await fetcher(config.siteOrigin, options());
  assert.equal(homepage.status, 200);
  const html = await homepage.text();
  const canonicalTag = html.match(
    /<link\b(?=[^>]*\brel=["']canonical["'])[^>]*>/i,
  )?.[0];
  const canonical = new URL(
    canonicalTag?.match(/\bhref=["']([^"']+)["']/i)?.[1] ?? "about:blank",
  );
  assert.equal(
    canonical.origin,
    config.siteOrigin,
    "Homepage must identify the new canonical domain",
  );
  assert.ok(["/", "/index.html"].includes(canonical.pathname));
  const redirect = await fetcher(
    `${config.legacySiteOrigin}/download?curfew_migration_check=1`,
    options(),
  );
  assert.equal(redirect.status, 308);
  assert.equal(
    redirect.headers.get("location"),
    `${config.siteOrigin}/download?curfew_migration_check=1`,
  );
  assert.equal(
    (await fetcher(publication.accountPortal, options())).status,
    200,
    "Existing account access changed",
  );
  const feed = await fetcher(config.appcast, options());
  assert.equal(feed.status, publication.feed.status);
  if (feed.status === 200)
    assert.equal(
      hash(Buffer.from(await feed.arrayBuffer())),
      publication.feed.sha256,
      "Existing signed feed changed",
    );
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const [action, directory] = process.argv.slice(2);
  assert.ok(["prepare", "verify"].includes(action));
  const json = async (path) =>
    JSON.parse(await readFile(join(directory, path), "utf8"));
  const deployment = await json("identity/environment-artifact.json");
  if (action === "prepare") {
    const manifest = JSON.parse(
      await readFile(
        new URL("../deployment/environments.json", import.meta.url),
        "utf8",
      ),
    );
    const inventory = await json("pages-domains.json");
    const publication = await preparePublicWebsite({
      website: {
        directory: join(directory, "website"),
        deployment,
        stamp: await json("website-build/website-build.json"),
      },
      websiteRun: await json("website-run.json"),
      domains: inventory.result ?? inventory,
      currentMainCommit: process.env.GITHUB_SHA,
      configurationSHA256: createArtifact(manifest, process.env.GITHUB_SHA)
        .sha256,
      destination: join(directory, "site-ready"),
    });
    await writeFile(
      join(directory, "publication.json"),
      JSON.stringify(publication, null, 2) + "\n",
      { flag: "wx" },
    );
    console.log(JSON.stringify(publication));
  } else {
    await verifyPublicWebsite(deployment, await json("publication.json"));
    console.log(
      "Public website and redirect verified; existing account and native feed state preserved.",
    );
  }
}
