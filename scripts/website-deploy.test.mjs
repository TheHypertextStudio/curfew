import assert from "node:assert/strict";
import test from "node:test";
import {
  mkdtemp,
  mkdir,
  readFile,
  writeFile,
  copyFile,
  symlink,
  rm,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join, delimiter } from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL("../", import.meta.url));
const pkg = JSON.parse(
  await readFile(join(root, "landing/package.json"), "utf8"),
);

async function deployFixture(t, mode, wrongOutput = false) {
  const directory = await mkdtemp(join(tmpdir(), "curfew-deploy-command-"));
  t.after(() => rm(directory, { recursive: true, force: true }));
  await mkdir(join(directory, "landing"));
  await mkdir(join(directory, "bin"));
  await mkdir(join(directory, "scripts"));
  for (const script of ["website-artifact.mjs", "deployment-config.mjs"]) {
    await copyFile(
      join(root, "scripts", script),
      join(directory, "scripts", script),
    );
  }
  await symlink(join(root, "deployment"), join(directory, "deployment"));
  await writeFile(
    join(directory, "bin/astro"),
    `#!/usr/bin/env node
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
const actualMode = ${wrongOutput ? JSON.stringify(mode === "staging" ? "production" : "staging") : "process.env.CURFEW_DEPLOYMENT_MODE || 'production'"};
const manifest = JSON.parse(readFileSync('../deployment/environments.json', 'utf8'));
mkdirSync('dist', { recursive: true });
for (const [page, kind] of [['success', 'checkout'], ['restore', 'restore']]) {
  writeFileSync('dist/' + page + '.html', '<div data-purchase-mode="' + kind + '" data-issuer="' + manifest.environments[actualMode].licenseOrigin + '" data-scheme="' + (actualMode === 'production' ? 'curfew' : 'curfew-dev') + '"></div>');
}
writeFileSync('built-mode', actualMode);
`,
    { mode: 0o755 },
  );
  await writeFile(
    join(directory, "bin/pnpm"),
    `#!/usr/bin/env node
import { appendFileSync } from 'node:fs';
appendFileSync('provider-commands', JSON.stringify({ args: process.argv.slice(2), assetsDirectory: process.env.CURFEW_WEBSITE_ASSETS_DIRECTORY }) + '\\n');
`,
    { mode: 0o755 },
  );
  const result = spawnSync(
    "/bin/sh",
    ["-c", pkg.scripts[`deploy:worker:${mode}`]],
    {
      cwd: join(directory, "landing"),
      env: {
        ...process.env,
        PATH: join(directory, "bin") + delimiter + process.env.PATH,
        CURFEW_DEPLOYMENT_MODE: mode === "staging" ? "production" : "staging",
        CURFEW_WEBSITE_ASSETS_DIRECTORY: "/unrelated/staging-assets",
      },
      encoding: "utf8",
    },
  );
  return { result, directory: join(directory, "landing") };
}

for (const mode of ["production", "staging"]) {
  test(`direct ${mode} deployment overrides an inherited opposite build mode`, async (t) => {
    const { result, directory } = await deployFixture(t, mode);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(await readFile(join(directory, "built-mode"), "utf8"), mode);
    const commands = (
      await readFile(join(directory, "provider-commands"), "utf8")
    )
      .trim()
      .split("\n")
      .map(JSON.parse);
    assert.ok(
      commands.every((command) => command.assetsDirectory === "../dist"),
      "Native provider commands must package the directory that passed verification",
    );
    assert.deepEqual(
      commands.map((command) => command.args),
      [
        ["--dir", "hosting", "exec", "cf", "build", "--mode", mode],
        [
          "--dir",
          "hosting",
          "exec",
          "cf",
          "deploy",
          "--prebuilt",
          "--mode",
          mode,
        ],
      ],
    );
  });

  test(`direct ${mode} deployment stops before provider commands when purchase pages belong to the other environment`, async (t) => {
    const { result, directory } = await deployFixture(t, mode, true);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /purchase.*environment/i);
    await assert.rejects(readFile(join(directory, "provider-commands")), {
      code: "ENOENT",
    });
  });
}
