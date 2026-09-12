import { execFile } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { promisify } from "node:util";

import { afterEach, describe, expect, it } from "vitest";

import {
  DEVELOPMENT_EXTENSION_ID,
  DEVELOPMENT_PUBLIC_KEY,
} from "../scripts/manifest.mjs";

const run = promisify(execFile);
const temporaryDirectories: string[] = [];
const productionIdentity = {
  CURFEW_BROWSER_EXTENSION_PUBLIC_KEY: DEVELOPMENT_PUBLIC_KEY,
  CURFEW_BROWSER_EXTENSION_ID: DEVELOPMENT_EXTENSION_ID,
};

afterEach(async () => {
  await Promise.all(temporaryDirectories.splice(0).map((directory) =>
    rm(directory, { recursive: true, force: true })));
});

describe("production upload package", () => {
  it("contains only the built extension files", async () => {
    const directory = await mkdtemp(resolve(tmpdir(), "curfew-extension-package-"));
    temporaryDirectories.push(directory);
    const output = resolve(directory, "curfew-browser.zip");
    const staleBuildFile = resolve("dist/production/stale.txt");
    await mkdir(resolve("dist/production"), { recursive: true });
    await writeFile(staleBuildFile, "not part of this build");

    await run(
      process.execPath,
      [resolve("scripts/package.mjs"), "--output", output],
      { env: { ...process.env, ...productionIdentity } },
    );

    const { stdout } = await run("/usr/bin/unzip", ["-Z1", output]);
    expect(stdout.trim().split("\n")).toEqual([
      "background.js",
      "blocker.css",
      "blocker.html",
      "blocker.js",
      "icons/icon-128.png",
      "icons/icon-16.png",
      "icons/icon-32.png",
      "icons/icon-48.png",
      "manifest.json",
    ]);
    const manifest = JSON.parse((await run("/usr/bin/unzip", [
      "-p", output, "manifest.json",
    ])).stdout) as { key: string };
    expect(manifest.key).toBe(DEVELOPMENT_PUBLIC_KEY);
    expect((await readFile(output)).byteLength).toBeGreaterThan(0);
    await rm(staleBuildFile, { force: true });
  });

  it("refuses to package without the production identity", async () => {
    const directory = await mkdtemp(resolve(tmpdir(), "curfew-extension-package-"));
    temporaryDirectories.push(directory);
    const output = resolve(directory, "curfew-browser.zip");

    await expect(run(
      process.execPath,
      [resolve("scripts/package.mjs"), "--output", output],
      { env: process.env },
    )).rejects.toThrow(/production public key.*extension ID/i);
  });
});
