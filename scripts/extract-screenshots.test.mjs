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
      await writeFile(path, `#!/bin/sh
case " $* " in
  *" ${name === "swift" ? "--jobs" : "-jobs"} 2 "*) ;;
  *) echo "Missing bounded concurrency for ${name}" >&2; exit 97 ;;
esac
exit ${exitCode}
`);
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

for (const selected of [undefined, "testCaptureDistinctSettingsStates"]) {
  test(`capture passes only its selected test to Xcode: ${selected ?? "full matrix"}`, async () => {
    const root = await mkdtemp(join(tmpdir(), "curfew-capture-selection-"));
    try {
      const scripts = join(root, "scripts");
      const binaries = join(root, "bin");
      await mkdir(scripts);
      await mkdir(binaries);
      await copyFile("scripts/extract-screenshots.sh", join(scripts, "extract-screenshots.sh"));
      await writeFile(join(binaries, "swift"), "#!/bin/sh\nexit 0\n", { mode: 0o755 });
      await writeFile(join(binaries, "xcodebuild"), '#!/bin/sh\nprintf \'%s\\n\' "$@"\nexit 65\n', { mode: 0o755 });
      const env = { ...process.env, PATH: `${binaries}:${process.env.PATH}` };
      delete env.CURFEW_CAPTURE_TEST;
      if (selected) env.CURFEW_CAPTURE_TEST = selected;
      const result = spawnSync("bash", [join(scripts, "extract-screenshots.sh")], { encoding: "utf8", env });
      assert.equal(result.status, 65, result.stdout + result.stderr);
      const selection = result.stdout.split("\n").filter(line => line.startsWith("-only-testing:"));
      assert.deepEqual(selection, [`-only-testing:CurfewUITests/MarketingCaptureTests${selected ? `/${selected}` : ""}`]);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
}

test("capture rejects malformed test selectors before starting a build", async () => {
  const root = await mkdtemp(join(tmpdir(), "curfew-capture-invalid-"));
  try {
    const scripts = join(root, "scripts");
    const binaries = join(root, "bin");
    await mkdir(scripts);
    await mkdir(binaries);
    await copyFile("scripts/extract-screenshots.sh", join(scripts, "extract-screenshots.sh"));
    for (const name of ["swift", "xcodebuild"]) {
      await writeFile(join(binaries, name), "#!/bin/sh\nexit 99\n", { mode: 0o755 });
    }
    const result = spawnSync("bash", [join(scripts, "extract-screenshots.sh")], {
      encoding: "utf8",
      env: { ...process.env, PATH: `${binaries}:${process.env.PATH}`, CURFEW_CAPTURE_TEST: "../CurfewTests" },
    });
    assert.equal(result.status, 2, result.stdout + result.stderr);
    assert.match(result.stderr, /Invalid capture test/);
    assert.doesNotMatch(result.stdout, /Pre-building/);
  } finally {
    await rm(root, { recursive: true, force: true });
  }
});
