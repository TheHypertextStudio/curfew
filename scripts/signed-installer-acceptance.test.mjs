import assert from "node:assert/strict";
import test from "node:test";
import { verifyCandidateOrigin, selectCandidateRun } from "./signed-installer-acceptance.mjs";

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
