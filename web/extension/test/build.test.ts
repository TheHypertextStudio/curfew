import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
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

afterEach(async () => {
  await Promise.all(temporaryDirectories.splice(0).map((directory) =>
    rm(directory, { recursive: true, force: true })));
});

const productionIdentity = {
  CURFEW_BROWSER_EXTENSION_PUBLIC_KEY: DEVELOPMENT_PUBLIC_KEY,
  CURFEW_BROWSER_EXTENSION_ID: DEVELOPMENT_EXTENSION_ID,
};

async function build(
  flavor: "development" | "production",
  environment: NodeJS.ProcessEnv = {},
) {
  const output = await mkdtemp(resolve(tmpdir(), `curfew-extension-${flavor}-`));
  temporaryDirectories.push(output);
  await run(
    process.execPath,
    [resolve("scripts/build.mjs"), flavor, "--outdir", output],
    { env: { ...process.env, ...environment } },
  );
  return {
    background: await readFile(resolve(output, "background.js"), "utf8"),
    blocker: await readFile(resolve(output, "blocker.html"), "utf8"),
    blockerScript: await readFile(resolve(output, "blocker.js"), "utf8"),
    manifest: JSON.parse(await readFile(resolve(output, "manifest.json"), "utf8")) as {
      key: string;
      homepage_url: string;
      icons: Record<string, string>;
    },
    output,
  };
}

describe("extension build", () => {
  it("pins the development identity and development native host", async () => {
    const output = await build("development");

    expect(output.manifest.key).toBe(DEVELOPMENT_PUBLIC_KEY);
    expect(output.background).toContain("studio.hypertext.curfew.dev.browser");
    expect(output.background).not.toContain('"studio.hypertext.curfew.browser"');
  });

  it("uses the explicit production identity and only the production native host", async () => {
    const output = await build("production", productionIdentity);

    expect(output.manifest.key).toBe(DEVELOPMENT_PUBLIC_KEY);
    expect(output.background).toContain("studio.hypertext.curfew.browser");
    expect(output.background).not.toContain("studio.hypertext.curfew.dev.browser");
  });

  it("packages the blocker as an extension-local justification form", async () => {
    const output = await build("production", productionIdentity);

    expect(output.blocker).toContain('<form id="review-form"');
    expect(output.blocker).toContain('id="justification"');
    expect(output.blocker.match(/<textarea/g)).toHaveLength(1);
    expect(output.blocker).not.toContain("challenge-answer");
    expect(output.blocker).not.toContain("http://");
    expect(output.blocker).not.toContain("https://");
  });

  it("removes the screenshot fixture from production blocker code", async () => {
    const development = await build("development");
    const production = await build("production", productionIdentity);

    expect(development.blockerScript).toContain("Complete LVBT social strategy");
    expect(production.blockerScript).not.toContain("Complete LVBT social strategy");
  });

  it("fails production builds when the release identity is absent", async () => {
    await expect(build("production")).rejects.toThrow(/production public key.*extension ID/i);
  });

  it("copies the complete Chrome icon package", async () => {
    const output = await build("development");

    expect(output.manifest.homepage_url).toBe("https://curfew.hypertext.studio");
    for (const size of [16, 32, 48, 128]) {
      const icon = await readFile(resolve(output.output, `icons/icon-${size}.png`));
      expect(icon.subarray(1, 4).toString()).toBe("PNG");
      expect(icon.readUInt32BE(16)).toBe(size);
      expect(icon.readUInt32BE(20)).toBe(size);
    }
  });
});
