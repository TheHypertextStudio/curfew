import { beforeEach, describe, expect, it } from "vitest";
import worker from "../src/index.js";
import { base64url } from "../src/crypto.js";
import type { Env } from "../src/types.js";

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
  beforeEach(async () => {
    kv = new MemoryKV();
    mail = [];
    const pair = await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"]) as CryptoKeyPair;
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
      RESTORE_EMAIL_FROM: "purchases@hypertext.studio",
      PURCHASE_PORTAL_URL: "https://curfew.hypertext.studio",
      RESTORE_IP_LIMIT: { async limit() { return { success: true }; } },
      RESTORE_EMAIL_LIMIT: { async limit() { return { success: true }; } },
    };
  });

  const post = (path: string, body: unknown) => worker.fetch(new Request(`https://issuer.example${path}`, {
    method: "POST", headers: { "Content-Type": "application/json", "CF-Connecting-IP": "192.0.2.1" }, body: JSON.stringify(body),
  }), env);

  async function checkout(paymentStatus = "paid", mode = "payment") {
    const body = JSON.stringify({ id: `evt_${paymentStatus}_${mode}`, type: "checkout.session.completed", data: { object: {
      id: "cs_test_purchase", mode, status: "complete", payment_status: paymentStatus,
      customer_details: { email: "Buyer@Example.com" }, subscription: mode === "subscription" ? "sub_test" : undefined,
    } } });
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
    await kv.put(refreshEntry, "renewed-signed-key");
    await post("/license/restore", { email: "buyer@example.com" });
    const token = new URLSearchParams(new URL(mail[0].text.match(/https:\/\/\S+/)![0]).hash.slice(1)).get("token");
    expect(await (await post("/license/redeem", { token })).json()).toEqual({ license_key: "renewed-signed-key" });
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
});
