import test from "node:test";
import assert from "node:assert/strict";
import { writeFile, unlink } from "node:fs/promises";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

test("license tests ignore the enclosing backend's Vitest configuration", async (t) => {
  const project = fileURLToPath(new URL("../", import.meta.url));
  const ancestor = new URL("../../vitest.config.ts", import.meta.url);
  await writeFile(
    ancestor,
    'throw new Error("Enclosing backend configuration must not load")\n',
    { flag: "wx" },
  );
  t.after(() => unlink(ancestor));
  const result = spawnSync(
    `${project}node_modules/.bin/vitest`,
    ["list", "--filesOnly", "--json"],
    { cwd: project, encoding: "utf8", timeout: 30_000 },
  );
  assert.equal(result.status, 0, result.stderr);
  const files = JSON.parse(result.stdout).map((value) => value.file);
  assert.ok(
    files.some((path) => path.endsWith("/test/domain.test.ts")),
    "License behavior tests must remain selected",
  );
  assert.ok(
    files.every((path) => path.startsWith(`${project}test/`)),
    "Only this license project's tests may run",
  );
});
