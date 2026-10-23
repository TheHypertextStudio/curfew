import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { readFile, mkdir, writeFile, appendFile, lstat, rm, readdir, readlink } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { userInfo } from "node:os";
import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { appendFileSync, openSync, closeSync } from "node:fs";
import { verifyCandidate } from "./release-candidate.mjs";

const repository = "TheHypertextStudio/curfew";
export const upgradeBaseline = Object.freeze({
  version: "0.0.8", runID: "39845052365", artifactID: "12454629589",
  sourceCommit: "be209d487d554cc4a2bbe5dd89211e258280bf3b",
  dmgSHA256: "30e6a9d98d30d394b99d92e7dc169da2c5dd52f2ac4fd3e2711077ab395fed1e",
});
const bundleID = "studio.hypertext.apps.curfew";
const digest = bytes => createHash("sha256").update(bytes).digest("hex");
export function requireFreshWalkthrough(source) {
  assert.match(source, /func testFreshSignedInstallerOpensRealSetup\(\) throws/,
    "Producer has no signed fresh-installer walkthrough; select a supported candidate");
}
export function verifierSourceOutput(candidate) {
  assert.match(candidate.sourceCommit, /^[a-f0-9]{40}$/);
  return `source_commit=${candidate.sourceCommit}\n`;
}
export function validateUpgradeVersion(version) {
  assert.equal(typeof version, "string", "An explicit candidate version is required");
  assert.match(version, /^0\.0\.(0|[1-9]\d*)$/);
  const patch = Number(version.slice(4));
  assert.ok(Number.isSafeInteger(patch) && patch > 8, "Candidate must be newer than the pinned baseline");
  return version;
}
export function upgradeRequest(environment) {
  const expected = { version: environment.CURFEW_UPGRADE_VERSION, runID: environment.CURFEW_UPGRADE_RUN_ID,
    sourceCommit: environment.CURFEW_UPGRADE_SOURCE_COMMIT, dmgSHA256: environment.CURFEW_UPGRADE_DMG_SHA256 };
  validateUpgradeVersion(expected.version);
  assert.match(expected.runID, /^[1-9]\d*$/);
  assert.match(expected.sourceCommit, /^[a-f0-9]{40}$/);
  assert.match(expected.dmgSHA256, /^[a-f0-9]{64}$/);
  return expected;
}
export function validateUpgradePair(baseline, candidate) {
  for (const key of ["version", "sourceCommit", "dmgSHA256"])
    assert.equal(baseline[key], upgradeBaseline[key], `Unapproved baseline ${key}`);
  validateUpgradeVersion(candidate.version);
  assert.equal(candidate.sparkleKey, baseline.sparkleKey, "The existing Sparkle key must be retained");
}
export function createUpgradeHandler({ origin, assets, log }) {
  const base = validateLoopbackURL(origin);
  return (request, response) => {
    let url;
    try { url = new URL(request.url, base); }
    catch { response.writeHead(400); response.end(); return; }
    const asset = assets.get(url.pathname);
    const status = request.headers.host !== base.host ? 403
      : !["GET", "HEAD"].includes(request.method) ? 405
      : request.url !== url.pathname || !asset ? 404 : 200;
    const bytes = status === 200 && request.method === "GET" ? asset.bytes : Buffer.alloc(0);
    response.once("finish", () => log({ method: request.method, path: url.pathname, status, bytes: bytes.length }));
    response.writeHead(status, { "content-type": status === 200 ? asset.type : "text/plain",
      "cache-control": "no-store", "content-length": status === 200 ? asset.bytes.length : 0 });
    response.end(bytes);
  };
}

export function requireDisposableRunner({ githubActions, username, home, temporary }) {
  assert.equal(githubActions, "true", "Hosted disposable runner required");
  assert.equal(username, "runner", "Owner account cannot run upgrade acceptance");
  assert.equal(home, "/Users/runner", "Hosted disposable home required");
  assert.equal(resolve(temporary), "/Users/runner/work/_temp", "Hosted temporary directory required");
}
function guardUpgradeDirectory(directory) {
  const account = userInfo();
  requireDisposableRunner({ githubActions: process.env.GITHUB_ACTIONS,
    username: account.username, home: account.homedir, temporary: process.env.RUNNER_TEMP });
  assert.equal(resolve(directory), join(process.env.RUNNER_TEMP, "sparkle-upgrade"));
}
export function validateLoopbackURL(value) {
  const url = new URL(value);
  assert.equal(url.protocol, "http:");
  assert.equal(url.hostname, "localhost");
  assert.ok(url.port && Number(url.port) > 0);
  assert.equal(url.pathname, "/");
  assert.ok(!url.username && !url.password && !url.search && !url.hash);
  return url;
}
export function defaultsRemovalAllowed(current, owned) {
  if (current === undefined) return false;
  assert.equal(current, owned, "Refusing to remove an unowned feed override");
  return true;
}
export function createUpgradeAppcast(appcast, candidate, baseURL) {
  const base = validateLoopbackURL(baseURL);
  validateUpgradeVersion(candidate.version);
  const replaceOne = (pattern, replacement) => {
    assert.equal([...appcast.matchAll(pattern)].length, 1, "Ambiguous staging feed");
    appcast = appcast.replace(pattern, replacement);
  };
  replaceOne(/(<enclosure\s+[^>]*?url=")[^"]+("[^>]*>)/g,
    `$1${new URL(`Curfew-v${candidate.version}.dmg`, base)}$2`);
  replaceOne(/<sparkle:releaseNotesLink>[^<]+<\/sparkle:releaseNotesLink>/g,
    `<sparkle:releaseNotesLink>${new URL("release-notes.html", base)}</sparkle:releaseNotesLink>`);
  // All links remain on this runner. The enclosure length/signature are untouched.
  appcast = appcast.replace(/<link>[^<]+<\/link>/g, `<link>${base}</link>`);
  return appcast;
}
export function selectCandidateRun(runs, expected) {
  assert.ok(expected, "Explicit candidate subject required");
  const matches = runs.filter(run => String(run.databaseId) === expected.runID);
  assert.equal(matches.length, 1, "The explicitly selected candidate run is missing");
  assert.equal(matches[0].headBranch, `v${expected.version}`);
  assert.equal(matches[0].headSha, expected.sourceCommit);
  return { run: matches[0], version: expected.version };
}

export function verifyCandidateOrigin({ candidate, artifact, tagCommit, version, expected }) {
  assert.match(tagCommit, /^[a-f0-9]{40}$/);
  assert.equal(candidate.version, version);
  assert.equal(candidate.sourceCommit, tagCommit);
  assert.equal(artifact.name, "curfew-signed-candidate");
  assert.equal(artifact.expired, false);
  assert.equal(artifact.workflow_run.repository_id, 1165282307);
  assert.equal(String(artifact.workflow_run.id), candidate.runID);
  assert.equal(artifact.workflow_run.head_branch, `v${version}`);
  assert.equal(artifact.workflow_run.head_sha, tagCommit);
  if (expected) {
    for (const key of ["version", "runID", "sourceCommit", "dmgSHA256"])
      assert.equal(candidate[key], expected[key], `Unexpected upgrade ${key}`);
    if (expected.artifactID) assert.equal(String(artifact.id), expected.artifactID);
  }
  return candidate;
}
const gh = args => JSON.parse(execFileSync("gh", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }));
async function prepare(directory) {
  const input = await downloadExactCandidate(directory, upgradeRequest(process.env));
  // Export only after origin and cryptographic checks have accepted this subject.
  if (process.env.GITHUB_OUTPUT)
    await appendFile(process.env.GITHUB_OUTPUT, verifierSourceOutput(input.candidate));
}

async function verifyFreshSource(directory, source) {
  const { candidate } = await readCandidate(directory);
  assert.equal(execFileSync("git", ["-C", source, "rev-parse", "HEAD"], { encoding: "utf8" }).trim(), candidate.sourceCommit);
  execFileSync("git", ["-C", source, "diff", "--quiet", "HEAD", "--"]);
  let walkthrough = "";
  try { walkthrough = await readFile(join(source, "CurfewUITests/SignedInstallerAcceptanceTests.swift"), "utf8"); }
  catch (error) { if (error.code !== "ENOENT") throw error; }
  requireFreshWalkthrough(walkthrough);
}

async function readCandidate(directory) {
  const candidate = JSON.parse(await readFile(join(directory, "candidate.json"), "utf8"));
  const input = { candidate,
    dmg: await readFile(join(directory, `Curfew-v${candidate.version}.dmg`)),
    appcast: await readFile(join(directory, "appcast.xml")),
    configuration: JSON.parse(await readFile(join(directory, "release-configuration.json"), "utf8")) };
  verifyCandidate(input);
  return input;
}

async function downloadExactCandidate(directory, expected) {
  assert.match(expected.runID, /^[1-9]\d*$/);
  assert.match(expected.sourceCommit, /^[a-f0-9]{40}$/);
  assert.match(expected.dmgSHA256, /^[a-f0-9]{64}$/);
  const run = gh(["api", `repos/${repository}/actions/runs/${expected.runID}`]);
  assert.equal(run.path.split("@")[0], ".github/workflows/release.yml");
  assert.equal(run.event, "push");
  assert.equal(run.conclusion, "success");
  selectCandidateRun([{ databaseId: run.id, headBranch: run.head_branch, headSha: run.head_sha }], expected);
  let ref = gh(["api", `repos/${repository}/git/ref/tags/v${expected.version}`]).object;
  if (ref.type === "tag") ref = gh(["api", `repos/${repository}/git/tags/${ref.sha}`]).object;
  assert.equal(ref.type, "commit");
  assert.equal(ref.sha, expected.sourceCommit);
  const artifacts = gh(["api", `repos/${repository}/actions/runs/${expected.runID}/artifacts`]).artifacts
    .filter(value => value.name === "curfew-signed-candidate" && !value.expired);
  assert.equal(artifacts.length, 1);
  const artifact = gh(["api", `repos/${repository}/actions/artifacts/${artifacts[0].id}`]);
  if (expected.artifactID) assert.equal(String(artifact.id), expected.artifactID);
  await mkdir(directory);
  const zip = join(directory, "download.zip");
  const output = openSync(zip, "wx", 0o600);
  try {
    // gh's terminal-escape protection also applies to piped binary ZIP output.
    // Preserve approved artifact bytes directly to a private file, never a terminal.
    execFileSync("gh", ["api", "--allow-escape-sequences",
      `repos/${repository}/actions/artifacts/${artifact.id}/zip`],
    { stdio: ["ignore", output, "pipe"] });
  } finally { closeSync(output); }
  execFileSync("unzip", ["-q", zip, "-d", directory]);
  await rm(zip);
  const input = await readCandidate(directory);
  verifyCandidateOrigin({ candidate: input.candidate, artifact, tagCommit: ref.sha, version: expected.version, expected });
  const subject = { version: input.candidate.version, sourceCommit: input.candidate.sourceCommit,
    dmgSHA256: input.candidate.dmgSHA256, configurationSHA256: input.candidate.configurationSHA256,
    artifactID: artifact.id, runID: expected.runID };
  await writeFile(join(directory, "acceptance-subject.json"), JSON.stringify(subject, null, 2) + "\n");
  return input;
}

async function prepareUpgrade(directory) {
  guardUpgradeDirectory(directory);
  await assert.rejects(() => lstat("/Applications/Curfew.app"), { code: "ENOENT" });
  await mkdir(directory);
  const expected = upgradeRequest(process.env);
  assert.equal(execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim(), expected.sourceCommit,
    "Run acceptance from the exact candidate source, including its final artifact verifier");
  execFileSync("git", ["diff", "--quiet", "HEAD", "--"]);
  const baseline = await downloadExactCandidate(join(directory, "baseline"), upgradeBaseline);
  const candidate = await downloadExactCandidate(join(directory, "candidate"), expected);
  validateUpgradePair(baseline.candidate, candidate.candidate);
  await writeFile(join(directory, "upgrade-plan.json"), JSON.stringify({
    scope: "disposable-sparkle-upgrade", baseline: upgradeBaseline, candidate: expected,
    acceptanceClaimed: false,
  }, null, 2) + "\n");
}

async function verifyUpgradeInputs(directory) {
  guardUpgradeDirectory(directory);
  const plan = JSON.parse(await readFile(join(directory, "upgrade-plan.json"), "utf8"));
  assert.equal(plan.scope, "disposable-sparkle-upgrade");
  assert.deepEqual(plan.baseline, upgradeBaseline);
  assert.equal(execFileSync("git", ["rev-parse", "HEAD"], { encoding: "utf8" }).trim(), plan.candidate.sourceCommit);
  const baseline = await readCandidate(join(directory, "baseline"));
  const candidate = await readCandidate(join(directory, "candidate"));
  validateUpgradePair(baseline.candidate, candidate.candidate);
  for (const key of ["version", "runID", "sourceCommit", "dmgSHA256"])
    assert.equal(candidate.candidate[key], plan.candidate[key]);
  return { plan, candidate };
}

async function serveUpgrade(directory) {
  const { candidate } = await verifyUpgradeInputs(directory);
  const notes = await readFile(`landing/releases/${candidate.candidate.version}.html`);
  assert.ok(notes.includes(`<h1>Curfew ${candidate.candidate.version}</h1>`));
  let handler = (_request, response) => { response.writeHead(503); response.end(); };
  const server = createServer((request, response) => handler(request, response));
  await new Promise((resolve, reject) => {
    server.once("error", reject);
    server.listen(0, "127.0.0.1", resolve);
  });
  const origin = `http://localhost:${server.address().port}/`;
  const appcast = Buffer.from(createUpgradeAppcast(candidate.appcast.toString("utf8"), candidate.candidate, origin));
  handler = createUpgradeHandler({ origin, assets: new Map([
    ["/appcast.xml", { bytes: appcast, type: "application/xml" }],
    [`/Curfew-v${candidate.candidate.version}.dmg`, { bytes: candidate.dmg, type: "application/octet-stream" }],
    ["/release-notes.html", { bytes: notes, type: "text/html; charset=utf-8" }],
  ]), log: entry => appendFileSync(join(directory, "transfers.jsonl"), JSON.stringify(entry) + "\n", { mode: 0o600 }) });
  await writeFile(join(directory, "staging-appcast.xml"), appcast);
  await writeFile(join(directory, "server.json"), JSON.stringify({ feedURL: new URL("appcast.xml", origin).href,
    derivedFeedSHA256: digest(appcast), candidateDMGSHA256: digest(candidate.dmg) }, null, 2) + "\n");
  const stop = () => server.close();
  process.once("SIGINT", stop); process.once("SIGTERM", stop);
  await new Promise(resolve => server.once("close", resolve));
}

function currentFeedOverride() {
  const result = spawnSync("/usr/bin/defaults", ["read", bundleID, "SUFeedURL"], { encoding: "utf8" });
  if (result.status === 0) return result.stdout.trim();
  assert.match(result.stderr, /does not exist/, "Cannot inspect the disposable user's override");
  return undefined;
}

async function configureUpgrade(directory) {
  await verifyUpgradeInputs(directory);
  const state = JSON.parse(await readFile(join(directory, "server.json"), "utf8"));
  const feed = new URL(state.feedURL);
  validateLoopbackURL(feed.origin + "/");
  assert.equal(feed.pathname, "/appcast.xml");
  assert.equal(currentFeedOverride(), undefined, "A fresh user must have no existing feed override");
  execFileSync("/usr/bin/defaults", ["write", bundleID, "SUFeedURL", "-string", state.feedURL]);
  assert.equal(currentFeedOverride(), state.feedURL);
}

async function cleanupUpgrade(directory) {
  guardUpgradeDirectory(directory);
  let state;
  try { state = JSON.parse(await readFile(join(directory, "server.json"), "utf8")); }
  catch (error) { if (error.code === "ENOENT") return; throw error; }
  if (defaultsRemovalAllowed(currentFeedOverride(), state.feedURL))
    execFileSync("/usr/bin/defaults", ["delete", bundleID, "SUFeedURL"]);
  assert.equal(currentFeedOverride(), undefined);
  await writeFile(join(directory, "cleanup.json"), JSON.stringify({ ownedFeedOverrideRemoved: true }) + "\n");
}

async function appManifest(directory, prefix = "") {
  const manifest = {};
  for (const name of (await readdir(directory)).sort()) {
    const path = join(directory, name), relative = prefix + name, entry = await lstat(path);
    if (entry.isSymbolicLink()) manifest[relative] = { symlink: await readlink(path) };
    else if (entry.isDirectory()) Object.assign(manifest, await appManifest(path, relative + "/"));
    else { assert.ok(entry.isFile()); manifest[relative] = { sha256: digest(await readFile(path)) }; }
  }
  return manifest;
}

async function verifyInstalledUpgrade(directory, reference) {
  const { candidate } = await verifyUpgradeInputs(directory);
  assert.equal(resolve(reference), join(directory, "candidate-mount/Curfew.app"));
  const installed = "/Applications/Curfew.app";
  execFileSync("bash", ["scripts/verify-release-artifact.sh", installed,
    join(directory, "candidate/release-configuration.json"), candidate.candidate.version], { stdio: "inherit" });
  const manifest = await appManifest(installed);
  assert.deepEqual(manifest, await appManifest(reference), "Installed app differs from exact candidate");
  const ui = JSON.parse(await readFile(join(directory, "upgrade-ui.json"), "utf8"));
  assert.equal(ui.baselineVersion, upgradeBaseline.version);
  assert.equal(ui.version, candidate.candidate.version);
  assert.equal(ui.sparkleInstallAndRelaunch, true);
  assert.ok(Number.isInteger(ui.baselinePID) && Number.isInteger(ui.relaunchedPID));
  assert.notEqual(ui.baselinePID, ui.relaunchedPID);
  const transfers = (await readFile(join(directory, "transfers.jsonl"), "utf8")).trim().split("\n").map(JSON.parse);
  assert.ok(transfers.some(entry => entry.method === "GET" && entry.status === 200
    && entry.path === `/Curfew-v${candidate.candidate.version}.dmg` && entry.bytes === candidate.dmg.length),
  "No completed exact-DMG response was recorded");
  await writeFile(join(directory, "installed-verification.json"), JSON.stringify({
    sourceCommit: candidate.candidate.sourceCommit, dmgSHA256: candidate.candidate.dmgSHA256,
    installedFilesMatchCandidate: true, manifestSHA256: digest(JSON.stringify(manifest)),
  }, null, 2) + "\n");
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const command = process.argv[2];
  assert.ok(["prepare", "verify-fresh-source", "prepare-upgrade", "serve-upgrade", "configure-upgrade", "cleanup-upgrade", "verify-upgrade"].includes(command));
  assert.ok(process.argv[3], "A new candidate directory is required");
  const directory = resolve(process.argv[3]);
  if (command === "prepare") await prepare(directory);
  if (command === "verify-fresh-source") await verifyFreshSource(directory, process.argv[4]);
  if (command === "prepare-upgrade") await prepareUpgrade(directory);
  if (command === "serve-upgrade") await serveUpgrade(directory);
  if (command === "configure-upgrade") await configureUpgrade(directory);
  if (command === "cleanup-upgrade") await cleanupUpgrade(directory);
  if (command === "verify-upgrade") await verifyInstalledUpgrade(directory, process.argv[4]);
}
