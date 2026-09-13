import { execFile } from "node:child_process";
import { mkdtemp, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import { resolve } from "node:path";
import { promisify } from "node:util";

import { PNG } from "pngjs";
import { afterEach, describe, expect, it } from "vitest";

const run = promisify(execFile);
const temporaryDirectories: string[] = [];

afterEach(async () => {
  await Promise.all(temporaryDirectories.splice(0).map((directory) =>
    rm(directory, { recursive: true, force: true })));
});

describe("extension icons", () => {
  it("stay generated from the Curfew app icon", async () => {
    const output = await mkdtemp(resolve(tmpdir(), "curfew-extension-icons-"));
    temporaryDirectories.push(output);

    await run(
      "/usr/bin/swift",
      [resolve("../../scripts/generate-extension-icons.swift"), output],
    );

    for (const size of [16, 32, 48, 128]) {
      const generated = resolve(output, `icon-${size}.png`);
      const committed = resolve(`icons/icon-${size}.png`);
      const generatedBytes = await readFile(generated);
      const image = PNG.sync.read(generatedBytes);
      const visiblePixels: Array<{ x: number; y: number }> = [];

      for (let y = 0; y < image.height; y += 1) {
        for (let x = 0; x < image.width; x += 1) {
          if (image.data[(y * image.width + x) * 4 + 3] > 0) {
            visiblePixels.push({ x, y });
          }
        }
      }

      expect(visiblePixels.length).toBeGreaterThan(0);
      expect(visiblePixels.length).toBeLessThan(size * size);

      if (size === 128) {
        const xs = visiblePixels.map(({ x }) => x);
        const ys = visiblePixels.map(({ y }) => y);

        expect(Math.min(...xs)).toBeGreaterThanOrEqual(16);
        expect(Math.max(...xs)).toBeLessThanOrEqual(111);
        expect(Math.min(...ys)).toBeGreaterThanOrEqual(16);
        expect(Math.max(...ys)).toBeLessThanOrEqual(111);
      }

      expect(generatedBytes).toEqual(await readFile(committed));
    }
  }, 30_000);
});
