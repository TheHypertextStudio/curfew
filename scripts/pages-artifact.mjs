import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, readdir, lstat, writeFile } from "node:fs/promises";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { verifyArtifact } from "./deployment-config.mjs";

export async function sealWebsite(directory, deployment) {
  verifyArtifact(deployment, deployment.sha256, deployment.sourceCommit);
  for (const path of ["index.html", "_worker.js/index.js", "_routes.json"])
    assert.ok(
      (await lstat(join(directory, path))).isFile(),
      "Incomplete website build",
    );
  const routes = JSON.parse(
    await readFile(join(directory, "_routes.json"), "utf8"),
  );
  assert.equal(routes.version, 1);
  assert.deepEqual(
    routes.include,
    ["/*"],
    "Website middleware must handle every public path",
  );
  assert.deepEqual(routes.exclude, [], "Website middleware cannot be bypassed");
  const files = [];
  const visit = async (relative = "") => {
    for (const name of (await readdir(join(directory, relative))).sort()) {
      const path = relative ? `${relative}/${name}` : name;
      const stat = await lstat(join(directory, path));
      if (stat.isDirectory()) await visit(path);
      else if (stat.isFile())
        files.push([
          path,
          createHash("sha256")
            .update(await readFile(join(directory, path)))
            .digest("hex"),
        ]);
      else
        throw new Error(
          "Website build contains an unsupported filesystem entry",
        );
    }
  };
  await visit();
  return Object.freeze({
    schemaVersion: 1,
    sourceCommit: deployment.sourceCommit,
    configurationSHA256: deployment.sha256,
    contentSHA256: createHash("sha256")
      .update(JSON.stringify(files))
      .digest("hex"),
  });
}

export async function verifyWebsite(
  directory,
  stamp,
  deployment,
  expectedHash,
  expectedCommit,
) {
  verifyArtifact(deployment, expectedHash, expectedCommit);
  assert.deepEqual(
    stamp,
    await sealWebsite(directory, deployment),
    "Retained website build identity mismatch",
  );
  return stamp;
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  const [directory, artifactPath, stampPath] = process.argv.slice(2);
  const deployment = JSON.parse(await readFile(artifactPath, "utf8"));
  verifyArtifact(deployment, deployment.sha256, process.env.GITHUB_SHA);
  await writeFile(
    stampPath,
    JSON.stringify(await sealWebsite(directory, deployment), null, 2) + "\n",
    { flag: "wx" },
  );
}
