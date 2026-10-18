import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdtemp, mkdir, rm, stat } from "node:fs/promises";
import { tmpdir } from "node:os";
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
