#!/usr/bin/env node
// Curfew one-shot infrastructure setup — Cloudflare + Stripe.
//
// Automates the bulk of `scripts/release-checklist.md`: deploys the license
// Worker (auto-provisioning its custom domain), generates the signing keypair
// and uploads it, creates the Stripe product/prices/payment-links/webhook and
// wires the secrets, injects the live values into the repo, and deploys the
// landing + /docs proxy. Idempotent: safe to re-run.
//
// What it CANNOT do (no API): the Mintlify dashboard (connect repo + set the
// /docs subpath) and Stripe "Managed Payments" account enablement.
//
// Usage:
//   STRIPE_API_KEY=sk_test_… node scripts/setup.mjs            # dry run (prints the plan)
//   STRIPE_API_KEY=sk_test_… node scripts/setup.mjs --yes      # execute (test mode)
//   STRIPE_API_KEY=sk_live_… node scripts/setup.mjs --yes --live
//
// Env:
//   STRIPE_API_KEY            required (sk_test_… or sk_live_…)
//   STRIPE_LIFETIME_AMOUNT    cents for the one-time price (default 2000 = $20)
//   STRIPE_SUB_AMOUNT         cents for the recurring price (omit to skip the sub SKU)
//   STRIPE_SUB_INTERVAL       'year' | 'month' (default 'year')
//   CLOUDFLARE_API_TOKEN      optional; needed to attach the Pages custom domain
//   CLOUDFLARE_ACCOUNT_ID     optional; auto-detected from `wrangler whoami`
//   SKIP_WORKER / SKIP_KEYPAIR / SKIP_STRIPE / SKIP_PAGES = 1 to skip a phase
//   RECREATE_WEBHOOK=1        delete + recreate the Stripe webhook (to re-read its secret)

import { execFileSync } from "node:child_process";
import { generateKeyPairSync } from "node:crypto";
import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const WORKER_DIR = join(ROOT, "web", "worker");
const LANDING_DIR = join(ROOT, "web", "landing");

const WORKER_DOMAIN = "curfew-license.hypertext.studio";
const LANDING_DOMAIN = "curfew.hypertext.studio";
const PAGES_PROJECT = "curfew-landing";
const WEBHOOK_URL = `https://${WORKER_DOMAIN}/`;
const SUCCESS_URL = `https://${LANDING_DOMAIN}/success.html?session_id={CHECKOUT_SESSION_ID}`;
const EXPECTED_ACCOUNT = "willie@hypertext.studio";

const ARGS = new Set(process.argv.slice(2));
const EXECUTE = ARGS.has("--yes");
const ALLOW_LIVE = ARGS.has("--live");
const env = process.env;

const STRIPE_KEY = env.STRIPE_API_KEY || "";
const LIFETIME_AMOUNT = Number(env.STRIPE_LIFETIME_AMOUNT || 2000);
const SUB_AMOUNT = env.STRIPE_SUB_AMOUNT ? Number(env.STRIPE_SUB_AMOUNT) : null;
const SUB_INTERVAL = env.STRIPE_SUB_INTERVAL || "year";

const C = { dim: "\x1b[2m", red: "\x1b[31m", grn: "\x1b[32m", ylw: "\x1b[33m", rst: "\x1b[0m" };
const log = (m) => console.log(m);
const step = (m) => console.log(`\n${C.grn}▸ ${m}${C.rst}`);
const warn = (m) => console.log(`${C.ylw}! ${m}${C.rst}`);
const die = (m) => { console.error(`${C.red}✘ ${m}${C.rst}`); process.exit(1); };

// --- shell + API helpers ------------------------------------------------------

function wrangler(args, opts = {}) {
  return execFileSync("pnpm", ["exec", "wrangler", ...args], {
    cwd: WORKER_DIR, encoding: "utf8", stdio: opts.capture ? "pipe" : "inherit", input: opts.input,
  });
}

async function stripe(method, path, params) {
  const body = params instanceof URLSearchParams ? params.toString() : undefined;
  const res = await fetch(`https://api.stripe.com/v1${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${STRIPE_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body,
  });
  const json = await res.json();
  if (!res.ok) throw new Error(`Stripe ${method} ${path}: ${json.error?.message || res.status}`);
  return json;
}

async function cloudflare(method, path, body) {
  const token = env.CLOUDFLARE_API_TOKEN;
  const account = env.CLOUDFLARE_ACCOUNT_ID || detectAccountId();
  if (!token) return { skipped: true, account };
  const res = await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}${path}`, {
    method,
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  return res.json();
}

let _accountId;
function detectAccountId() {
  if (_accountId) return _accountId;
  try {
    const out = wrangler(["whoami"], { capture: true });
    _accountId = (out.match(/\b[0-9a-f]{32}\b/) || [])[0];
  } catch { /* ignore */ }
  return _accountId;
}

// --- preflight ----------------------------------------------------------------

function preflight() {
  step("Preflight");
  if (!STRIPE_KEY) die("STRIPE_API_KEY is required (sk_test_… or sk_live_…).");
  const mode = STRIPE_KEY.startsWith("sk_live_") ? "LIVE" : STRIPE_KEY.startsWith("sk_test_") ? "TEST" : "UNKNOWN";
  if (mode === "UNKNOWN") die("STRIPE_API_KEY must start with sk_test_ or sk_live_.");
  if (mode === "LIVE" && !ALLOW_LIVE) die("Refusing LIVE Stripe key without --live. Re-run with --yes --live to confirm.");
  log(`Stripe mode: ${mode === "LIVE" ? C.red + "LIVE" + C.rst : C.grn + "TEST" + C.rst}`);

  const who = wrangler(["whoami"], { capture: true });
  if (!who.includes(EXPECTED_ACCOUNT) && !who.includes("Hypertext Studio")) {
    die(`Wrong Cloudflare account. Expected ${EXPECTED_ACCOUNT}; run \`wrangler login\` first.\n${who}`);
  }
  log(`Cloudflare account: ${C.grn}Hypertext Studio${C.rst} (${detectAccountId() || "?"})`);

  log(`\nPlan:`);
  log(`  1. Deploy Worker → ${WORKER_DOMAIN} (custom domain auto-provisioned)`);
  log(`  2. Generate Ed25519 keypair → secret LICENSE_PRIVATE_KEY + public key into LicenseGate.swift`);
  log(`  3. Stripe: product + lifetime price ($${(LIFETIME_AMOUNT / 100).toFixed(2)})` +
      (SUB_AMOUNT ? ` + subscription ($${(SUB_AMOUNT / 100).toFixed(2)}/${SUB_INTERVAL})` : " (no sub — STRIPE_SUB_AMOUNT unset)") +
      ` + payment links + webhook → secret STRIPE_WEBHOOK_SECRET`);
  log(`  4. Deploy landing + /docs proxy → ${PAGES_PROJECT}` +
      (env.CLOUDFLARE_API_TOKEN ? ` + attach ${LANDING_DOMAIN}` : ` (Pages domain attach skipped — no CLOUDFLARE_API_TOKEN)`));

  if (!EXECUTE) {
    warn("\nDry run. Re-run with --yes to execute.");
    process.exit(0);
  }
}

// --- phases -------------------------------------------------------------------

function phaseWorker() {
  if (env.SKIP_WORKER) return warn("Skipping Worker deploy (SKIP_WORKER).");
  step("Deploy Worker");
  wrangler(["deploy"]);
  log(`Worker deployed; webhook target ${WEBHOOK_URL}`);
}

function phaseKeypair() {
  if (env.SKIP_KEYPAIR) return warn("Skipping keypair (SKIP_KEYPAIR).");
  step("Signing keypair");
  // Match scripts/gen-license-keypair.sh: raw 32-byte seed (base64url) for the
  // Worker secret, raw 32-byte public (standard base64) for LicenseGate.swift.
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const seed = privateKey.export({ type: "pkcs8", format: "der" }).subarray(-32);
  const rawPub = publicKey.export({ type: "spki", format: "der" }).subarray(-32);
  const privB64url = seed.toString("base64url");
  const pubB64std = rawPub.toString("base64");

  wrangler(["secret", "put", "LICENSE_PRIVATE_KEY"], { input: privB64url });
  const gatePath = join(ROOT, "Curfew/Core/Features/LicenseGate.swift");
  const gate = readFileSync(gatePath, "utf8");
  const next = gate.replace(/licensePublicKeyBase64 = "[^"]*"/, `licensePublicKeyBase64 = "${pubB64std}"`);
  if (next === gate) warn("Could not find licensePublicKeyBase64 to update — check LicenseGate.swift.");
  else { writeFileSync(gatePath, next); log(`Set LICENSE_PRIVATE_KEY secret; embedded public key ${pubB64std.slice(0, 12)}…`); }
}

async function phaseStripe() {
  if (env.SKIP_STRIPE) return warn("Skipping Stripe (SKIP_STRIPE).");
  step("Stripe");

  // Product (idempotent by metadata).
  const products = await stripe("GET", "/products?limit=100");
  let product = products.data.find((p) => p.metadata?.curfew === "plus");
  if (!product) {
    const p = new URLSearchParams();
    p.append("name", "Curfew Plus");
    p.append("metadata[curfew]", "plus");
    product = await stripe("POST", "/products", p);
    log(`Created product ${product.id}`);
  } else log(`Reusing product ${product.id}`);

  // These three lookups are independent — fetch them together.
  const [pricesRes, linksRes, hooksRes] = await Promise.all([
    stripe("GET", `/prices?product=${product.id}&limit=100`),
    stripe("GET", "/payment_links?limit=100"),
    stripe("GET", "/webhook_endpoints?limit=100"),
  ]);
  const prices = pricesRes.data;
  const links = linksRes.data;

  async function ensurePrice(match, build) {
    let price = prices.find(match);
    if (!price) { price = await stripe("POST", "/prices", build()); log(`Created price ${price.id}`); }
    else log(`Reusing price ${price.id}`);
    return price;
  }
  async function ensureLink(sku, priceId) {
    let link = links.find((l) => l.metadata?.curfew_sku === sku);
    if (!link) {
      const p = new URLSearchParams();
      p.append("line_items[0][price]", priceId);
      p.append("line_items[0][quantity]", "1");
      p.append("after_completion[type]", "redirect");
      p.append("after_completion[redirect][url]", SUCCESS_URL);
      p.append("metadata[curfew_sku]", sku);
      link = await stripe("POST", "/payment_links", p);
      log(`Created payment link (${sku}) ${link.url}`);
    } else log(`Reusing payment link (${sku}) ${link.url}`);
    return link;
  }

  const lifetimePrice = await ensurePrice(
    (p) => !p.recurring && p.unit_amount === LIFETIME_AMOUNT && p.currency === "usd",
    () => { const p = new URLSearchParams(); p.append("product", product.id); p.append("unit_amount", String(LIFETIME_AMOUNT)); p.append("currency", "usd"); return p; }
  );
  const lifetimeLink = await ensureLink("lifetime", lifetimePrice.id);

  let subLink = null;
  if (SUB_AMOUNT) {
    const subPrice = await ensurePrice(
      (p) => p.recurring?.interval === SUB_INTERVAL && p.unit_amount === SUB_AMOUNT && p.currency === "usd",
      () => { const p = new URLSearchParams(); p.append("product", product.id); p.append("unit_amount", String(SUB_AMOUNT)); p.append("currency", "usd"); p.append("recurring[interval]", SUB_INTERVAL); return p; }
    );
    subLink = await ensureLink("subscription", subPrice.id);
  } else warn("STRIPE_SUB_AMOUNT unset — skipping subscription price/link.");

  // Fill the landing page by replacing stable placeholder tokens (not copy
  // strings, which drift when the marketing copy is reworded). Each replacement
  // must hit — otherwise we throw rather than silently shipping a placeholder.
  const indexPath = join(LANDING_DIR, "index.html");
  let html = readFileSync(indexPath, "utf8");
  const inject = (token, value) => {
    if (!html.includes(token)) throw new Error(`Placeholder "${token}" not found in index.html — was it renamed?`);
    html = html.split(token).join(value);
  };
  inject("https://buy.stripe.com/REPLACE_WITH_CURFEW_PLUS_LIFETIME_LINK", lifetimeLink.url);
  if (subLink) {
    const each = SUB_INTERVAL === "year" ? "year" : "mo";
    inject("https://buy.stripe.com/REPLACE_WITH_CURFEW_PLUS_SUBSCRIPTION_LINK", subLink.url);
    inject("REPLACE_WITH_CURFEW_PLUS_SUB_PRICE", `$${(SUB_AMOUNT / 100).toFixed(0)} / ${each}`);
  }
  writeFileSync(indexPath, html);
  log("Injected payment links into web/web/landing/index.html");

  // Webhook endpoint (its signing secret is only returned on creation).
  const hooks = hooksRes.data;
  let hook = hooks.find((h) => h.url === WEBHOOK_URL);
  if (hook && env.RECREATE_WEBHOOK) { await stripe("DELETE", `/webhook_endpoints/${hook.id}`); hook = null; log("Deleted existing webhook to recreate."); }
  if (!hook) {
    const p = new URLSearchParams();
    p.append("url", WEBHOOK_URL);
    for (const e of ["checkout.session.completed", "invoice.paid", "customer.subscription.deleted"]) p.append("enabled_events[]", e);
    hook = await stripe("POST", "/webhook_endpoints", p);
    wrangler(["secret", "put", "STRIPE_WEBHOOK_SECRET"], { input: hook.secret });
    log(`Created webhook ${hook.id}; set STRIPE_WEBHOOK_SECRET`);
  } else warn(`Webhook ${hook.id} already exists; its secret can't be re-read. Re-run with RECREATE_WEBHOOK=1 to rotate.`);
}

async function phasePages() {
  if (env.SKIP_PAGES) return warn("Skipping landing deploy (SKIP_PAGES).");
  step("Deploy landing + /docs proxy");
  wrangler(["pages", "deploy", LANDING_DIR, "--project-name", PAGES_PROJECT]);

  const res = await cloudflare("POST", `/pages/projects/${PAGES_PROJECT}/domains`, { name: LANDING_DOMAIN });
  if (res.skipped) {
    warn(`Set CLOUDFLARE_API_TOKEN to auto-attach ${LANDING_DOMAIN}. Manual:`);
    log(`  curl -X POST https://api.cloudflare.com/client/v4/accounts/${res.account || "<acct>"}/pages/projects/${PAGES_PROJECT}/domains \\`);
    log(`    -H "Authorization: Bearer <token>" -H "Content-Type: application/json" -d '{"name":"${LANDING_DOMAIN}"}'`);
  } else if (res.success) log(`Attached custom domain ${LANDING_DOMAIN}`);
  else warn(`Pages domain attach: ${JSON.stringify(res.errors || res)}`);
}

// --- run ----------------------------------------------------------------------

(async () => {
  preflight();
  try {
    phaseWorker();
    phaseKeypair();
    await phaseStripe();
    await phasePages();
  } catch (e) {
    die(e.message);
  }

  step("Done");
  log("Remaining manual steps (no API):");
  log("  • Mintlify dashboard → connect the GitHub repo and set the /docs subpath on " + LANDING_DOMAIN);
  log("  • Stripe → enable Managed Payments (account-level eligibility)");
  log("  • Commit the injected changes (LicenseGate.swift public key, web/web/landing/index.html links)");
})();
