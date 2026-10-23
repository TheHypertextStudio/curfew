import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import {
  mkdtemp,
  mkdir,
  writeFile,
  copyFile,
  access,
  rm,
} from "node:fs/promises";
import { constants } from "node:fs";
import { tmpdir, homedir } from "node:os";
import { join, resolve } from "node:path";
import test from "node:test";

const wrapper = resolve("scripts/swiftformat.sh");
const version = "0.63.1";

async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), "curfew-formatter-"));
  t.after(() => rm(root, { recursive: true, force: true }));
  const bin = join(root, "bin");
  await mkdir(bin);
  const invoked = join(root, "global-invoked");
  await writeFile(
    join(bin, "swiftformat"),
    `#!/bin/sh\nprintf unpinned > '${invoked}'\n`,
    { mode: 0o755 },
  );
  await writeFile(
    join(bin, "curl"),
    `#!/bin/sh\nwhile [ "$#" -gt 0 ]; do\n if [ "$1" = -o ]; then shift; printf corrupt > "$1"; exit 0; fi\n shift\ndone\nexit 2\n`,
    { mode: 0o755 },
  );
  return {
    root,
    bin,
    invoked,
    env: {
      ...process.env,
      PATH: `${bin}:${process.env.PATH}`,
      XDG_CACHE_HOME: join(root, "cache"),
    },
  };
}

const run = (script, args, env, cwd) =>
  spawnSync(script, args, { env, cwd, encoding: "utf8", timeout: 150000 });

// This gate existed before the pinned wrapper: its behavior must reject an
// unverified formatter on PATH rather than silently use the newest Homebrew.
test("format gate ignores an unpinned global formatter", async (t) => {
  const f = await fixture(t);
  await copyFile(resolve("justfile"), join(f.root, "justfile"));
  await mkdir(join(f.root, "scripts"));
  try {
    await copyFile(wrapper, join(f.root, "scripts/swiftformat.sh"));
  } catch (error) {
    if (error.code !== "ENOENT") throw error;
  }
  const result = run("just", ["format-check"], f.env, f.root);
  await assert.rejects(access(f.invoked), { code: "ENOENT" });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /SHA-256/);
});

test("downloaded formatter archive must match the fixed SHA-256", async (t) => {
  const f = await fixture(t);
  const result = run(wrapper, ["--version"], f.env);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /archive SHA-256/);
  await assert.rejects(
    access(
      join(f.env.XDG_CACHE_HOME, "curfew/swiftformat", version, "swiftformat"),
    ),
    { code: "ENOENT" },
  );
});

test("corrupt cached formatter cannot execute even if it reports the pinned version", async (t) => {
  const f = await fixture(t);
  const directory = join(f.env.XDG_CACHE_HOME, "curfew/swiftformat", version);
  await mkdir(directory, { recursive: true });
  await writeFile(
    join(directory, "swiftformat"),
    `#!/bin/sh\nprintf '${version}\\n'\nprintf executed > '${f.invoked}'\n`,
    { mode: 0o755 },
  );
  const result = run(wrapper, ["--version"], f.env);
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /archive SHA-256/);
  await assert.rejects(access(f.invoked), { code: "ENOENT" });
});

test("official verified formatter cache works offline and preserves CLI arguments and exits", async (t) => {
  // This one integration check obtains the real, fixed official asset on the
  // first run. All later calls use its verified shared cache; no test URL or
  // digest override exists in the wrapper.
  const official = run(wrapper, ["--version"], process.env);
  assert.equal(official.status, 0, official.stderr);
  assert.equal(official.stdout.trim(), version);
  const f = await fixture(t);
  const directory = join(f.env.XDG_CACHE_HOME, "curfew/swiftformat", version);
  await mkdir(directory, { recursive: true });
  const shared = join(
    process.env.XDG_CACHE_HOME || join(homedir(), ".cache"),
    "curfew/swiftformat",
    version,
    "swiftformat",
  );
  await copyFile(
    shared,
    join(directory, "swiftformat"),
    constants.COPYFILE_FICLONE,
  );
  await writeFile(
    join(f.bin, "curl"),
    `#!/bin/sh\nprintf downloaded > '${f.invoked}'\nexit 88\n`,
    { mode: 0o755 },
  );
  const file = join(f.root, "source with spaces.swift");
  const report = join(f.root, "report with spaces.json");
  await writeFile(file, "let value=1\n");
  const lint = run(
    wrapper,
    [
      file,
      "--lint",
      "--cache",
      "ignore",
      "--report",
      report,
      "--reporter",
      "json",
    ],
    f.env,
  );
  assert.equal(lint.status, 1, lint.stderr);
  await access(report);
  assert.equal(
    run(wrapper, [file, "--cache", "ignore", "--quiet"], f.env).status,
    0,
  );
  assert.equal(
    run(wrapper, [file, "--lint", "--cache", "ignore"], f.env).status,
    0,
  );
  await assert.rejects(access(f.invoked), { code: "ENOENT" });
});
