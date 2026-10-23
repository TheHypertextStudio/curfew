import assert from "node:assert/strict";
import test from "node:test";
import { createServer, request } from "node:http";
import { readFileSync } from "node:fs";
import { verifyCandidateOrigin, selectCandidateRun } from "./signed-installer-acceptance.mjs";
import {
  requireDisposableRunner, validateLoopbackURL, defaultsRemovalAllowed,
  createUpgradeAppcast,
  validateUpgradePair, upgradeBaseline, createUpgradeHandler,
} from "./signed-installer-acceptance.mjs";

function fixture() {
  return { candidate: { version: "0.0.8", runID: "123", sourceCommit: "a".repeat(40) },
    artifact: { name: "curfew-signed-candidate", expired: false,
      workflow_run: { id: 123, head_branch: "v0.0.8", head_sha: "a".repeat(40), repository_id: 1165282307 } },
    tagCommit: "a".repeat(40), version: "0.0.8" };
}
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
test("release selection uses retained signed tags instead of the project development version", () => {
  const result = selectCandidateRun([
    { databaseId: 10, headBranch: "v0.0.7", headSha: "a".repeat(40) },
    { databaseId: 20, headBranch: "v0.0.8", headSha: "b".repeat(40) },
    { databaseId: 30, headBranch: "main", headSha: "c".repeat(40) },
  ]);
  assert.equal(result.version, "0.0.8");
  assert.equal(result.run.databaseId, 20);
  assert.throws(() => selectCandidateRun([]));
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
  const method = /func testSignedStagingUpgrade\(\) throws \{([\s\S]*?)\n    \}/.exec(source)?.[1];
  assert.ok(method);
  const guard = method.indexOf("try requireDisposableUpgradeRunner(environment)");
  assert.ok(guard >= 0 && guard < method.indexOf("app.launch()"),
    "The UI entrypoint must reject owner users before launching the signed app");
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
  const projected = createUpgradeAppcast(original, { version: "0.0.11" }, "http://localhost:12345/");
  assert.match(projected, /url="http:\/\/localhost:12345\/Curfew-v0.0.11.dmg"/);
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
