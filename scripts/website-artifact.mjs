import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile, readdir, lstat, writeFile } from "node:fs/promises";
import { resolve, join } from "node:path";
import { fileURLToPath } from "node:url";
import { verifyArtifact } from "./deployment-config.mjs";

export async function sealWebsite(directory, deployment, mode = "production") {
  await verifyPurchaseEnvironment(directory, deployment.manifest, mode);
  verifyArtifact(deployment, deployment.sha256, deployment.sourceCommit);
  assert.ok(
    (await lstat(join(directory, "index.html"))).isFile(),
    "Incomplete website build",
  );
  for (const path of ["_worker.js", "_routes.json"])
    await assert.rejects(
      () => lstat(join(directory, path)),
      { code: "ENOENT" },
      "Static output must not contain obsolete Pages runtime files",
    );
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
    schemaVersion: 2,
    deploymentMode: mode,
    sourceCommit: deployment.sourceCommit,
    configurationSHA256: deployment.sha256,
    contentSHA256: createHash("sha256")
      .update(JSON.stringify(files))
      .digest("hex"),
  });
}

async function verifyPurchaseEnvironment(directory, manifest, mode) {
  assert.ok(
    ["production", "staging"].includes(mode),
    "Unsupported website deployment mode",
  );
  const profile = manifest.environments[mode];
  assert.ok(profile, "Missing website deployment profile");
  const scheme = mode === "production" ? "curfew" : "curfew-studio-dev";
  for (const [page, kind] of [
    ["success", "checkout"],
    ["restore", "restore"],
  ]) {
    const html = await readFile(join(directory, `${page}.html`), "utf8");
    const panels = [
      ...html.matchAll(/<div\b[^>]*\bdata-purchase-mode="[^"]*"[^>]*>/g),
    ];
    assert.equal(
      panels.length,
      1,
      "Purchase page environment must be unambiguous",
    );
    const attributes = Object.fromEntries(
      [
        ...panels[0][0].matchAll(
          /\b(data-(?:purchase-mode|issuer|scheme))="([^"]*)"/g,
        ),
      ].map((match) => [match[1], match[2]]),
    );
    assert.deepEqual(
      attributes,
      {
        "data-purchase-mode": kind,
        "data-issuer": profile.licenseOrigin,
        "data-scheme": scheme,
      },
      "Purchase page environment does not match the retained deployment mode",
    );
  }
}

export async function verifyWebsite(
  directory,
  stamp,
  deployment,
  expectedHash,
  expectedCommit,
  mode = "production",
) {
  verifyArtifact(deployment, expectedHash, expectedCommit);
  assert.deepEqual(
    stamp,
    await sealWebsite(directory, deployment, mode),
    "Retained website build identity mismatch",
  );
  return stamp;
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  if (process.argv[2] === "check-environment") {
    const [directory, manifestPath, mode] = process.argv.slice(3);
    const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
    await verifyPurchaseEnvironment(directory, manifest, mode);
  } else {
    const [directory, artifactPath, stampPath, mode = "production"] =
      process.argv.slice(2);
    const deployment = JSON.parse(await readFile(artifactPath, "utf8"));
    verifyArtifact(deployment, deployment.sha256, process.env.GITHUB_SHA);
    await writeFile(
      stampPath,
      JSON.stringify(await sealWebsite(directory, deployment, mode), null, 2) +
        "\n",
      { flag: "wx" },
    );
  }
}
