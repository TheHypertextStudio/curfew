import { mkdir, writeFile, copyFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

import { build } from "esbuild";

import { buildManifest } from "./manifest.mjs";

const packageDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const flavor = process.argv[2];
if (flavor !== "development" && flavor !== "draft" && flavor !== "production") {
  throw new Error("Build flavor must be development, draft, or production");
}
const outputArgument = process.argv.indexOf("--outdir");
const outputDirectory = outputArgument === -1
  ? resolve(packageDirectory, "dist", flavor)
  : resolve(process.argv[outputArgument + 1]);
const hostName = flavor === "development"
  ? "studio.hypertext.curfew.dev.browser"
  : "studio.hypertext.curfew.browser";
const manifest = buildManifest(flavor, {
  productionPublicKey: process.env.CURFEW_BROWSER_EXTENSION_PUBLIC_KEY,
  productionExtensionID: process.env.CURFEW_BROWSER_EXTENSION_ID,
});

await mkdir(outputDirectory, { recursive: true });
await mkdir(resolve(outputDirectory, "icons"), { recursive: true });
await Promise.all([
  build({
    entryPoints: [resolve(packageDirectory, "src/background.ts")],
    outfile: resolve(outputDirectory, "background.js"),
    bundle: true,
    define: { __CURFEW_NATIVE_HOST__: JSON.stringify(hostName) },
    format: "esm",
    minify: flavor !== "development",
    platform: "browser",
    target: "chrome120",
  }),
  build({
    entryPoints: [resolve(packageDirectory, "src/blocker.ts")],
    outfile: resolve(outputDirectory, "blocker.js"),
    bundle: true,
    define: { __CURFEW_BLOCKER_DEMO__: String(flavor === "development") },
    format: "esm",
    minify: flavor !== "development",
    platform: "browser",
    target: "chrome120",
  }),
  copyFile(resolve(packageDirectory, "blocker.html"), resolve(outputDirectory, "blocker.html")),
  copyFile(resolve(packageDirectory, "blocker.css"), resolve(outputDirectory, "blocker.css")),
  ...[16, 32, 48, 128].map((size) => copyFile(
    resolve(packageDirectory, `icons/icon-${size}.png`),
    resolve(outputDirectory, `icons/icon-${size}.png`),
  )),
  writeFile(
    resolve(outputDirectory, "manifest.json"),
    `${JSON.stringify(manifest, null, 2)}\n`,
  ),
]);
