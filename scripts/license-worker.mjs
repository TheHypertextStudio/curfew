#!/usr/bin/env node
/**
 * Reproducible, no-secret bootstrap for Curfew's license Worker.
 *
 * This command never logs a private seed and never performs a Cloudflare or
 * Stripe mutation. `dry-run` delegates only to Wrangler's local dry-run mode.
 */
import { generateKeyPairSync } from "node:crypto";
import { access, chmod, mkdir, open, readFile, writeFile } from "node:fs/promises";
import { constants } from "node:fs";
import { dirname, resolve } from "node:path";
import { spawnSync } from "node:child_process";

const root = resolve(import.meta.dirname, "..");
const templatePath = resolve(root, "web/worker/wrangler.toml.example");
const requiredConfig = [
  "CURFEW_LICENSE_WORKER_NAME",
  "CURFEW_LICENSE_KV_NAMESPACE_ID",
  "CURFEW_LICENSE_HOSTNAME",
];

const [command, ...args] = process.argv.slice(2);
try {
  switch (command) {
    case "keygen": await keygen(args); break;
    case "validate-config": validateConfig(); break;
    case "render-config": await renderConfig(args); break;
    case "dry-run": dryRun(args); break;
    case "verify-endpoint": await verifyEndpoint(args); break;
    default: usage();
  }
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
}

async function keygen(arguments_) {
  const privateKeyFile = option(arguments_, "--private-key-file");
  const publicKeyFile = option(arguments_, "--public-key-file");
  if (!privateKeyFile) throw new Error("keygen requires --private-key-file <user-owned-path>");
  await assertAbsent(privateKeyFile);
  if (publicKeyFile) await assertAbsent(publicKeyFile);

  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const privateDer = privateKey.export({ type: "pkcs8", format: "der" });
  const publicDer = publicKey.export({ type: "spki", format: "der" });
  const seed = privateDer.subarray(-32);
  const rawPublicKey = publicDer.subarray(-32);
  if (seed.length !== 32 || rawPublicKey.length !== 32) throw new Error("unexpected Ed25519 key encoding");

  await writePrivate(privateKeyFile, base64url(seed));
  const publicValue = rawPublicKey.toString("base64");
  if (publicKeyFile) await writePublic(publicKeyFile, `${publicValue}\n`);
  // This is the only key material printed: it is intentionally public and is
  // copied into LicenseGate before the signed release is built.
  console.log(`CURFEW_LICENSE_PUBLIC_KEY=${publicValue}`);
}

function validateConfig() {
  const missing = requiredConfig.filter(name => !process.env[name] || process.env[name].includes("__"));
  if (missing.length > 0) throw new Error(`missing required configuration: ${missing.join(", ")}`);
  if (!/^[a-z0-9-]+$/.test(process.env.CURFEW_LICENSE_WORKER_NAME)) throw new Error("CURFEW_LICENSE_WORKER_NAME must be lowercase letters, digits, or hyphens");
  if (!/^[a-f0-9]{32}$/i.test(process.env.CURFEW_LICENSE_KV_NAMESPACE_ID)) throw new Error("CURFEW_LICENSE_KV_NAMESPACE_ID must be a 32-character hexadecimal KV namespace ID");
  if (!/^[a-z0-9.-]+$/i.test(process.env.CURFEW_LICENSE_HOSTNAME)) throw new Error("CURFEW_LICENSE_HOSTNAME must be a hostname without a scheme or path");
  console.log("License Worker configuration is structurally valid.");
}

async function renderConfig(arguments_) {
  validateConfig();
  const output = option(arguments_, "--output");
  if (!output) throw new Error("render-config requires --output <local-path>");
  const template = await readFile(templatePath, "utf8");
  const rendered = template
    .replaceAll("__CURFEW_LICENSE_WORKER_NAME__", process.env.CURFEW_LICENSE_WORKER_NAME)
    .replaceAll("__CURFEW_LICENSE_KV_NAMESPACE_ID__", process.env.CURFEW_LICENSE_KV_NAMESPACE_ID)
    .replaceAll("__CURFEW_LICENSE_HOSTNAME__", process.env.CURFEW_LICENSE_HOSTNAME);
  await writePublic(output, rendered);
  console.log(`Rendered local Worker configuration: ${resolve(output)}`);
}

function dryRun(arguments_) {
  const config = option(arguments_, "--config");
  if (!config) throw new Error("dry-run requires --config <rendered-local-config>");
  const workerDirectory = resolve(root, "web/worker");
  const result = spawnSync("pnpm", ["exec", "wrangler", "deploy", "--dry-run", "--config", resolve(config)], {
    cwd: workerDirectory,
    stdio: "inherit",
  });
  if (result.status !== 0) process.exitCode = result.status ?? 1;
}

async function verifyEndpoint(arguments_) {
  const baseURL = option(arguments_, "--base-url");
  if (!baseURL) throw new Error("verify-endpoint requires --base-url <https-worker-url>");
  const url = new URL("/health", baseURL);
  if (url.protocol !== "https:") throw new Error("verify-endpoint requires an HTTPS URL");
  const response = await fetch(url, { headers: { Accept: "application/json" } });
  if (!response.ok) throw new Error(`health endpoint returned HTTP ${response.status}`);
  const body = await response.json();
  if (body?.status !== "ok" || body?.envelope_version !== 2) throw new Error("health endpoint did not report license envelope v2");
  console.log(`Verified ${url.origin}/health (license envelope v2).`);
}

function option(arguments_, name) {
  const index = arguments_.indexOf(name);
  return index === -1 ? undefined : arguments_[index + 1];
}

async function assertAbsent(path) {
  try {
    await access(path, constants.F_OK);
    throw new Error(`refusing to overwrite existing file: ${resolve(path)}`);
  } catch (error) {
    if (error?.code !== "ENOENT") throw error;
  }
}

async function writePrivate(path, value) {
  await mkdir(dirname(resolve(path)), { recursive: true, mode: 0o700 });
  const handle = await open(path, "wx", 0o600);
  try { await handle.writeFile(value); } finally { await handle.close(); }
  await chmod(path, 0o600);
}

async function writePublic(path, value) {
  await mkdir(dirname(resolve(path)), { recursive: true, mode: 0o700 });
  await writeFile(path, value, { encoding: "utf8", mode: 0o644, flag: "wx" });
}

function base64url(bytes) {
  return bytes.toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function usage() {
  console.error("Usage: license-worker.mjs <keygen|validate-config|render-config|dry-run|verify-endpoint> [options]");
  process.exitCode = 1;
}
