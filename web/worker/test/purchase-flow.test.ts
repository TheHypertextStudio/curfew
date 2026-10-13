import { beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index.js";
import { base64url } from "../src/crypto.js";
import type { Env } from "../src/types.js";
import { indexPurchase } from "../src/purchases.js";

// Only the external storage, email delivery, and edge rate limiter are doubled.
// Requests exercise the real HTTP handler and signed Stripe webhook boundary.
class MemoryKV {
  values = new Map<string, string>();
  async get(key: string) { return this.values.get(key) ?? null; }
  async put(key: string, value: string) { this.values.set(key, value); }
  async delete(key: string) { this.values.delete(key); }
  async list({ prefix = "" } = {}) {
    return { keys: [...this.values.keys()].filter(name => name.startsWith(prefix)).map(name => ({ name })), list_complete: true };
  }
}

describe("purchase activation and recovery", () => {
  let env: Env;
  let kv: MemoryKV;
  let mail: Array<{ to: string; text: string }>;
  let signer: CryptoKey;
  beforeEach(async () => {
    kv = new MemoryKV();
    mail = [];
    const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]) as CryptoKeyPair;
    signer = pair.privateKey;
    const privateKey = new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey));
    env = {
      STRIPE_WEBHOOK_SECRET: "test-webhook-secret",
      LICENSE_PRIVATE_KEY: base64url(privateKey.slice(-32)),
      LICENSE_KV: kv as unknown as KVNamespace,
      EMAIL: { async send(message: EmailMessage | EmailMessageBuilder) {
        if (!("text" in message) || typeof message.to !== "string" || typeof message.text !== "string") throw new Error("Expected plain-text recipient message");
        mail.push({ to: message.to, text: message.text });
        return { messageId: "test" } as EmailSendResult;
      } },
      RESTORE_EMAIL_FROM: "purchases@curfew.hypertext.studio",
      PURCHASE_PORTAL_URL: "https://curfew.hypertext.studio",
      RESTORE_IP_LIMIT: { async limit() { return { success: true }; } },
      RESTORE_EMAIL_LIMIT: { async limit() { return { success: true }; } },
    };
  });

  const post = (path: string, body: unknown) => worker.fetch(new Request(`https://issuer.example${path}`, {
    method: "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2.1" }, body: JSON.stringify(body),
  }), env);

  async function checkout(paymentStatus = "paid", mode = "payment", sku = mode === "subscription" ? "subscription" : "lifetime") {
    return stripeEvent(`evt_${paymentStatus}_${mode}_${sku}`, "checkout.session.completed", {
      id: "cs_test_purchase", mode, status: "complete", payment_status: paymentStatus,
      customer_details: { email: "Buyer@Example.com" }, subscription: mode === "subscription" ? "sub_test" : undefined,
      metadata: { curfew_sku: sku },
    });
  }

  async function stripeEvent(id: string, type: string, object: unknown) {
    const body = JSON.stringify({ id, type, data: { object } });
    const timestamp = Math.floor(Date.now() / 1000);
    const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(env.STRIPE_WEBHOOK_SECRET), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
    const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${timestamp}.${body}`)));
    const hex = [...signature].map(byte => byte.toString(16).padStart(2, "0")).join("");
    return worker.fetch(new Request("https://issuer.example/", { method: "POST", headers: { "Stripe-Signature": `t=${timestamp},v1=${hex}` }, body }), env);
  }

  it("exchanges a paid checkout for a short-lived activation ticket and a signed key", async () => {
    expect((await checkout()).status).toBe(200);
    const response = await post("/license/activation", { session_id: "cs_test_purchase" });
    expect(response.status).toBe(200);
    const activation = await response.json() as { activation_token: string; license_key: string };
    expect(activation.activation_token).toMatch(/^[A-Za-z0-9_-]{43}$/);
    const redeemed = await post("/license/redeem", { token: activation.activation_token });
    expect(redeemed.status).toBe(200);
    expect(await redeemed.json()).toEqual({ license_key: activation.license_key });
    expect(redeemed.headers.get("Cache-Control")).toBe("no-store");
  });

  it("never grants Plus for a completed checkout whose payment is unpaid", async () => {
    await checkout("unpaid");
    expect((await post("/license/activation", { session_id: "cs_test_purchase" })).status).toBe(404);
    expect(await kv.get("session:cs_test_purchase")).toBeNull();
  });

  it("does not redeem unknown, malformed, or expired activation tickets", async () => {
    expect((await post("/license/redeem", { token: "bad" })).status).toBe(400);
    expect((await post("/license/redeem", { token: "a".repeat(43) })).status).toBe(404);
    await checkout();
    const activation = await (await post("/license/activation", { session_id: "cs_test_purchase" })).json() as { activation_token: string };
    for (const [key, value] of kv.values) {
      if (key.startsWith("activation:")) kv.values.set(key, JSON.stringify({ ...JSON.parse(value), expiresAt: 1 }));
    }
    expect((await post("/license/redeem", { token: activation.activation_token })).status).toBe(410);
  });

  it("restores through the purchase inbox without returning a key or revealing purchase existence", async () => {
    await checkout();
    const known = await post("/license/restore", { email: " buyer@example.com " });
    const unknown = await post("/license/restore", { email: "unknown@example.com" });
    expect(known.status).toBe(202);
    expect(await known.json()).toEqual(await unknown.json());
    expect(mail).toHaveLength(2);
    expect(mail[0].to).toBe("buyer@example.com");
    const restoreLink = mail[0].text.match(/https:\/\/\S+/)?.[0];
    expect(restoreLink).toMatch(/^https:\/\/curfew.hypertext.studio\/restore#token=[A-Za-z0-9_-]{43}$/);
    const token = new URLSearchParams(new URL(restoreLink!).hash.slice(1)).get("token");
    const restored = await post("/license/redeem", { token });
    expect(restored.status).toBe(200);
    expect((await restored.json() as { license_key: string }).license_key).toBe(await kv.get("session:cs_test_purchase"));
    expect(mail[0].text).not.toContain((await kv.get("session:cs_test_purchase"))!);
  });

  it("uses the latest subscription key when restoring instead of the checkout's old period", async () => {
    await checkout("paid", "subscription");
    const refreshEntry = [...kv.values.keys()].find(key => key.startsWith("refresh:"))!;
    await stripeEvent("evt_new_period", "invoice.paid", {
      subscription: "sub_test", customer_email: "buyer@example.com",
      lines: { data: [{ period: { end: Math.floor(Date.now() / 1000) + 365 * 86400 } }] },
    });
    const renewed = await kv.get(refreshEntry);
    await post("/license/restore", { email: "buyer@example.com" });
    const token = new URLSearchParams(new URL(mail[0].text.match(/https:\/\/\S+/)![0]).hash.slice(1)).get("token");
    expect(await (await post("/license/redeem", { token })).json()).toEqual({ license_key: renewed });
  });

  it("fails clearly when email delivery is unavailable and rejects abusive or invalid requests", async () => {
    expect((await post("/license/restore", { email: "bad\r\naddress" })).status).toBe(400);
    env.RESTORE_IP_LIMIT = { async limit() { return { success: false }; } };
    expect((await post("/license/restore", { email: "buyer@example.com" })).status).toBe(429);
    expect(mail).toHaveLength(0);
    env.EMAIL = undefined;
    expect((await post("/license/restore", { email: "buyer@example.com" })).status).toBe(503);
  });

  it("backfills a legacy purchase index when Stripe resends its already processed paid checkout", async () => {
    await checkout();
    const original = await kv.get("session:cs_test_purchase");
    for (const key of kv.values.keys()) if (key.startsWith("purchase:")) await kv.delete(key);
    await checkout();
    await post("/license/restore", { email: "buyer@example.com" });
    const token = new URLSearchParams(new URL(mail[0].text.match(/https:\/\/\S+/)![0]).hash.slice(1)).get("token");
    expect((await post("/license/redeem", { token })).status).toBe(200);
    expect(await kv.get("session:cs_test_purchase")).toBe(original);
  });

  it("does not issue a license for another product or a mismatched checkout mode", async () => {
    for (const [mode, sku] of [["payment", "unrelated-product"], ["subscription", "lifetime"], ["setup", "lifetime"]]) {
      await checkout("paid", mode, sku);
      expect(await kv.get("session:cs_test_purchase")).toBeNull();
    }
  });

  it("indexes an already issued legacy Curfew purchase without requiring current metadata", async () => {
    await checkout();
    const original = await kv.get("session:cs_test_purchase");
    for (const key of kv.values.keys()) if (key.startsWith("purchase:")) await kv.delete(key);
    await stripeEvent("evt_paid_payment_lifetime", "checkout.session.completed", {
      id: "cs_test_purchase", mode: "payment", payment_status: "paid",
      customer_details: { email: "buyer@example.com" },
    });
    await post("/license/restore", { email: "buyer@example.com" });
    const token = new URLSearchParams(new URL(mail[0].text.match(/https:\/\/\S+/)![0]).hash.slice(1)).get("token");
    expect(await (await post("/license/redeem", { token })).json()).toEqual({ license_key: original });
  });

  it("preserves UTF-8 inbox addresses when indexing a stored legacy envelope", async () => {
    const email = "buyer@例子.公司";
    await stripeEvent("evt_unicode", "checkout.session.completed", {
      id: "cs_unicode", mode: "payment", payment_status: "paid", customer_details: { email },
      metadata: { curfew_sku: "lifetime" },
    });
    for (const key of kv.values.keys()) if (key.startsWith("purchase:")) await kv.delete(key);
    await stripeEvent("evt_unicode", "checkout.session.completed", {
      id: "cs_unicode", mode: "payment", payment_status: "paid", customer_details: { email },
    });
    await post("/license/restore", { email });
    const token = new URLSearchParams(new URL(mail[0].text.match(/https:\/\/\S+/)![0]).hash.slice(1)).get("token");
    expect((await post("/license/redeem", { token })).status).toBe(200);
  });

  it("restores the latest paid period when concurrent invoices finish out of order", async () => {
    await checkout("paid", "subscription");
    const oldEnd = 3786912000;
    const newEnd = 3818448000;
    const originalPut = kv.put.bind(kv);
    let release: () => void = () => {};
    let started: () => void = () => {};
    const waiting = new Promise<void>(resolve => { started = resolve; });
    const blocked = new Promise<void>(resolve => { release = resolve; });
    kv.put = async (key, value) => {
      if (key.startsWith("refresh:") && JSON.parse(atob(value.split(".")[0].replace(/-/g, "+").replace(/_/g, "/"))).expires_at.startsWith("2090-01-04")) {
        started(); await blocked;
      }
      await originalPut(key, value);
    };
    const invoice = (end: number) => ({ subscription: "sub_test", customer_email: "buyer@example.com",
      lines: { data: [{ period: { end } }] } });
    const older = stripeEvent("evt_concurrent_old", "invoice.paid", invoice(oldEnd));
    await waiting;
    await stripeEvent("evt_concurrent_new", "invoice.paid", invoice(newEnd));
    release(); await older;
    await stripeEvent("evt_concurrent_cancel", "customer.subscription.deleted", { id: "sub_test" });
    const response = await post("/license/activation", { session_id: "cs_test_purchase" });
    const restored = (await response.json() as { license_key: string }).license_key;
    expect(JSON.parse(atob(restored.split(".")[0].replace(/-/g, "+").replace(/_/g, "/"))).expires_at).toBe("2091-01-04T00:00:00Z");
  });

  it("retains an existing legacy renewal when a backfilled subscription is canceled", async () => {
    await checkout("paid", "subscription");
    await kv.delete("subsession:sub_test");
    for (const key of kv.values.keys()) if (key.startsWith("purchase:")) await kv.delete(key);
    await stripeEvent("evt_legacy_renewal", "invoice.paid", {
      subscription: "sub_test", customer_email: "buyer@example.com",
      lines: { data: [{ period: { end: Math.floor(Date.now() / 1000) + 365 * 86400 } }] },
    });
    const renewed = [...kv.values.entries()].find(([key]) => key.startsWith("refresh:"))![1];
    await stripeEvent("evt_paid_subscription_subscription", "checkout.session.completed", {
      id: "cs_test_purchase", mode: "subscription", payment_status: "paid", subscription: "sub_test",
      customer_details: { email: "buyer@example.com" }, metadata: { curfew_sku: "subscription" },
    });
    await stripeEvent("evt_legacy_cancel", "customer.subscription.deleted", { id: "sub_test" });
    await post("/license/restore", { email: "buyer@example.com" });
    const token = new URLSearchParams(new URL(mail[0].text.match(/https:\/\/\S+/)![0]).hash.slice(1)).get("token");
    expect(await (await post("/license/redeem", { token })).json()).toEqual({ license_key: renewed });
  });

  it("repairs a historical canceled paid period by replaying its signed invoice after checkout backfill", async () => {
    await checkout("paid", "subscription");
    await kv.delete("subsession:sub_test");
    for (const key of kv.values.keys()) if (key.startsWith("purchase:")) await kv.delete(key);
    const invoice = { subscription: "sub_test", customer_email: "buyer@example.com",
      lines: { data: [{ period: { end: Math.floor(Date.now() / 1000) + 365 * 86400 } }] } };
    await stripeEvent("evt_historical_renewal", "invoice.paid", invoice);
    const renewed = [...kv.values.entries()].find(([key]) => key.startsWith("refresh:"))![1];
    await stripeEvent("evt_historical_cancel", "customer.subscription.deleted", { id: "sub_test" });
    await checkout("paid", "subscription");
    await stripeEvent("evt_historical_renewal", "invoice.paid", invoice);
    await post("/license/restore", { email: "buyer@example.com" });
    const token = new URLSearchParams(new URL(mail[0].text.match(/https:\/\/\S+/)![0]).hash.slice(1)).get("token");
    const response = await post("/license/redeem", { token });
    const restored = (await response.json() as { license_key: string }).license_key;
    const expiry = (key: string) => JSON.parse(atob(key.split(".")[0].replace(/-/g, "+").replace(/_/g, "/"))).expires_at;
    expect(expiry(restored)).toBe(expiry(renewed));
  });

  it("retains the last paid subscription period for restoration after cancellation", async () => {
    await checkout("paid", "subscription");
    const first = await kv.get("session:cs_test_purchase");
    await stripeEvent("evt_renewal", "invoice.paid", {
      subscription: "sub_test", customer_email: "buyer@example.com",
      lines: { data: [{ period: { end: Math.floor(Date.now() / 1000) + 365 * 86400 } }] },
    });
    const renewed = [...kv.values.entries()].find(([key]) => key.startsWith("refresh:"))![1];
    expect(renewed).not.toBe(first);
    await stripeEvent("evt_cancel", "customer.subscription.deleted", { id: "sub_test" });
    await post("/license/restore", { email: "buyer@example.com" });
    const token = new URLSearchParams(new URL(mail[0].text.match(/https:\/\/\S+/)![0]).hash.slice(1)).get("token");
    expect(await (await post("/license/redeem", { token })).json()).toEqual({ license_key: renewed });
  });

  it("prefers a legacy lifetime envelope over an expired subscription for the same inbox", async () => {
    async function signed(payload: unknown) {
      const data = new TextEncoder().encode(JSON.stringify(payload));
      return `${base64url(data)}.${base64url(new Uint8Array(await crypto.subtle.sign("Ed25519", signer, data)))}`;
    }
    const expired = await signed({ email: "buyer@example.com", product: "curfew-plus", plan: "subscription",
      order_id: "cs_a_expired", issued_at: "2019-01-01T00:00:00Z", expires_at: "2020-01-01T00:00:00Z" });
    const lifetime = await signed({ email: "buyer@example.com", product: "curfew-pro",
      order_id: "cs_z_legacy", issued_at: "2019-01-01T00:00:00Z" });
    await kv.put("session:cs_a_expired", expired);
    await kv.put("session:cs_z_legacy", lifetime);
    await indexPurchase(env, "buyer@example.com", "cs_a_expired");
    await indexPurchase(env, "buyer@example.com", "cs_z_legacy");
    await post("/license/restore", { email: "buyer@example.com" });
    const token = new URLSearchParams(new URL(mail[0].text.match(/https:\/\/\S+/)![0]).hash.slice(1)).get("token");
    expect(await (await post("/license/redeem", { token })).json()).toEqual({ license_key: lifetime });
  });
});
