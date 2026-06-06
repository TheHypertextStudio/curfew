/**
 * Cloudflare Worker: Stripe Checkout webhook → signed Curfew Pro license key.
 *
 * Deploy:
 *   wrangler deploy scripts/issue-license.ts
 *
 * Required secrets (wrangler secret put <NAME>):
 *   STRIPE_WEBHOOK_SECRET  — from Stripe → Developers → Webhooks → signing
 *                            secret (the `whsec_…` value for this endpoint).
 *   LICENSE_PRIVATE_KEY    — base64url-encoded Ed25519 private key (gen-license-keypair.sh)
 *
 * Required KV binding (wrangler.toml [[kv_namespaces]]):
 *   LICENSE_KV             — stores per-event idempotency records and the
 *                            signed key keyed by Checkout Session id. A
 *                            replayed webhook returns the original license
 *                            instead of minting a second signed key for the
 *                            same purchase, and the GET route reads the key
 *                            back out for the success page.
 *
 * Routes (one Worker, two methods):
 *   POST /              — Stripe webhook. Verifies the `Stripe-Signature`
 *                         header, acts only on `checkout.session.completed`,
 *                         signs a license payload, and stores it.
 *   GET  /license?session_id=<id>
 *                       — success-page delivery. Returns {license_key} for the
 *                         Checkout Session id, or 404 if not yet issued.
 *
 * Delivery:
 *   Stripe runs as Managed Payments (merchant of record) and emails its own
 *   payment receipt — this Worker does NOT send email. The custom Curfew Pro
 *   LICENSE KEY is delivered out-of-band: the Checkout `success_url` points at
 *   the landing success page, which calls `GET /license?session_id=...`
 *   (the session id is interpolated by Stripe into the success URL) and shows
 *   the returned key to the buyer. The landing success page is built by the
 *   landing agent.
 *
 * The webhook verifies the Stripe signature, extracts the customer email and
 * Checkout Session id, signs a license payload, and stores the signed key.
 */

export interface Env {
  STRIPE_WEBHOOK_SECRET: string;
  LICENSE_PRIVATE_KEY: string;
  /**
   * Optional in local dev, required in production. When present, the worker
   * dedupes by Stripe event id and stores the signed key under
   * `session:<id>` for the GET delivery route. When absent, it logs a
   * warning and still issues the key (useful for first-time-deploy smoke
   * tests), but the GET route then has nothing to return.
   */
  LICENSE_KV?: KVNamespace;
}

/** Reject webhooks whose signed timestamp is older than this (replay guard). */
const SIGNATURE_TOLERANCE_SECONDS = 5 * 60;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // GET /license?session_id=<id> — success-page delivery.
    if (request.method === "GET") {
      return handleLicenseLookup(url, env);
    }

    // CORS preflight for the success page's fetch.
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    // POST / — Stripe webhook.
    if (request.method === "POST") {
      return handleWebhook(request, env);
    }

    return new Response("Method not allowed", { status: 405 });
  },
};

// --- Webhook route (POST) ---

async function handleWebhook(request: Request, env: Env): Promise<Response> {
  // The RAW body text is used for BOTH the signature check and the JSON
  // parse — re-stringifying would change byte-for-byte content and break
  // verification.
  const body = await request.text();

  const signature = request.headers.get("Stripe-Signature");
  if (!signature || !(await verifyStripeSignature(body, signature, env.STRIPE_WEBHOOK_SECRET))) {
    return new Response("Invalid signature", { status: 400 });
  }

  const event = JSON.parse(body);
  if (event.type !== "checkout.session.completed") {
    return new Response("ignored", { status: 200 });
  }

  const session = event.data?.object ?? {};
  const sessionID: string = String(session.id ?? "");
  const email: string = session.customer_details?.email ?? session.customer_email ?? "";

  // Only mint for sessions that actually paid. Checkout marks paid sessions
  // with payment_status "paid"; "complete" status covers zero-amount / fully
  // discounted sessions that still finalize.
  const paid = session.payment_status === "paid" || session.status === "complete";
  if (!paid) {
    return new Response("not paid", { status: 200 });
  }

  if (!email || !sessionID) {
    return new Response("Missing session data", { status: 400 });
  }

  // Idempotency: Stripe retries webhooks on non-2xx responses, and a captured
  // body could be replayed. Dedupe on the Stripe EVENT id so a redelivered
  // event is a no-op rather than minting a second key with a fresh issued_at.
  const eventID: string = String(event.id ?? "");
  if (env.LICENSE_KV) {
    if (eventID) {
      const seen = await env.LICENSE_KV.get(`event:${eventID}`);
      if (seen) {
        console.log(`Replay hit for event ${eventID}; no-op`);
        return new Response("ok", { status: 200 });
      }
    }
  } else {
    console.warn("LICENSE_KV binding missing; proceeding without idempotency");
  }

  const licenseKey = await signLicenseKey(email, sessionID, env.LICENSE_PRIVATE_KEY);
  console.log(`Issued license for ${email}, session ${sessionID}`);

  if (env.LICENSE_KV) {
    // Licenses are durable — Ed25519 signatures do not expire — so both the
    // event-dedupe marker and the session→key record are durable. The GET
    // route reads `session:<id>` back out for the buyer's success page.
    if (eventID) {
      await env.LICENSE_KV.put(`event:${eventID}`, "1");
    }
    await env.LICENSE_KV.put(`session:${sessionID}`, licenseKey);
  }

  return new Response("ok", { status: 200 });
}

// --- License lookup route (GET /license?session_id=<id>) ---

async function handleLicenseLookup(url: URL, env: Env): Promise<Response> {
  if (url.pathname !== "/license") {
    return new Response("Not found", { status: 404, headers: corsHeaders() });
  }

  const sessionID = url.searchParams.get("session_id");
  if (!sessionID) {
    return new Response(JSON.stringify({ error: "session_id required" }), {
      status: 400,
      headers: { "Content-Type": "application/json", ...corsHeaders() },
    });
  }

  // The key is only retrievable by knowing the exact Checkout Session id,
  // which Stripe places in the buyer's own success URL — so a wildcard CORS
  // origin is safe here.
  const licenseKey = env.LICENSE_KV ? await env.LICENSE_KV.get(`session:${sessionID}`) : null;
  if (!licenseKey) {
    return new Response(JSON.stringify({ error: "not found" }), {
      status: 404,
      headers: { "Content-Type": "application/json", ...corsHeaders() },
    });
  }

  return new Response(JSON.stringify({ license_key: licenseKey }), {
    status: 200,
    headers: { "Content-Type": "application/json", ...corsHeaders() },
  });
}

function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
  };
}

// --- Signing ---

async function signLicenseKey(
  email: string,
  orderID: string,
  privateKeyBase64url: string
): Promise<string> {
  const payload = {
    email,
    // Must match the `product` check in LicenseGate.swift — any drift here
    // silently rejects every license the worker mints.
    product: "curfew-pro",
    order_id: orderID,
    issued_at: new Date().toISOString(),
  };

  const payloadJSON = JSON.stringify(payload);
  const payloadB64 = base64url(new TextEncoder().encode(payloadJSON));

  const privateKeyBytes = base64urlDecode(privateKeyBase64url);
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    privateKeyBytes,
    { name: "Ed25519" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "Ed25519",
    cryptoKey,
    new TextEncoder().encode(payloadB64)
  );

  const sigB64 = base64url(new Uint8Array(signature));
  return `${payloadB64}.${sigB64}`;
}

// --- Webhook verification (Stripe) ---

/**
 * Verifies a Stripe `Stripe-Signature` header.
 *
 * The header has the form `t=<timestamp>,v1=<sig>[,v1=<sig2>...]`. The signed
 * payload is `${t}.${rawBody}`; the expected signature is the hex-encoded
 * HMAC-SHA256 of that string under the endpoint signing secret. The signature
 * is valid when ANY `v1` scheme value matches (constant-time) and the
 * timestamp is within `SIGNATURE_TOLERANCE_SECONDS` of now (replay guard).
 */
async function verifyStripeSignature(
  body: string,
  header: string,
  secret: string
): Promise<boolean> {
  let timestamp = "";
  const signatures: string[] = [];
  for (const part of header.split(",")) {
    const eq = part.indexOf("=");
    if (eq === -1) {
      continue;
    }
    const key = part.slice(0, eq).trim();
    const value = part.slice(eq + 1).trim();
    if (key === "t") {
      timestamp = value;
    } else if (key === "v1") {
      signatures.push(value);
    }
  }

  if (!timestamp || signatures.length === 0) {
    return false;
  }

  // Replay protection: reject events whose signed timestamp is too old (or
  // implausibly far in the future). Stripe timestamps are seconds since epoch.
  const timestampSeconds = Number(timestamp);
  if (!Number.isFinite(timestampSeconds)) {
    return false;
  }
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSeconds - timestampSeconds) > SIGNATURE_TOLERANCE_SECONDS) {
    return false;
  }

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const expectedBytes = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${timestamp}.${body}`)
  );
  const expectedHex = hexEncode(new Uint8Array(expectedBytes));

  // Constant-time compare against every offered v1 signature.
  let matched = false;
  for (const candidate of signatures) {
    if (constantTimeEqual(candidate, expectedHex)) {
      matched = true;
    }
  }
  return matched;
}

// --- Base64url helpers ---

function base64url(bytes: Uint8Array): string {
  const b64 = btoa(String.fromCharCode(...bytes));
  return b64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlDecode(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64 + "=".repeat((4 - (b64.length % 4)) % 4);
  const bin = atob(padded);
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

function hexEncode(bytes: Uint8Array): string {
  let out = "";
  for (const b of bytes) {
    out += b.toString(16).padStart(2, "0");
  }
  return out;
}

/**
 * Length-independent constant-time string comparison. Returns false for any
 * length mismatch and otherwise XOR-accumulates every char code so timing
 * does not leak how many leading characters matched.
 */
function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) {
    return false;
  }
  let diff = 0;
  for (let i = 0; i < a.length; i += 1) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}
