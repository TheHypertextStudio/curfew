import assert from "node:assert/strict";
import test from "node:test";
import { generateKeyPairSync, sign } from "node:crypto";
import {
  mkdtemp,
  mkdir,
  writeFile,
  readFile,
  access,
  rm,
  stat,
} from "node:fs/promises";
import { execFileSync, spawnSync } from "node:child_process";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createArtifact } from "./deployment-config.mjs";
import { createReleaseConfiguration } from "./release-configuration.mjs";
import { createCandidate, activationGates } from "./release-candidate.mjs";
import { sealWebsite } from "./website-artifact.mjs";

async function fixture(t) {
  const directory = await mkdtemp(join(tmpdir(), "curfew-publication-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  const site = join(directory, "website");
  await mkdir(site, { recursive: true });
  await writeFile(join(site, "index.html"), "verified site");
  for (const [page, mode] of [
    ["success", "checkout"],
    ["restore", "restore"],
  ]) {
    await writeFile(
      join(site, `${page}.html`),
      `<div data-purchase-mode="${mode}" data-issuer="https://license.alternate.example" data-scheme="curfew"></div>`,
    );
  }
  const deployment = createArtifact(
    {
      version: 1,
      environments: {
        production: {
          siteOrigin: "https://alternate.example",
          accountOrigin: "https://account.alternate.example",
          syncOrigin: "https://sync.alternate.example",
          licenseOrigin: "https://license.alternate.example",
          passkeyRPID: "alternate.example",
          recoveryEmailFrom: "accounts@alternate.example",
        },
      },
    },
    "a".repeat(40),
  );
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const sparkleKey = publicKey
    .export({ type: "spki", format: "der" })
    .subarray(-32)
    .toString("base64");
  const configuration = createReleaseConfiguration({
    sourceCommit: "a".repeat(40),
    deployment,
    appcast: "https://alternate.example/appcast.xml",
    sparkleKey,
    inputs: { "Curfew/Info.plist": "b".repeat(64) },
  });
  const dmg = Buffer.from("signed candidate fixture");
  const appcast = Buffer.from(
    `<rss><channel><link>https://alternate.example/appcast.xml</link><item><sparkle:version>0.0.2</sparkle:version><enclosure url="https://github.com/TheHypertextStudio/curfew/releases/download/v0.0.2/Curfew-v0.0.2.dmg" length="${dmg.length}" sparkle:edSignature="${sign(null, dmg, privateKey).toString("base64")}"/></item></channel></rss>`,
  );
  const candidate = createCandidate({
    dmg,
    appcast,
    configuration,
    version: "0.0.2",
    team: "T95VDD3A4W",
    sparkleKey,
    runID: "123",
  });
  const run = {
    status: "completed",
    conclusion: "success",
    event: "push",
    repository: { full_name: "TheHypertextStudio/curfew" },
    head_sha: "a".repeat(40),
  };
  const now = Date.now();
  return {
    native: { candidate, dmg, appcast, configuration },
    website: {
      directory: site,
      deployment,
      stamp: await sealWebsite(site, deployment),
    },
    candidateRun: {
      ...run,
      id: 123,
      path: ".github/workflows/release.yml",
      head_branch: "v0.0.2",
    },
    websiteRun: {
      ...run,
      id: 456,
      path: ".github/workflows/website.yml",
      head_branch: "main",
    },
    currentMainCommit: "a".repeat(40),
    now,
    destination: join(directory, "ready"),
    receipt: {
      operator: "owner",
      observedAt: new Date(now).toISOString(),
      candidate,
      gates: Object.fromEntries(
        activationGates.map((gate) => [
          gate,
          { outcome: "pass", evidence: "test-only fixture" },
        ]),
      ),
    },
  };
}
async function api() {
  const value = await import("./publication.mjs").catch(() => null);
  assert.equal(
    typeof value?.preparePublication,
    "function",
    "Publication requires verified retained inputs",
  );
  return value;
}
async function localFixture(t) {
  const input = await fixture(t);
  const provenance = {
    kind: "local",
    executionID: "fe840ac6-2162-47dc-83c1-b8e55e46a4e3",
    qualitySHA256: "c".repeat(64),
    signingSHA256: "d".repeat(64),
  };
  input.native.candidate = createCandidate({
    ...input.native.candidate,
    ...input.native,
    runID: undefined,
    provenance,
  });
  input.receipt.candidate = structuredClone(input.native.candidate);
  input.receipt.gates.stagingAcceptance = {
    outcome: "pass",
    evidence: "test-only staging acceptance fixture",
  };
  delete input.candidateRun;
  input.currentMainCommit = "f".repeat(40);
  input.local = {
    publicationCommit: input.currentMainCommit,
    repository: "/fixture-repository",
    nativeRepository: "/fixture-frozen-native-source",
    evidenceDirectory: "/missing-fixture-evidence",
    candidateDirectory: "/fixture-candidate",
  };
  return input;
}
test("local publication uses its explicit verifier without borrowing a hosted run", async (t) => {
  const input = await localFixture(t);
  let verified = false;
  const result = await (
    await api()
  ).preparePublication(input, async (actual) => {
    assert.equal(actual, input);
    verified = true;
  });
  assert.equal(verified, true);
  assert.equal(result.publicationCommit, input.local.publicationCommit);
  assert.deepEqual(
    await readFile(join(input.destination, "appcast.xml")),
    input.native.appcast,
  );
});
test("local publication retains staging, source, receipt and evidence gates before writing", async (t) => {
  const { preparePublication } = await api();
  for (const mutate of [
    (x) => {
      delete x.receipt.gates.stagingAcceptance;
    },
    (x) => {
      x.receipt.gates.stagingAcceptance.outcome = "pending";
    },
    (x) => {
      x.receipt.gates.stagingAcceptance.evidence = "";
    },
    (x) => {
      x.candidateRun = { id: 123, conclusion: "success" };
    },
    (x) => {
      x.local.publicationCommit = "b".repeat(40);
    },
  ]) {
    const input = await localFixture(t);
    mutate(input);
    await assert.rejects(() => preparePublication(input, async () => {}));
    await assert.rejects(() => access(input.destination));
  }
  const missing = await localFixture(t);
  await assert.rejects(() => preparePublication(missing));
  await assert.rejects(() => access(missing.destination));
});
test("local release keeps the candidate tag pinned while checking the reviewed publication head", async (t) => {
  const input = await localFixture(t);
  const { publishGithubRelease } = await api();
  const expected = {
    "Curfew-v0.0.2.dmg": "a".repeat(64),
    "appcast.xml": "b".repeat(64),
    "candidate.json": "c".repeat(64),
  };
  const invoke = (args) => {
    assert.equal(args[0], "api", "matching public bytes must not be rewritten");
    if (args[1].includes("heads/main"))
      return { object: { type: "commit", sha: input.currentMainCommit } };
    if (args[1].includes("git/ref/tags"))
      return {
        object: { type: "commit", sha: input.native.candidate.sourceCommit },
      };
    return {
      draft: false,
      tag_name: "v0.0.2",
      assets: Object.entries(expected).map(([name, digest]) => ({
        name,
        digest: `sha256:${digest}`,
      })),
    };
  };
  assert.equal(
    publishGithubRelease(
      invoke,
      input.native.candidate,
      expected,
      "/fixture",
      input.local.publicationCommit,
    ),
    "reused",
  );
  assert.throws(
    () =>
      publishGithubRelease(
        invoke,
        input.native.candidate,
        expected,
        "/fixture",
        "e".repeat(40),
      ),
    /Main changed/,
  );
  const hosted = await fixture(t);
  assert.throws(
    () =>
      publishGithubRelease(
        invoke,
        hosted.native.candidate,
        expected,
        "/fixture",
        input.local.publicationCommit,
      ),
    /hosted|source/i,
  );
});
test("publication stages the exact signed feed beside the verified site without changing retained bytes", async (t) => {
  const input = await fixture(t);
  const { preparePublication } = await api();
  const result = await preparePublication(input);
  assert.equal(result.candidate.version, "0.0.2");
  assert.deepEqual(
    await readFile(join(input.destination, "appcast.xml")),
    input.native.appcast,
  );
  assert.equal(
    await readFile(join(input.destination, "index.html"), "utf8"),
    "verified site",
  );
  await assert.rejects(() =>
    access(join(input.website.directory, "appcast.xml")),
  );
});
test("publication refuses unaccepted, stale, mismatched, or failed inputs before writing output", async (t) => {
  const { preparePublication } = await api();
  for (const mutate of [
    (input) => {
      delete input.receipt.gates.signedDevice;
    },
    (input) => {
      input.receipt.observedAt = new Date(input.now - 3_600_001).toISOString();
    },
    (input) => {
      input.receipt.observedAt = new Date(input.now + 1).toISOString();
    },
    (input) => {
      input.candidateRun.head_sha = "c".repeat(40);
    },
    (input) => {
      input.websiteRun.conclusion = "failure";
    },
    (input) => {
      input.websiteRun.repository.full_name = "other/repository";
    },
    (input) => {
      input.currentMainCommit = "c".repeat(40);
    },
    (input) => {
      input.website.stamp = {
        ...input.website.stamp,
        contentSHA256: "c".repeat(64),
      };
    },
  ]) {
    const input = await fixture(t);
    mutate(input);
    await assert.rejects(() => preparePublication(input));
    await assert.rejects(() => access(input.destination));
  }
});
test("release retries reuse matching published assets and refuse changed public bytes", async (t) => {
  const input = await fixture(t);
  const { publishGithubRelease } = await api();
  const expected = {
    "Curfew-v0.0.2.dmg": "a".repeat(64),
    "appcast.xml": "b".repeat(64),
    "candidate.json": "c".repeat(64),
  };
  const assets = Object.entries(expected).map(([name, digest]) => ({
    name,
    digest: `sha256:${digest}`,
  }));
  const invoke = (args) => {
    if (args[0] !== "api")
      throw new Error("A matching public release cannot be mutated");
    if (
      args[1].includes("git/ref/heads/main") ||
      args[1].includes("git/ref/tags/")
    )
      return { object: { type: "commit", sha: "a".repeat(40) } };
    return { draft: false, tag_name: "v0.0.2", assets };
  };
  assert.equal(
    publishGithubRelease(
      invoke,
      input.native.candidate,
      expected,
      "/candidate",
    ),
    "reused",
  );
  assets[0].digest = `sha256:${"d".repeat(64)}`;
  assert.throws(
    () =>
      publishGithubRelease(
        invoke,
        input.native.candidate,
        expected,
        "/candidate",
      ),
    /asset/i,
  );
});

test("release publication refuses changed main or tag before any write", async (t) => {
  const input = await fixture(t);
  const { publishGithubRelease } = await api();
  const expected = {
    "Curfew-v0.0.2.dmg": "a".repeat(64),
    "appcast.xml": "b".repeat(64),
    "candidate.json": "c".repeat(64),
  };
  for (const changed of ["heads/main", "tags/v0.0.2"]) {
    const invoke = (args) => {
      assert.equal(args[0], "api");
      assert.ok(args[1].includes("/git/ref/"));
      return {
        object: {
          type: "commit",
          sha: args[1].endsWith(changed) ? "d".repeat(40) : "a".repeat(40),
        },
      };
    };
    assert.throws(
      () =>
        publishGithubRelease(
          invoke,
          input.native.candidate,
          expected,
          "/candidate",
        ),
      /changed before publication/,
    );
  }
});

test("draft release activation verifies uploaded retained bytes before making them public", async (t) => {
  const input = await fixture(t);
  const { publishGithubRelease } = await api();
  const directory = join(input.destination, "../candidate");
  await mkdir(directory);
  const files = {
    "Curfew-v0.0.2.dmg": input.native.dmg,
    "appcast.xml": input.native.appcast,
    "candidate.json": Buffer.from(JSON.stringify(input.native.candidate)),
  };
  const expected = {};
  for (const [name, bytes] of Object.entries(files)) {
    await writeFile(join(directory, name), bytes);
    expected[name] = createHash("sha256").update(bytes).digest("hex");
  }
  let release = null;
  const invoke = (args) => {
    if (args[0] === "api" && args[1].includes("/git/ref/"))
      return { object: { type: "commit", sha: "a".repeat(40) } };
    if (args[0] === "api") {
      if (args[1].includes("/releases/tags/")) return null;
      if (args[1].endsWith("/releases"))
        return [release ? [structuredClone(release)] : []];
      assert.ok(args[1].endsWith("/releases/17"));
      return structuredClone(release);
    }
    if (args[1] === "create") {
      assert.ok(args.includes("--draft"));
      release = { id: 17, draft: true, tag_name: "v0.0.2", assets: [] };
    } else if (args[1] === "upload") {
      assert.equal(release.draft, true);
      assert.ok(!args.includes("--clobber"));
      const name = args[3].split("/").at(-1);
      release.assets.push({
        name,
        digest: `sha256:${createHash("sha256").update(readFileSync(args[3])).digest("hex")}`,
      });
    } else if (args[1] === "edit") {
      assert.equal(release.assets.length, 3);
      for (const asset of release.assets)
        assert.equal(asset.digest, `sha256:${expected[asset.name]}`);
      release.draft = false;
    } else throw new Error("Unexpected provider operation");
  };
  assert.equal(
    publishGithubRelease(invoke, input.native.candidate, expected, directory),
    "published",
  );
  assert.equal(release.draft, false);
});

test("publication readiness requires live website TLS and the reviewed backend in maintenance", async (t) => {
  const input = await fixture(t);
  const { checkPublicationReadiness } = await api();
  assert.equal(typeof checkPublicationReadiness, "function");
  const config = {
    ...input.website.deployment.manifest.environments.production,
    legacySiteOrigin: "https://old.example",
    sha256: input.native.candidate.configurationSHA256,
    sourceCommit: "a".repeat(40),
  };
  const fetcher = async (url) =>
    new Response("healthy", {
      headers: {
        "x-curfew-configuration": config.sha256,
        "x-curfew-configuration-commit": config.sourceCommit,
        "x-curfew-maintenance": url.includes("license.") ? "false" : "true",
      },
    });
  await checkPublicationReadiness(config, fetcher);
  await assert.rejects(() =>
    checkPublicationReadiness(
      config,
      async () => new Response("unavailable", { status: 503 }),
    ),
  );
  await assert.rejects(() =>
    checkPublicationReadiness(
      config,
      async () =>
        new Response("healthy", {
          headers: {
            "x-curfew-configuration": config.sha256,
            "x-curfew-maintenance": "false",
          },
        }),
    ),
  );
});
test("live publication verification checks actual feed bytes, public redirects, and callback retirement", async (t) => {
  const input = await fixture(t);
  const { verifyLivePublication } = await api();
  assert.equal(typeof verifyLivePublication, "function");
  const config = {
    siteOrigin: "https://alternate.example",
    legacySiteOrigin: "https://old.example",
  };
  const fetcher = async (url) => {
    if (url === "https://alternate.example/appcast.xml")
      return new Response(input.native.appcast);
    if (url.startsWith("https://old.example/api/"))
      return new Response("retired", { status: 410 });
    if (url.startsWith("https://old.example/"))
      return new Response(null, {
        status: 308,
        headers: {
          location:
            "https://alternate.example/download?curfew_migration_check=1",
        },
      });
    return new Response("site");
  };
  await verifyLivePublication(config, input.native.candidate, fetcher);
  await assert.rejects(() =>
    verifyLivePublication(
      config,
      input.native.candidate,
      async () => new Response("different feed"),
    ),
  );
});

test("manual activation writes only the independently approved private acceptance receipt", async (t) => {
  const path = ".github/workflows/activate-production.yml";
  await assert.doesNotReject(
    () => access(path),
    "Activation requires a separate manual workflow",
  );
  const workflow = JSON.parse(
    execFileSync(
      "ruby",
      [
        "-rjson",
        "-ryaml",
        "-e",
        "puts JSON.generate(YAML.load_file(ARGV[0]))",
        path,
      ],
      { encoding: "utf8" },
    ),
  );
  assert.deepEqual(Object.keys(workflow.on ?? workflow.true), [
    "workflow_dispatch",
  ]);
  assert.equal(workflow.jobs.activate.environment, "production");
  assert.equal(workflow.jobs.activate.if, "github.ref == 'refs/heads/main'");
  const step = workflow.jobs.activate.steps.find(
    (value) => value.name === "Load the approved private receipt",
  );
  assert.ok(step);
  for (const valid of [false, true]) {
    const input = await fixture(t);
    const receipt = JSON.stringify(input.receipt);
    const result = spawnSync("bash", ["-e", "-c", step.run], {
      cwd: join(input.destination, ".."),
      encoding: "utf8",
      env: {
        PATH: process.env.PATH,
        OWNER_RECEIPT: receipt,
        RECEIPT_SHA256: valid
          ? createHash("sha256").update(receipt).digest("hex")
          : "f".repeat(64),
      },
    });
    assert.equal(result.status, valid ? 0 : 1, result.stderr);
    const output = join(
      input.destination,
      "../.publication/owner-receipt.json",
    );
    if (valid) assert.equal((await stat(output)).mode & 0o777, 0o600);
    else await assert.rejects(() => access(output));
  }
});

test("activation can read source records on a clean runner before loading its receipt", async (t) => {
  const input = await fixture(t);
  const root = join(input.destination, "..");
  const workflow = JSON.parse(
    execFileSync(
      "ruby",
      [
        "-rjson",
        "-ryaml",
        "-e",
        "puts JSON.generate(YAML.load_file(ARGV[0]))",
        ".github/workflows/activate-production.yml",
      ],
      { encoding: "utf8" },
    ),
  );
  const script = workflow.jobs.activate.steps.find(
    (step) => step.name === "Read source workflow records",
  ).run;
  const testScript = `gh() { printf '{}\\n'; }\n${script}`;
  const result = spawnSync("bash", ["-e", "-c", testScript], {
    cwd: root,
    encoding: "utf8",
    env: {
      PATH: "/usr/bin:/bin",
      GH_CONFIG_DIR: join(root, ".isolated-gh-config"),
      GITHUB_REPOSITORY: "TheHypertextStudio/curfew",
      CANDIDATE_RUN_ID: "123",
      WEBSITE_RUN_ID: "456",
    },
  });
  assert.equal(result.status, 0, result.stderr);
  for (const name of ["candidate-run.json", "website-run.json"])
    assert.deepEqual(
      JSON.parse(await readFile(join(root, ".publication", name), "utf8")),
      {},
    );
});

test("native publication builds and deploys the retained static directory with its signed feed", async (t) => {
  const input = await fixture(t);
  const root = join(input.destination, "..");
  const workflow = JSON.parse(
    execFileSync(
      "ruby",
      [
        "-rjson",
        "-ryaml",
        "-e",
        "puts JSON.generate(YAML.load_file(ARGV[0]))",
        ".github/workflows/activate-production.yml",
      ],
      { encoding: "utf8" },
    ),
  );
  const script = workflow.jobs.activate.steps.find(
    (step) =>
      step.name === "Publish the same Worker assets and signed update feed",
  ).run;
  const testCommands = `gh() { printf '%s\\n' "$GITHUB_SHA"; }
pnpm() {
  "$CURFEW_TEST_NODE" -e 'const {appendFileSync}=require("node:fs");appendFileSync(process.env.GITHUB_WORKSPACE+"/uploaded-arguments.jsonl",JSON.stringify({args:process.argv.slice(1),assets:process.env.CURFEW_WEBSITE_ASSETS_DIRECTORY})+"\\n")' -- "$@"
}
`;
  const testScript = `${testCommands}\n${script}`;
  const result = spawnSync("bash", ["-e", "-c", testScript], {
    cwd: root,
    encoding: "utf8",
    env: {
      PATH: "/usr/bin:/bin",
      GH_CONFIG_DIR: join(root, ".isolated-gh-config"),
      CURFEW_TEST_NODE: process.execPath,
      GITHUB_WORKSPACE: root,
      GITHUB_SHA: "a".repeat(40),
      GITHUB_REPOSITORY: "TheHypertextStudio/curfew",
    },
  });
  assert.equal(result.status, 0, result.stderr);
  const calls = (await readFile(join(root, "uploaded-arguments.jsonl"), "utf8"))
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line));
  assert.deepEqual(
    calls,
    [
      ["build", "--mode", "production"],
      [
        "deploy",
        "--prebuilt",
        "--mode",
        "production",
        "--dry-run",
        "--provision=false",
      ],
      ["deploy", "--prebuilt", "--mode", "production", "--provision=false"],
    ].map((args) => ({
      args: ["--dir", "landing/hosting", "exec", "cf", ...args],
      assets: join(root, ".publication/site-ready"),
    })),
  );
  assert.doesNotMatch(script, /astro build|pages deploy/);
});
