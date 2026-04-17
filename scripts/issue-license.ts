/**
 * Cloudflare Worker: Lemonsqueezy webhook → signed Curfew Pro license key.
 *
 * Deploy:
 *   wrangler deploy scripts/issue-license.ts
 *
 * Required secrets (wrangler secret put <NAME>):
 *   LEMON_WEBHOOK_SECRET   — from Lemonsqueezy → Webhooks → signing secret
 *   LICENSE_PRIVATE_KEY    — base64url-encoded Ed25519 private key (gen-license-keypair.sh)
 *
 * The worker verifies the Lemonsqueezy webhook signature, extracts the
 * customer email and order ID, signs a license payload, and updates the
 * Lemonsqueezy license key meta with the signed key so it's delivered in
 * the purchase receipt email.
 */

export interface Env {
  LEMON_WEBHOOK_SECRET: string;
  LICENSE_PRIVATE_KEY: string;
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method !== "POST") {
      return new Response("Method not allowed", { status: 405 });
    }

    const body = await request.text();

    // Verify Lemonsqueezy webhook signature
    const signature = request.headers.get("X-Signature");
    if (!signature || !(await verifySignature(body, signature, env.LEMON_WEBHOOK_SECRET))) {
      return new Response("Unauthorized", { status: 401 });
    }

    const event = JSON.parse(body);
    if (event.meta?.event_name !== "order_created") {
      return new Response("OK", { status: 200 });
    }

    const email: string = event.data?.attributes?.user_email ?? "";
    const orderID: string = String(event.data?.id ?? "");

    if (!email || !orderID) {
      return new Response("Missing order data", { status: 400 });
    }

    const licenseKey = await signLicenseKey(email, orderID, env.LICENSE_PRIVATE_KEY);
    console.log(`Issued license for ${email}, order ${orderID}: ${licenseKey}`);

    return new Response(JSON.stringify({ license_key: licenseKey }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  },
};

// --- Signing ---

async function signLicenseKey(
  email: string,
  orderID: string,
  privateKeyBase64url: string
): Promise<string> {
  const payload = {
    email,
    product: "curfew",
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

// --- Webhook verification ---

async function verifySignature(body: string, signature: string, secret: string): Promise<boolean> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["verify"]
  );

  const sigBytes = hexDecode(signature);
  return crypto.subtle.verify("HMAC", key, sigBytes, new TextEncoder().encode(body));
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

function hexDecode(hex: string): Uint8Array {
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.slice(i, i + 2), 16);
  }
  return bytes;
}
