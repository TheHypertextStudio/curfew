import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { chmod, copyFile, mkdtemp, mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
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

// MarketingCaptureTests spreads its tests across extensions in several files.
// Read every top-level declaration of the class so the allowlist check covers
// all of them, and nothing declared on another test class.
async function declaredCaptureTests() {
  const directory = "CurfewUITests";
  const names = [];
  for (const file of (await readdir(directory)).filter(name => name.endsWith(".swift"))) {
    const source = await readFile(join(directory, file), "utf8");
    const blocks = source.matchAll(/^(?:final class|extension) MarketingCaptureTests\b[^{]*\{([\s\S]*?)^\}/gm);
    for (const [, body] of blocks) {
      names.push(...[...body.matchAll(/func (testCapture\w+)\(/g)].map(match => match[1]));
    }
  }
  return names.sort();
}

const captureTests = await declaredCaptureTests();

async function captureSelection({ argument, environment }) {
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
    if (environment) env.CURFEW_CAPTURE_TEST = environment;
    const args = [join(scripts, "extract-screenshots.sh"), ...(argument ? [argument] : [])];
    const result = spawnSync("bash", args, { encoding: "utf8", env });
    assert.equal(result.status, 65, result.stdout + result.stderr);
    return result.stdout.split("\n").filter(line => line.startsWith("-only-testing:"));
  } finally {
    await rm(root, { recursive: true, force: true });
  }
}

test("capture runs the full matrix when no test is named", async () => {
  assert.deepEqual(await captureSelection({}), ["-only-testing:CurfewUITests/MarketingCaptureTests"]);
});

for (const selected of captureTests) {
  test(`capture passes only the named test to Xcode: ${selected}`, async () => {
    const expected = [`-only-testing:CurfewUITests/MarketingCaptureTests/${selected}`];
    assert.deepEqual(await captureSelection({ argument: selected }), expected);
    assert.deepEqual(await captureSelection({ environment: selected }), expected);
  });
}

test("a named argument takes precedence over the environment selector", async () => {
  const selection = await captureSelection({
    argument: "testCaptureOverlays",
    environment: "testCaptureDistinctSettingsStates",
  });
  assert.deepEqual(selection, ["-only-testing:CurfewUITests/MarketingCaptureTests/testCaptureOverlays"]);
});

for (const [label, selector] of [
  ["environment", { environment: "../CurfewTests" }],
  ["argument", { argument: "CurfewUITests/CurfewUITests" }],
  ["argument typo", { argument: "testCaptureOverlay" }],
]) {
  test(`capture rejects malformed test selectors before starting a build: ${label}`, async () => {
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
      const env = { ...process.env, PATH: `${binaries}:${process.env.PATH}` };
      delete env.CURFEW_CAPTURE_TEST;
      if (selector.environment) env.CURFEW_CAPTURE_TEST = selector.environment;
      const args = [join(scripts, "extract-screenshots.sh"), ...(selector.argument ? [selector.argument] : [])];
      const result = spawnSync("bash", args, { encoding: "utf8", env });
      assert.equal(result.status, 2, result.stdout + result.stderr);
      assert.match(result.stderr, /Invalid capture test/);
      assert.doesNotMatch(result.stdout, /Pre-building/);
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
}

test("the allowlist names exactly the capture tests MarketingCaptureTests declares", async () => {
  const script = await readFile("scripts/extract-screenshots.sh", "utf8");
  const selector = script.match(/^case "\$selected_test" in$([\s\S]*?)^esac$/m)?.[1] ?? "";
  const allowed = [...new Set([...selector.matchAll(/\btestCapture\w+/g)].map(match => match[0]))].sort();
  assert.ok(captureTests.length > 0, "MarketingCaptureTests must declare capture tests");
  assert.deepEqual(allowed, captureTests);
});
