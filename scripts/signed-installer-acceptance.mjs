import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { readFile, mkdir, writeFile } from "node:fs/promises";
import { join, resolve } from "node:path";
import { pathToFileURL } from "node:url";
import { verifyCandidate } from "./release-candidate.mjs";

const repository = "TheHypertextStudio/curfew";
export function selectCandidateRun(runs) {
  const candidates = runs.filter(value => /^v0\.0\.(0|[1-9]\d*)$/.test(value.headBranch))
    .sort((left, right) => Number(right.headBranch.slice(5)) - Number(left.headBranch.slice(5)));
  assert.ok(candidates.length, "No successful tagged signed candidate is retained");
  return { run: candidates[0], version: candidates[0].headBranch.slice(1) };
}
export function verifyCandidateOrigin({ candidate, artifact, tagCommit, version }) {
  assert.match(tagCommit, /^[a-f0-9]{40}$/);
  assert.equal(candidate.version, version);
  assert.equal(candidate.sourceCommit, tagCommit);
  assert.equal(artifact.name, "curfew-signed-candidate");
  assert.equal(artifact.expired, false);
  assert.equal(artifact.workflow_run.repository_id, 1165282307);
  assert.equal(String(artifact.workflow_run.id), candidate.runID);
  assert.equal(artifact.workflow_run.head_branch, `v${version}`);
  assert.equal(artifact.workflow_run.head_sha, tagCommit);
  return candidate;
}
const gh = args => JSON.parse(execFileSync("gh", args, { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }));
async function prepare(directory) {
  const runs = gh(["run", "list", "--repo", repository, "--workflow", "release.yml",
    "--status", "success", "--limit", "20", "--json", "databaseId,headSha,headBranch"]);
  const { run, version } = selectCandidateRun(runs);
  const tag = `v${version}`;
  let ref = gh(["api", `repos/${repository}/git/ref/tags/${tag}`]).object;
  if (ref.type === "tag") ref = gh(["api", `repos/${repository}/git/tags/${ref.sha}`]).object;
  assert.equal(ref.type, "commit");
  assert.equal(run.headSha, ref.sha, "Release tag and candidate run differ");
  const artifacts = gh(["api", `repos/${repository}/actions/runs/${run.databaseId}/artifacts`]).artifacts
    .filter(value => value.name === "curfew-signed-candidate" && !value.expired);
  assert.equal(artifacts.length, 1, "One retained candidate artifact is required");
  const artifact = gh(["api", `repos/${repository}/actions/artifacts/${artifacts[0].id}`]);
  await mkdir(directory);
  execFileSync("gh", ["run", "download", String(run.databaseId), "--repo", repository,
    "--name", "curfew-signed-candidate", "--dir", directory], { stdio: "inherit" });
  const candidate = JSON.parse(await readFile(join(directory, "candidate.json"), "utf8"));
  verifyCandidateOrigin({ candidate, artifact, tagCommit: ref.sha, version });
  verifyCandidate({ candidate, dmg: await readFile(join(directory, `Curfew-v${version}.dmg`)),
    appcast: await readFile(join(directory, "appcast.xml")),
    configuration: JSON.parse(await readFile(join(directory, "release-configuration.json"), "utf8")) });
  await writeFile(join(directory, "acceptance-subject.json"), JSON.stringify({
    version, sourceCommit: candidate.sourceCommit, dmgSHA256: candidate.dmgSHA256,
    configurationSHA256: candidate.configurationSHA256, artifactID: artifact.id,
    runID: run.databaseId, scope: "Exact signed installer; installation and UI outcomes recorded separately",
  }, null, 2) + "\n");
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  assert.equal(process.argv[2], "prepare");
  assert.ok(process.argv[3], "A new candidate directory is required");
  await prepare(resolve(process.argv[3]));
}
