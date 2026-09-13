import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { promisify } from "node:util";

import { afterEach, describe, expect, it } from "vitest";

import { DEVELOPMENT_PUBLIC_KEY } from "../scripts/manifest.mjs";
import {
  TEST_PRODUCTION_IDENTITY,
  TEST_PRODUCTION_PUBLIC_KEY,
} from "./production-identity";

const run = promisify(execFile);
const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(temporaryDirectories.splice(0).map((directory) =>
    rm(directory, { recursive: true, force: true })));
});

async function build(
  flavor: "development" | "draft" | "production",
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
      key?: string;
      name: string;
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
    const output = await build("production", TEST_PRODUCTION_IDENTITY);

    expect(output.manifest.key).toBe(TEST_PRODUCTION_PUBLIC_KEY);
    expect(output.background).toContain("studio.hypertext.curfew.browser");
    expect(output.background).not.toContain("studio.hypertext.curfew.dev.browser");
  });

  it("builds a keyless first-upload draft against the production native host", async () => {
    const output = await build("draft");

    expect(output.manifest.name).toBe("Curfew Browser");
    expect(output.manifest.key).toBeUndefined();
    expect(output.background).toContain("studio.hypertext.curfew.browser");
    expect(output.background).not.toContain("studio.hypertext.curfew.dev.browser");
    expect(output.blockerScript).not.toContain("Complete LVBT social strategy");
  });

  it("packages the blocker as an extension-local justification form", async () => {
    const output = await build("production", TEST_PRODUCTION_IDENTITY);

    expect(output.blocker).toContain('<form id="review-form"');
    expect(output.blocker).toContain('id="justification"');
    expect(output.blocker.match(/<textarea/g)).toHaveLength(1);
    expect(output.blocker).not.toContain("challenge-answer");
    expect(output.blocker).not.toContain("http://");
    expect(output.blocker).not.toContain("https://");
  });

  it("builds one focused access request without self-narrating chrome", async () => {
    const output = await build("production", TEST_PRODUCTION_IDENTITY);

    expect(output.blocker).toContain('src="icons/icon-32.png"');
    expect(output.blocker).toContain('<h1 class="task" id="task-title"');
    expect(output.blocker).toContain('id="target-host"');
    expect(output.blocker).toContain('id="question"');
    expect(output.blocker).toContain('id="justification"');
    expect(output.blocker).toContain(">Request access</button>");

    for (const narration of [
      "DESTINATION HELD",
      "ACTIVE TASK",
      "Stop. Name the work.",
      "Your plan and deliverable",
      "Unknown destinations stay blocked",
    ]) {
      expect(output.blocker).not.toContain(narration);
    }
  });

  it("removes the screenshot fixture from production blocker code", async () => {
    const development = await build("development");
    const production = await build("production", TEST_PRODUCTION_IDENTITY);

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
