import { execFile } from "node:child_process";
import { mkdir, readFile, readdir, rm, utimes } from "node:fs/promises";
import { dirname, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

import { extensionIDFromPublicKey } from "./manifest.mjs";

const run = promisify(execFile);
const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const flavor = process.argv.includes("--draft") ? "draft" : "production";
const buildDirectory = resolve(packageDirectory, "dist", flavor);
const outputArgument = process.argv.indexOf("--output");
const outputPath = outputArgument === -1
  ? resolve(packageDirectory, `dist/curfew-browser-${flavor}.zip`)
  : resolve(process.argv[outputArgument + 1]);

await rm(buildDirectory, { recursive: true, force: true });
await run(process.execPath, [resolve(packageDirectory, "scripts/build.mjs"), flavor], {
  env: process.env,
});

const manifest = JSON.parse(await readFile(
  resolve(buildDirectory, "manifest.json"),
  "utf8",
));
if (
  flavor === "production" &&
  extensionIDFromPublicKey(manifest.key) !== process.env.CURFEW_BROWSER_EXTENSION_ID
) {
  throw new Error("The built production manifest does not match the configured extension ID");
}

/**
 * @param {string} directory
 * @returns {Promise<string[]>}
 */
async function builtFiles(directory) {
  const entries = await readdir(directory, { withFileTypes: true });
  /** @type {string[]} */
  const files = [];
  for (const entry of entries) {
    const path = resolve(directory, entry.name);
    if (entry.isDirectory()) {
      files.push(...await builtFiles(path));
    } else if (entry.isFile()) {
      files.push(relative(buildDirectory, path).split(sep).join("/"));
    }
  }
  return files.sort();
}

const files = await builtFiles(buildDirectory);
const fixedTimestamp = new Date("1980-01-01T00:00:00.000Z");
for (const file of files) {
  await utimes(resolve(buildDirectory, file), fixedTimestamp, fixedTimestamp);
}
await mkdir(dirname(outputPath), { recursive: true });
await rm(outputPath, { force: true });
await run("/usr/bin/zip", ["-X", "-q", outputPath, ...files], {
  cwd: buildDirectory,
});
