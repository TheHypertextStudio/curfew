import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmod, copyFile, mkdtemp, mkdir, rm, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";

test("screenshot capture fails when its UI test fails", async () => {
  const root = await mkdtemp(join(tmpdir(), "curfew-capture-test-"));
  try {
    const scripts = join(root, "scripts");
    const binaries = join(root, "bin");
    await mkdir(scripts);
    await mkdir(binaries);
    await copyFile("scripts/extract-screenshots.sh", join(scripts, "extract-screenshots.sh"));
    for (const [name, exitCode] of [["swift", 0], ["xcodebuild", 65], ["xcrun", 0]]) {
      const path = join(binaries, name);
      await writeFile(path, `#!/bin/sh\nexit ${exitCode}\n`);
      await chmod(path, 0o755);
    }

    const result = spawnSync("bash", [join(scripts, "extract-screenshots.sh")], {
      encoding: "utf8",
      env: { ...process.env, PATH: `${binaries}:${process.env.PATH}` },
    });
    assert.equal(result.status, 65, result.stdout + result.stderr);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
