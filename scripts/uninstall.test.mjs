import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, rm, stat, writeFile, readFile, access } from "node:fs/promises";
import { tmpdir, homedir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

test("shared-storage removal covers new production snapshots and legacy history without touching development groups", async (t) => {
  const root = await mkdtemp(join(tmpdir(), "curfew-uninstall-paths-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const groupRoot = join(root, "Library/Group Containers");
  const groups = [
    "group.studio.hypertext.curfew",
    "group.studio.hypertext.apps.curfew",
    "group.studio.hypertext.curfew.dev",
    "group.studio.hypertext.curfew.studio.dev",
  ];
  for (const group of groups)
    await mkdir(join(groupRoot, group, "Curfew"), { recursive: true });
  // Source only the isolated cleanup function; never execute the uninstall flow.
  const result = spawnSync(
    "bash",
    [
      "-c",
      `
    source "$1"
    confirm() { return 0; }
    say() { :; }
    remove_shared_storage "$2"
  `,
      "curfew-uninstall-test",
      resolve("scripts/uninstall.sh"),
      root,
    ],
    { encoding: "utf8" },
  );
  assert.equal(result.status, 0, result.stderr);
  for (const group of groups.slice(0, 2))
    await assert.rejects(() => stat(join(groupRoot, group, "Curfew")), {
      code: "ENOENT",
    });
  for (const group of groups.slice(2))
    assert.ok((await stat(join(groupRoot, group, "Curfew"))).isDirectory());
});


test("development uninstall honors the explicit bundle and leaves production and privileged state alone", {skip: process.platform !== "darwin"}, async (t) => {
  await access("/usr/bin/sandbox-exec");
  const root = await mkdtemp(join(tmpdir(), "curfew-uninstall-execution-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const app = join(root, "Fixture.app");
  await mkdir(join(app, "Contents/MacOS"), {recursive: true});
  await writeFile(join(app, "Contents/Info.plist"), `<?xml version="1.0"?><plist version="1.0"><dict><key>CFBundleIdentifier</key><string>studio.hypertext.apps.curfew.dev</string><key>CFBundleExecutable</key><string>Curfew</string></dict></plist>`);
  await writeFile(join(app, "Contents/MacOS/Curfew"), '#!/bin/sh\nprintf "%s\\n" "$1" > "$HOME/operation"\n', {mode: 0o755});
  const state = join(root, "Library/Application Support/Curfew (Studio Dev)");
  const production = join(root, "Library/Application Support/Curfew");
  await mkdir(state, {recursive: true});
  await mkdir(production, {recursive: true});
  await writeFile(join(state, "enforcement-runtime.json"), "development");
  await writeFile(join(production, "enforcement-runtime.json"), "production");
  // Even a broken parser cannot execute an installed app or mutate real user/root state.
  const profile = `(version 1)(allow default)(deny process-exec (subpath "/Applications") (literal "/usr/bin/sudo") (literal "/bin/launchctl") (literal "/usr/bin/defaults"))(deny file-write* (subpath "/Library") (subpath ${JSON.stringify(homedir())}))`;
  const result = spawnSync("/usr/bin/sandbox-exec", ["-p", profile, "/bin/bash", resolve("scripts/uninstall.sh"), "--force", "--app-bundle", app, "--development"], {env: {...process.env, HOME: root}, encoding: "utf8"});
  assert.equal(result.status, 0, result.stderr);
  assert.equal((await readFile(join(root, "operation"), "utf8")).trim(), "--unregister-background-service");
  await assert.rejects(() => stat(state), {code: "ENOENT"});
  assert.equal(await readFile(join(production, "enforcement-runtime.json"), "utf8"), "production");
});
