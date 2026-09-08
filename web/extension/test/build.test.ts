import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { promisify } from "node:util";

import { afterEach, describe, expect, it } from "vitest";

import { DEVELOPMENT_PUBLIC_KEY } from "../scripts/manifest.mjs";

const run = promisify(execFile);
const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(temporaryDirectories.splice(0).map((directory) =>
    rm(directory, { recursive: true, force: true })));
});

async function build(flavor: "development" | "production") {
  const output = await mkdtemp(resolve(tmpdir(), `curfew-extension-${flavor}-`));
  temporaryDirectories.push(output);
  await run(process.execPath, [
    resolve("scripts/build.mjs"),
    flavor,
    "--outdir",
    output,
  ]);
  return {
    background: await readFile(resolve(output, "background.js"), "utf8"),
    blocker: await readFile(resolve(output, "blocker.html"), "utf8"),
    blockerScript: await readFile(resolve(output, "blocker.js"), "utf8"),
    manifest: JSON.parse(await readFile(resolve(output, "manifest.json"), "utf8")) as {
      key: string;
    },
  };
}

describe("extension build", () => {
  it("pins the development identity and development native host", async () => {
    const output = await build("development");

    expect(output.manifest.key).toBe(DEVELOPMENT_PUBLIC_KEY);
    expect(output.background).toContain("studio.hypertext.curfew.dev.browser");
    expect(output.background).not.toContain('"studio.hypertext.curfew.browser"');
  });

  it("pins the same production identity and only the production native host", async () => {
    const output = await build("production");

    expect(output.manifest.key).toBe(DEVELOPMENT_PUBLIC_KEY);
    expect(output.background).toContain("studio.hypertext.curfew.browser");
    expect(output.background).not.toContain("studio.hypertext.curfew.dev.browser");
  });

  it("packages the blocker as an extension-local justification form", async () => {
    const output = await build("production");

    expect(output.blocker).toContain('<form id="review-form"');
    expect(output.blocker).toContain('id="justification"');
    expect(output.blocker.match(/<textarea/g)).toHaveLength(1);
    expect(output.blocker).not.toContain("challenge-answer");
    expect(output.blocker).not.toContain("http://");
    expect(output.blocker).not.toContain("https://");
  });

  it("removes the screenshot fixture from production blocker code", async () => {
    const development = await build("development");
    const production = await build("production");

    expect(development.blockerScript).toContain("Complete LVBT social strategy");
    expect(production.blockerScript).not.toContain("Complete LVBT social strategy");
  });
});
