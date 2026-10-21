import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, writeFile, cp, lstat } from "node:fs/promises";
import { execFileSync } from "node:child_process";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { inspectActivation } from "./release-candidate.mjs";
import { resolveEnvironment } from "./deployment-config.mjs";
import { verifyWebsite, sealWebsite } from "./website-artifact.mjs";
import {
  verifyLocalEvidence,
  verifyLocalRepositories,
  verifyLocalDistribution,
} from "./local-release.mjs";

const pendingDownload =
  "<p>The public Mac download is coming soon. The installer will be available here when it is ready.</p>";
const pendingInstallation = "<h2>When the download is available</h2>";

function installerURL(candidate) {
  assert.match(candidate.version, /^0\.0\.(0|[1-9]\d*)$/);
  return `https://github.com/TheHypertextStudio/curfew/releases/download/v${candidate.version}/Curfew-v${candidate.version}.dmg`;
}

function replaceOnce(html, expected, replacement) {
  assert.equal(
    html.split(expected).length,
    2,
    "Unknown or ambiguous download availability",
  );
  return html.replace(expected, replacement);
}

/** A derived publication page; the sealed website input remains untouched. */
export function renderPublishedDownload(html, candidate) {
  return replaceOnce(
    replaceOnce(
      html,
      pendingDownload,
      `<p><a class="button primary" href="${installerURL(candidate)}">Download Curfew ${candidate.version}</a></p>`,
    ),
    pendingInstallation,
    "<h2>Install Curfew</h2>",
  );
}

export function renderPublishedHome(html) {
  for (const [expected, replacement] of [
    [
      "Coming soon · Free &amp; open source · macOS 26+",
      "Free &amp; open source · macOS 26+",
    ],
    [
      "The public Mac download is coming soon. Check the",
      "Download Curfew from the",
    ],
    ["for availability and installation", "for installation"],
  ])
    html = replaceOnce(html, expected, replacement);
  return html;
}

async function verifyLocalPublication(input) {
  const candidate = input.native.candidate;
  verifyLocalRepositories(
    input.local.repository,
    input.local.nativeRepository,
    candidate.sourceCommit,
    input.local.publicationCommit,
  );
  await verifyLocalEvidence(
    input.local.evidenceDirectory,
    candidate,
    input.now,
  );
  await verifyLocalDistribution(
    input.local.candidateDirectory,
    candidate,
    input.local.nativeRepository,
  );
}

async function admit(input, localVerifier = verifyLocalPublication) {
  const { candidate } = inspectActivation(input.native, input.receipt);
  const observed = Date.parse(input.receipt.observedAt);
  const now = input.now ?? Date.now();
  assert.ok(
    observed <= now && now - observed <= 3_600_000,
    "Fresh owner acceptance is required",
  );
  const local = candidate.provenance?.kind === "local";
  const runs = [[input.websiteRun, ".github/workflows/website.yml", "main"]];
  if (local) {
    assert.equal(
      input.candidateRun,
      undefined,
      "A local candidate cannot claim a hosted run",
    );
    assert.match(input.local?.publicationCommit ?? "", /^[a-f0-9]{40}$/);
    assert.equal(
      input.currentMainCommit,
      input.local.publicationCommit,
      "Publication source changed after local validation",
    );
    assert.equal(
      input.receipt.gates?.stagingAcceptance?.outcome,
      "pass",
      "Actual staging acceptance is required",
    );
    assert.ok(
      input.receipt.gates.stagingAcceptance.evidence?.trim(),
      "Staging evidence is required",
    );
    await localVerifier(input);
  } else {
    assert.equal(
      input.currentMainCommit,
      candidate.sourceCommit,
      "Main changed after candidate validation",
    );
    runs.unshift([
      input.candidateRun,
      ".github/workflows/release.yml",
      `v${candidate.version}`,
    ]);
  }
  for (const [run, path, branch] of runs) {
    assert.equal(run.repository?.full_name, "TheHypertextStudio/curfew");
    assert.equal(run.status, "completed");
    assert.equal(run.conclusion, "success");
    assert.equal(run.event, "push");
    assert.equal(run.path, path);
    assert.equal(run.head_branch, branch);
    assert.equal(run.head_sha, candidate.sourceCommit);
  }
  if (!local) assert.equal(String(input.candidateRun.id), candidate.runID);
  await verifyWebsite(
    input.website.directory,
    input.website.stamp,
    input.website.deployment,
    candidate.configurationSHA256,
    candidate.sourceCommit,
  );
  return candidate;
}

export async function preparePublication(
  input,
  localVerifier = verifyLocalPublication,
) {
  const candidate = await admit(input, localVerifier);
  const download = renderPublishedDownload(
    await readFile(join(input.website.directory, "download.html"), "utf8"),
    candidate,
  );
  const home = renderPublishedHome(
    await readFile(join(input.website.directory, "index.html"), "utf8"),
  );
  await assert.rejects(
    () => lstat(input.destination),
    { code: "ENOENT" },
    "Publication output must be a fresh directory",
  );
  await cp(input.website.directory, input.destination, {
    recursive: true,
    force: false,
    errorOnExist: true,
  });
  await writeFile(join(input.destination, "appcast.xml"), input.native.appcast);
  await writeFile(join(input.destination, "download.html"), download);
  await writeFile(join(input.destination, "index.html"), home);
  return {
    candidate,
    ...(candidate.provenance?.kind === "local"
      ? { publicationCommit: input.local.publicationCommit }
      : {}),
    siteStamp: await sealWebsite(input.destination, input.website.deployment),
  };
}

const requestOptions = () => ({
  redirect: "manual",
  cache: "no-store",
  signal: AbortSignal.timeout(15_000),
});
export async function checkPublicationReadiness(config, fetcher = fetch) {
  assert.equal(
    (await fetcher(config.siteOrigin, { ...requestOptions(), method: "HEAD" }))
      .status,
    200,
    "New website TLS and routing must be ready",
  );
  for (const origin of [
    config.accountOrigin,
    config.syncOrigin,
    config.licenseOrigin,
  ]) {
    const response = await fetcher(`${origin}/health`, requestOptions());
    assert.equal(response.status, 200, "Service health must be available");
    assert.equal(
      response.headers.get("x-curfew-configuration"),
      config.sha256,
      "Service configuration mismatch",
    );
    if (origin === config.licenseOrigin)
      assert.equal(
        response.headers.get("x-curfew-configuration-commit"),
        config.sourceCommit,
      );
    else
      assert.equal(
        response.headers.get("x-curfew-maintenance"),
        "true",
        "Account authority must remain in maintenance during publication",
      );
  }
}

export async function verifyLivePublication(
  config,
  candidate,
  fetcher = fetch,
) {
  const homepage = await fetcher(config.siteOrigin, requestOptions());
  assert.equal(homepage.status, 200);
  const homeHTML = await homepage.text();
  assert.ok(
    homeHTML.includes('href="/download"'),
    "Homepage does not link the download page",
  );
  for (const stale of [
    "Coming soon · Free",
    "The public Mac download is coming soon.",
  ])
    assert.ok(
      !homeHTML.includes(stale),
      "Homepage still reports the installer unavailable",
    );
  const url = installerURL(candidate);
  const page = await fetcher(`${config.siteOrigin}/download`, requestOptions());
  assert.equal(page.status, 200, "Customer download page is unavailable");
  const html = await page.text();
  assert.ok(
    html.includes(`href="${url}"`),
    "Customer download page does not link the accepted installer",
  );
  assert.ok(
    !html.includes("The public Mac download is coming soon."),
    "Customer download page still reports unavailable",
  );
  const installer = await fetcher(url, {
    ...requestOptions(),
    redirect: "follow",
  });
  assert.equal(
    installer.status,
    200,
    "Customer installer download is unavailable",
  );
  assert.equal(
    createHash("sha256")
      .update(Buffer.from(await installer.arrayBuffer()))
      .digest("hex"),
    candidate.dmgSHA256,
    "Customer installer differs from the signed candidate",
  );
  const feed = await fetcher(
    `${config.siteOrigin}/appcast.xml`,
    requestOptions(),
  );
  assert.equal(feed.status, 200);
  assert.equal(
    createHash("sha256")
      .update(Buffer.from(await feed.arrayBuffer()))
      .digest("hex"),
    candidate.appcastSHA256,
    "Live update feed differs from the signed candidate",
  );
  const redirect = await fetcher(
    `${config.legacySiteOrigin}/download?curfew_migration_check=1`,
    requestOptions(),
  );
  assert.equal(redirect.status, 308);
  assert.equal(
    redirect.headers.get("location"),
    `${config.siteOrigin}/download?curfew_migration_check=1`,
  );
  const retired = await fetcher(
    `${config.legacySiteOrigin}/api/auth/callback/google?code=retirement-check`,
    requestOptions(),
  );
  assert.equal(retired.status, 410);
  assert.equal(retired.headers.get("location"), null);
}

const repository = "TheHypertextStudio/curfew";
export function publishGithubRelease(
  invoke,
  candidate,
  expectedAssets,
  directory,
  publicationCommit = candidate.sourceCommit,
) {
  assert.match(candidate.version, /^0\.0\.(0|[1-9]\d*)$/);
  const tag = `v${candidate.version}`;
  assert.match(publicationCommit, /^[a-f0-9]{40}$/);
  if (candidate.provenance?.kind !== "local")
    assert.equal(
      publicationCommit,
      candidate.sourceCommit,
      "A hosted candidate must retain its exact source head",
    );
  assert.deepEqual(
    Object.keys(expectedAssets).sort(),
    [`Curfew-${tag}.dmg`, "appcast.xml", "candidate.json"].sort(),
  );
  for (const digest of Object.values(expectedAssets))
    assert.match(digest, /^[a-f0-9]{64}$/);
  const head = invoke(["api", `repos/${repository}/git/ref/heads/main`]);
  assert.equal(
    head.object?.sha,
    publicationCommit,
    "Main changed before publication",
  );
  let reference = invoke([
    "api",
    `repos/${repository}/git/ref/tags/${tag}`,
  ]).object;
  if (reference?.type === "tag") {
    assert.match(reference.sha, /^[a-f0-9]{40}$/);
    reference = invoke([
      "api",
      `repos/${repository}/git/tags/${reference.sha}`,
    ]).object;
  }
  assert.equal(reference?.type, "commit");
  assert.equal(
    reference.sha,
    candidate.sourceCommit,
    "Release tag changed before publication",
  );
  const get = () => {
    const published = invoke([
      "api",
      `repos/${repository}/releases/tags/${tag}`,
    ]);
    if (published) return published;
    // The tag endpoint excludes pending drafts. The authenticated list includes
    // them, and pagination keeps retries independent of release-list ordering.
    const matches = invoke([
      "api",
      `repos/${repository}/releases`,
      "--paginate",
      "--slurp",
    ])
      .flat()
      .filter((value) => value.tag_name === tag);
    assert.ok(matches.length <= 1, "Multiple releases claim the candidate tag");
    return matches[0] ?? null;
  };
  let release = get();
  if (!release) {
    invoke([
      "release",
      "create",
      tag,
      "--repo",
      repository,
      "--verify-tag",
      "--draft",
      "--title",
      `Curfew ${candidate.version}`,
      "--notes-file",
      join(directory, "public-release-notes.md"),
    ]);
    release = get();
  }
  assert.ok(release, "Created release could not be read back");
  assert.equal(release.tag_name, tag);
  for (const [name, digest] of Object.entries(expectedAssets)) {
    const asset = release.assets.find((value) => value.name === name);
    if (asset)
      assert.equal(
        asset.digest,
        `sha256:${digest}`,
        `Published asset mismatch: ${name}`,
      );
    else {
      assert.ok(release.draft, `Public release is missing asset: ${name}`);
      invoke([
        "release",
        "upload",
        tag,
        join(directory, name),
        "--repo",
        repository,
      ]);
    }
  }
  if (!release.draft) return "reused";
  assert.ok(
    Number.isSafeInteger(release.id) && release.id > 0,
    "Invalid draft release ID",
  );
  release = invoke(["api", `repos/${repository}/releases/${release.id}`]);
  assert.equal(release.tag_name, tag);
  assert.equal(release.draft, true, "Draft changed during asset upload");
  for (const [name, digest] of Object.entries(expectedAssets))
    assert.equal(
      release.assets.find((value) => value.name === name)?.digest,
      `sha256:${digest}`,
      `Uploaded asset mismatch: ${name}`,
    );
  invoke([
    "release",
    "edit",
    tag,
    "--repo",
    repository,
    "--draft=false",
    "--prerelease=false",
    "--latest",
  ]);
  return "published";
}

async function load(base) {
  const json = async (path) =>
    JSON.parse(await readFile(join(base, path), "utf8"));
  const candidate = await json("candidate/candidate.json");
  assert.match(candidate.version, /^0\.0\.(0|[1-9]\d*)$/);
  const local = candidate.provenance?.kind === "local";
  const authority = local ? await json("local-authority.json") : undefined;
  return {
    native: {
      candidate,
      configuration: await json("candidate/release-configuration.json"),
      dmg: await readFile(
        join(base, `candidate/Curfew-v${candidate.version}.dmg`),
      ),
      appcast: await readFile(join(base, "candidate/appcast.xml")),
    },
    website: {
      directory: join(base, "website"),
      stamp: await json("website-build/website-build.json"),
      deployment: await json("identity/environment-artifact.json"),
    },
    candidateRun: local ? undefined : await json("candidate-run.json"),
    websiteRun: await json("website-run.json"),
    currentMainCommit:
      process.env.GITHUB_SHA ??
      (local
        ? execFileSync("git", ["rev-parse", "HEAD"], {
            encoding: "utf8",
          }).trim()
        : undefined),
    ...(local
      ? {
          local: {
            publicationCommit: authority.publicationCommit,
            nativeRepository: resolve(authority.nativeRepository),
            repository: fileURLToPath(new URL("../", import.meta.url)),
            evidenceDirectory: join(base, "local-evidence"),
            candidateDirectory: join(base, "candidate"),
          },
        }
      : {}),
    receipt: await json("owner-receipt.json"),
    destination: join(base, "site-ready"),
  };
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const [command, basePath] = process.argv.slice(2);
  const base = resolve(basePath);
  const input = await load(base);
  const config = {
    ...resolveEnvironment(
      input.website.deployment.manifest.environments.production,
      "production",
    ),
    sha256: input.website.deployment.sha256,
    sourceCommit: input.website.deployment.sourceCommit,
  };
  if (command === "prepare") {
    const prepared = await preparePublication(input);
    await writeFile(
      join(base, "prepared.json"),
      JSON.stringify(prepared, null, 2) + "\n",
      { flag: "wx" },
    );
    console.log(
      "Retained candidate and website are ready for owner-approved activation",
    );
  } else if (command === "ready") {
    await admit(input);
    await checkPublicationReadiness(config);
    console.log("Website TLS and maintenance services are ready");
  } else if (command === "verify") {
    const candidate = await admit(input);
    await verifyLivePublication(config, candidate);
    console.log(
      "Live site, exact update feed, public redirect, and callback retirement verified",
    );
  } else if (command === "publish") {
    const candidate = await admit(input);
    const prepared = JSON.parse(
      await readFile(join(base, "prepared.json"), "utf8"),
    );
    assert.deepEqual(prepared.candidate, candidate);
    if (candidate.provenance?.kind === "local")
      assert.equal(
        prepared.publicationCommit,
        input.local.publicationCommit,
        "Prepared publication source changed",
      );
    assert.deepEqual(
      prepared.siteStamp,
      await sealWebsite(input.destination, input.website.deployment),
    );
    const directory = join(base, "candidate");
    const expected = {};
    for (const name of [
      `Curfew-v${candidate.version}.dmg`,
      "appcast.xml",
      "candidate.json",
    ])
      expected[name] = createHash("sha256")
        .update(await readFile(join(directory, name)))
        .digest("hex");
    const origin =
      input.website.deployment.manifest.environments.production.siteOrigin;
    await writeFile(
      join(directory, "public-release-notes.md"),
      `Curfew now connects through ${new URL(origin).hostname}. Sign in again and reconnect your Mac and assistants. Local settings, history, licenses, and encryption keys are preserved.\n`,
    );
    const invoke = (args) => {
      try {
        const output = execFileSync("gh", args, {
          encoding: "utf8",
          stdio: ["ignore", "pipe", "pipe"],
        });
        return args[0] === "api" ? JSON.parse(output) : output;
      } catch (error) {
        if (
          args[0] === "api" &&
          args[1].includes("/releases/tags/") &&
          /HTTP 404/.test(String(error.stderr))
        )
          return null;
        throw error;
      }
    };
    console.log(
      `Release ${publishGithubRelease(invoke, candidate, expected, directory, input.local?.publicationCommit)}`,
    );
  } else
    throw new Error(
      "Use prepare, ready, publish, or verify with the retained publication directory",
    );
}
