import assert from "node:assert/strict";
import test from "node:test";
import { createServer, request } from "node:http";
import { readFileSync, mkdtempSync, mkdirSync, writeFileSync, rmSync, realpathSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { execFileSync, spawnSync } from "node:child_process";
import { verifyCandidateOrigin, selectCandidateRun } from "./signed-installer-acceptance.mjs";
import {
  requireDisposableRunner, validateLoopbackURL, defaultsRemovalAllowed,
  createUpgradeAppcast,
  validateUpgradePair, upgradeBaseline, createUpgradeHandler,
  verifierSourceOutput, upgradeRequest, requireFreshWalkthrough,
} from "./signed-installer-acceptance.mjs";

function fixture() {
  return { candidate: { version: "0.0.8", runID: "123", sourceCommit: "a".repeat(40) },
    artifact: { name: "curfew-signed-candidate", expired: false,
      workflow_run: { id: 123, head_branch: "v0.0.8", head_sha: "a".repeat(40), repository_id: 1165282307 } },
    tagCommit: "a".repeat(40), version: "0.0.8" };
}
test("verifier checkout output contains only the validated immutable source SHA", () => {
  assert.equal(verifierSourceOutput({ sourceCommit: "a".repeat(40) }), `source_commit=${"a".repeat(40)}\n`);
  for (const sourceCommit of ["main", "a".repeat(40) + "\nother=main", "a".repeat(39), undefined])
    assert.throws(() => verifierSourceOutput({ sourceCommit }));
  const preparation = readFileSync("scripts/signed-installer-acceptance.mjs", "utf8")
    .split("async function prepare(directory) {")[1].split("async function readCandidate")[0];
  const output = preparation.indexOf("appendFile(process.env.GITHUB_OUTPUT");
  assert.ok(output > preparation.indexOf("await downloadExactCandidate("));
  assert.ok(output > preparation.indexOf("upgradeRequest(process.env)"),
    "Checkout authority must not be exported before cryptographic verification");
});

test("fresh install runs the selected producer verifier and keeps newer architecture enforcement", () => {
  const workflow = JSON.parse(execFileSync("ruby", ["-rjson", "-ryaml", "-e",
    "puts JSON.generate(YAML.load_file(ARGV[0]))", ".github/workflows/signed-installer-acceptance.yml"], { encoding: "utf8" }));
  const steps = workflow.jobs["installed-candidate"].steps;
  const install = steps.find(step => step.name === "Verify and install retained bytes on the fresh Mac");
  const command = install.run.split("\n").find(line => line.includes("bash scripts/verify-release-artifact.sh"));
  const root = mkdtempSync(join(tmpdir(), "curfew-producer-verifier-"));
  const strict = '#!/bin/bash\n[[ "$(cat "$1/architectures")" == "arm64 x86_64" ]] || exit 19\nprintf strict > "$VERIFIER_TRACE"\n';
  try {
    for (const dir of ["scripts", "installer-source/scripts", "volume/Curfew.app", "signed-candidate"])
      mkdirSync(join(root, dir), { recursive: true });
    writeFileSync(join(root, "scripts/verify-release-artifact.sh"), strict);
    for (const [version, architectures, producer, expectedStatus] of [
      ["0.0.8", "arm64", '#!/bin/bash\nprintf historical > "$VERIFIER_TRACE"\n', 0],
      ["0.0.11", "arm64", strict, 19],
      ["0.0.11", "arm64 x86_64", strict, 0],
    ]) {
      writeFileSync(join(root, "installer-source/scripts/verify-release-artifact.sh"), producer);
      writeFileSync(join(root, "volume/Curfew.app/architectures"), architectures);
      const result = spawnSync("/bin/bash", ["-c", command], { cwd: root, encoding: "utf8",
        env: { ...process.env, volume: join(root, "volume"), RUNNER_TEMP: root, version,
          VERIFIER_TRACE: join(root, "trace") } });
      assert.equal(result.status, expectedStatus, `Wrong verifier selected for ${version}: ${result.stderr}`);
      if (expectedStatus === 0)
        assert.equal(readFileSync(join(root, "trace"), "utf8"), version === "0.0.8" ? "historical" : "strict");
    }
    const checkout = steps.find(step => step.with?.path === "installer-source");
    assert.equal(checkout.with.ref, "${{ steps.subject.outputs.source_commit }}");
    assert.equal(steps.find(step => step.id === "subject").name, "Retain the exact signed release subject");
  } finally { rmSync(root, { recursive: true, force: true }); }
});
test("signed install accepts only the retained artifact from its actual release tag", () => {
  assert.equal(verifyCandidateOrigin(fixture()).version, "0.0.8");
});
for (const [name, change] of [
  ["different source", f => f.candidate.sourceCommit = "b".repeat(40)],
  ["different run", f => f.artifact.workflow_run.id = 456],
  ["different repository", f => f.artifact.workflow_run.repository_id = 1],
  ["expired bytes", f => f.artifact.expired = true],
  ["different tag", f => f.artifact.workflow_run.head_branch = "main"],
  ["different artifact", f => f.artifact.name = "unsigned-build"],
  ["different version", f => f.candidate.version = "0.0.9"],
]) test(`signed install rejects ${name}`, () => {
  const value = fixture(); change(value);
  assert.throws(() => verifyCandidateOrigin(value));
});
test("release selection requires an explicit subject and never chooses the latest tag", () => {
  assert.throws(() => selectCandidateRun([
    { databaseId: 20, headBranch: "v0.0.8", headSha: "b".repeat(40) },
    { databaseId: 30, headBranch: "v0.0.12", headSha: "c".repeat(40) },
  ]), /Explicit candidate subject required/);
});

test("explicit upgrade selection never substitutes a newer successful candidate", () => {
  const runs = [
    { databaseId: 11, headBranch: "v0.0.11", headSha: "a".repeat(40) },
    { databaseId: 12, headBranch: "v0.0.12", headSha: "b".repeat(40) },
  ];
  const expected = { runID: "11", version: "0.0.11", sourceCommit: "a".repeat(40) };
  assert.equal(selectCandidateRun(runs, expected).run.databaseId, 11);
  for (const change of [
    { runID: "99" }, { version: "0.0.10" }, { sourceCommit: "c".repeat(40) },
  ]) assert.throws(() => selectCandidateRun(runs, { ...expected, ...change }));
});

test("upgrade origin binds the explicitly approved digest and numeric artifact", () => {
  const f = fixture();
  f.candidate.dmgSHA256 = "d".repeat(64);
  f.artifact.id = 42;
  const expected = { version: "0.0.8", runID: "123", sourceCommit: "a".repeat(40),
    dmgSHA256: "d".repeat(64), artifactID: "42" };
  verifyCandidateOrigin({ ...f, expected });
  for (const change of [
    { dmgSHA256: "e".repeat(64) }, { artifactID: "43" },
    { runID: "124" }, { sourceCommit: "b".repeat(40) }, { version: "0.0.9" },
  ]) assert.throws(() => verifyCandidateOrigin({ ...f, expected: { ...expected, ...change } }));
});

test("production owner identities cannot authorize installer or defaults writes", () => {
  const valid = { githubActions: "true", username: "runner", home: "/Users/runner",
    temporary: "/Users/runner/work/_temp" };
  assert.doesNotThrow(() => requireDisposableRunner(valid));
  for (const change of [
    { githubActions: "false" }, { username: "williecubed" },
    { home: "/Users/williecubed" }, { temporary: "/Users/runner/work/_temp/../../owner" },
  ]) assert.throws(() => requireDisposableRunner({ ...valid, ...change }));
});

test("direct XCTest entry verifies the real disposable user before touching the installed app", () => {
  const source = readFileSync("CurfewUITests/SignedInstallerAcceptanceTests.swift", "utf8");
  for (const name of ["testSignedStagingUpgrade", "testFreshSignedInstallerOpensRealSetup"]) {
    const method = new RegExp(`func ${name}\\(\\) throws \\{([\\s\\S]*?)\\n    \\}`).exec(source)?.[1];
    assert.ok(method);
    const guard = method.indexOf("try requireDisposableUpgradeRunner(environment)");
    assert.ok(guard >= 0 && guard < method.indexOf("app.launch()"),
      "The UI entrypoint must reject owner users before launching the signed app");
  }
  const helper = /private func requireDisposableUpgradeRunner[\s\S]*?\n    \}/.exec(source)?.[0];
  assert.ok(helper);
  for (const expression of [/getpwuid\(geteuid\(\)\)/, /pw_name/, /pw_dir/,
    /GITHUB_ACTIONS/, /RUNNER_TEMP/, /"runner"/, /"\/Users\/runner"/, /"\/Users\/runner\/work\/_temp"/])
    assert.match(helper, expression);
});

test("staging feed URLs stay on unqualified localhost without trust exceptions", () => {
  assert.equal(validateLoopbackURL("http://localhost:12345/").hostname, "localhost");
  for (const url of [
    "http://127.0.0.1:12345/", "http://example.com:12345/", "file:///tmp/feed.xml",
    "http://user:secret@localhost:12345/", "http://localhost:12345/?token=private",
    "http://localhost:12345/path", "http://localhost:12345/#fragment",
  ]) assert.throws(() => validateLoopbackURL(url));
});

test("cleanup cannot remove any foreign feed override", () => {
  const owned = "http://localhost:12345/appcast.xml";
  assert.equal(defaultsRemovalAllowed(owned, owned), true);
  assert.equal(defaultsRemovalAllowed(undefined, owned), false);
  assert.throws(() => defaultsRemovalAllowed("https://example.com/feed.xml", owned));
});

test("the derived local feed preserves the exact signed enclosure bytes and signature", () => {
  const original = '<rss><channel><link>https://thecurfew.app/appcast.xml</link><item>' +
    '<sparkle:releaseNotesLink>https://thecurfew.app/releases/0.0.11.html</sparkle:releaseNotesLink>' +
    '<enclosure url="https://github.com/example/Curfew-v0.0.11.dmg" length="123" sparkle:edSignature="UNCHANGED" />' +
    '</item></channel></rss>';
  const projected = createUpgradeAppcast(original, { version: "0.0.12" }, "http://localhost:12345/");
  assert.match(projected, /url="http:\/\/localhost:12345\/Curfew-v0.0.12.dmg"/);
  assert.match(projected, /length="123" sparkle:edSignature="UNCHANGED"/);
  assert.match(projected, /http:\/\/localhost:12345\/release-notes.html/);
  assert.match(original, /url="https:\/\/github.com/);
});

test("upgrade pairs retain the accepted baseline and the same signing key", () => {
  const baseline = { ...upgradeBaseline, sparkleKey: "original-key" };
  const candidate = { version: "0.0.11", sparkleKey: "original-key" };
  validateUpgradePair(baseline, candidate);
  for (const change of [
    { version: "0.0.9" }, { sourceCommit: "c".repeat(40) }, { dmgSHA256: "a".repeat(64) },
  ]) assert.throws(() => validateUpgradePair({ ...baseline, ...change }, candidate));
  assert.throws(() => validateUpgradePair(baseline, { ...candidate, version: "0.0.8" }));
  assert.throws(() => validateUpgradePair(baseline, { ...candidate, sparkleKey: "new-key" }));
});

test("loopback HTTP serves only exact read-only assets and records actual transfers", async () => {
  const entries = [];
  const assets = new Map([["/appcast.xml", { bytes: Buffer.from("signed feed fixture"), type: "application/xml" }]]);
  let origin;
  const server = createServer((req, res) => createUpgradeHandler({ origin, assets, log: value => entries.push(value) })(req, res));
  await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
  origin = `http://localhost:${server.address().port}/`;
  const send = (path, method = "GET", host = new URL(origin).host) => new Promise((resolve, reject) => {
    const req = request({ hostname: "127.0.0.1", port: server.address().port, path, method, headers: { host } }, response => {
      const chunks = [];
      response.on("data", chunk => chunks.push(chunk));
      response.on("end", () => resolve({ status: response.statusCode, body: Buffer.concat(chunks).toString() }));
    });
    req.on("error", reject); req.end();
  });
  try {
    assert.equal(server.address().address, "127.0.0.1");
    assert.deepEqual(await send("/appcast.xml"), { status: 200, body: "signed feed fixture" });
    assert.deepEqual(await send("/appcast.xml", "HEAD"), { status: 200, body: "" });
    assert.equal((await send("/appcast.xml", "POST")).status, 405);
    assert.equal((await send("/appcast.xml", "GET", "example.com")).status, 403);
    for (const path of ["/../appcast.xml", "/%2e%2e/appcast.xml", "/secret", "/appcast.xml?token=secret"])
      assert.equal((await send(path)).status, 404);
    assert.equal(entries[0].bytes, Buffer.byteLength("signed feed fixture"));
    assert.equal(entries[1].bytes, 0);
  } finally {
    await new Promise(resolve => server.close(resolve));
  }
});

test("upgrade accepts an explicitly selected newer patch without per-version harness edits", () => {
  const baseline = { ...upgradeBaseline, sparkleKey: "original-key" };
  for (const version of ["0.0.9", "0.0.12", "0.0.123"])
    assert.doesNotThrow(() => validateUpgradePair(baseline, { version, sparkleKey: "original-key" }));
  for (const version of ["0.0.0", "0.0.7", "0.0.8", "0.0.012", "0.0.-1", "0.1.12", "v0.0.12", "0.0.12-beta", "0.0.12\n", "", undefined]) {
    assert.throws(() => validateUpgradePair(baseline, { version, sparkleKey: "original-key" }));
    assert.throws(() => createUpgradeAppcast("", { version }, "http://localhost:12345/"));
  }
});

test("explicit upgrade input rejects invalid authority before any artifact request", () => {
  const environment = { CURFEW_UPGRADE_VERSION: "0.0.12", CURFEW_UPGRADE_RUN_ID: "123",
    CURFEW_UPGRADE_SOURCE_COMMIT: "a".repeat(40), CURFEW_UPGRADE_DMG_SHA256: "d".repeat(64) };
  assert.deepEqual(upgradeRequest(environment), { version: "0.0.12", runID: "123",
    sourceCommit: "a".repeat(40), dmgSHA256: "d".repeat(64) });
  for (const change of [{ CURFEW_UPGRADE_VERSION: "0.0.8" }, { CURFEW_UPGRADE_VERSION: "0.0.012" },
    { CURFEW_UPGRADE_VERSION: undefined }, { CURFEW_UPGRADE_RUN_ID: "latest" },
    { CURFEW_UPGRADE_SOURCE_COMMIT: "main" }, { CURFEW_UPGRADE_DMG_SHA256: "" }])
    assert.throws(() => upgradeRequest({ ...environment, ...change }));
});

test("PRs check boundaries without choosing or installing a historical signed subject", () => {
  const workflow = JSON.parse(execFileSync("ruby", ["-rjson", "-ryaml", "-e",
    "puts JSON.generate(YAML.load_file(ARGV[0]))", ".github/workflows/signed-installer-acceptance.yml"], { encoding: "utf8" }));
  assert.ok(workflow.jobs.boundaries);
  assert.ok(workflow.jobs.boundaries.steps.some(step => step.run === "node --test scripts/signed-installer-acceptance.test.mjs"));
  for (const name of ["installed-candidate", "staging-upgrade"])
    assert.match(workflow.jobs[name].if, /github.event_name == 'workflow_dispatch'/);
  assert.doesNotMatch(workflow.jobs["installed-candidate"].if, /pull_request/);
  const prepare = workflow.jobs["installed-candidate"].steps.find(step => step.id === "subject");
  assert.equal(prepare.env.CURFEW_UPGRADE_VERSION, "${{ inputs.candidate_version }}");
  assert.equal(prepare.env.CURFEW_UPGRADE_RUN_ID, "${{ inputs.candidate_run_id }}");
  assert.equal(prepare.env.CURFEW_UPGRADE_SOURCE_COMMIT, "${{ inputs.candidate_source_commit }}");
  assert.equal(prepare.env.CURFEW_UPGRADE_DMG_SHA256, "${{ inputs.candidate_dmg_sha256 }}");
});

test("fresh UI runs only the immutable producer's own required walkthrough", () => {
  const workflow = JSON.parse(execFileSync("ruby", ["-rjson", "-ryaml", "-e",
    "puts JSON.generate(YAML.load_file(ARGV[0]))", ".github/workflows/signed-installer-acceptance.yml"], { encoding: "utf8" }));
  const command = workflow.jobs["installed-candidate"].steps.find(step => step.name === "Exercise the installed signed app without demo fixtures").run;
  const root = mkdtempSync(join(tmpdir(), "curfew-producer-ui-"));
  try {
    mkdirSync(join(root, "installer-source")); mkdirSync(join(root, "bin"));
    writeFileSync(join(root, "bin/xcodebuild"), '#!/bin/bash\npwd > "$UI_TRACE"\nprintf "%s\\n" "$@" >> "$UI_TRACE"\n', { mode: 0o755 });
    const result = spawnSync("bash", ["-c", command], { cwd: root, encoding: "utf8",
      env: { ...process.env, PATH: join(root, "bin") + ":" + process.env.PATH, RUNNER_TEMP: root, UI_TRACE: join(root, "trace") } });
    assert.equal(result.status, 0, result.stderr);
    const trace = readFileSync(join(root, "trace"), "utf8");
    assert.ok(trace.startsWith(realpathSync(join(root, "installer-source")) + "\n"));
    assert.match(trace, /-only-testing:CurfewUITests\/SignedInstallerAcceptanceTests\/testFreshSignedInstallerOpensRealSetup/);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test("a producer without a signed fresh walkthrough fails instead of substituting current UI tests", () => {
  const legacy = spawnSync("git", ["show", `${upgradeBaseline.sourceCommit}:CurfewUITests/SignedInstallerAcceptanceTests.swift`], { encoding: "utf8" });
  assert.notEqual(legacy.status, 0, "The retained008 producer unexpectedly gained a walkthrough");
  assert.throws(() => requireFreshWalkthrough(legacy.stdout), /Producer has no signed fresh-installer walkthrough/);
  assert.throws(() => requireFreshWalkthrough("func testDemoFixture() {}"));
  assert.doesNotThrow(() => requireFreshWalkthrough(readFileSync("CurfewUITests/SignedInstallerAcceptanceTests.swift", "utf8")));
});


test("offered version matches AppKit values as well as labels", { skip: process.platform !== "darwin" }, () => {
  const source = readFileSync("CurfewUITests/SignedInstallerAcceptanceTests.swift", "utf8");
  const format = /format: "(label CONTAINS %@[^"]*)"/.exec(source)?.[1];
  assert.ok(format, "The actual updater version predicate must be available");
  const root = mkdtempSync(join(tmpdir(), "curfew-sparkle-version-"));
  try {
    const fixture = join(root, "VersionPredicate.swift");
    writeFileSync(fixture, `import Foundation
let predicate = NSPredicate(format: CommandLine.arguments[1], argumentArray: ["0.0.14", "0.0.14"])
let examples: [([String: String], Bool)] = [
  (["label": "Curfew 0.0.14 is now available", "value": ""], true),
  (["label": "", "value": "Curfew 0.0.14 is now available—you have 0.0.8."], true),
  (["label": "Question", "value": "Curfew 0.0.8 is now available"], false),
  (["label": "", "value": ""], false)
]
for (attributes, expected) in examples {
  guard predicate.evaluate(with: attributes) == expected else {
    fputs("Updater version predicate did not match the text field attributes correctly", stderr)
    exit(1)
  }
}
`);
    const result = spawnSync("xcrun", ["swift", fixture, format], { encoding: "utf8" });
    assert.equal(result.status, 0, result.stderr);
  } finally { rmSync(root, { recursive: true, force: true }); }
});

test("upgrade harness keeps producer commands on validated immutable source", () => {
  const workflow = JSON.parse(execFileSync("ruby", ["-rjson", "-ryaml", "-e",
    "puts JSON.generate(YAML.load_file(ARGV[0]))", ".github/workflows/signed-installer-acceptance.yml"], { encoding: "utf8" }));
  const steps = workflow.jobs["staging-upgrade"].steps;
  const checkout = steps.find(step => step.with?.path === "candidate-source");
  assert.ok(checkout, "Upgrade needs a separate immutable producer checkout");
  assert.equal(checkout.with.ref, "${{ steps.subject.outputs.source_commit }}");
  const authority = steps.find(step => step.id === "subject");
  assert.match(authority.run, /node scripts\/signed-installer-acceptance\.mjs prepare /);
  assert.ok(steps.indexOf(authority) < steps.indexOf(checkout));
  for (const name of ["Retain the pinned older build and exact new subject", "Verify the exact new candidate before the update",
    "Perform the real Sparkle update and verify installed bytes", "Confirm disposable defaults cleanup even after failure"]) {
    assert.equal(steps.find(step => step.name === name)["working-directory"], "candidate-source", name);
  }
  const update = steps.find(step => step.name === "Perform the real Sparkle update and verify installed bytes");
  assert.match(update.run, /xcodebuild test -project \.\.\/Curfew\.xcodeproj/);
  const retain = steps.find(step => step.name === "Retain exact subjects and actual update results");
  assert.match(retain.with.path, /sparkle-harness-source\.json/);
});
