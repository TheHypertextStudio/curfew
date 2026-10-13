import { handleCheckoutCompleted, handleInvoicePaid, handleSubscriptionDeleted } from "./handlers.js";
import { subscriptionIDFromInvoice, verifyStripeSignature } from "./stripe.js";
import type { Env } from "./types.js";
import { currentSubscriptionKey, indexPurchase, json, payload, purchaseRequest } from "./purchases.js";

/**
 * Curfew internal license issuer, envelope v2. This is deliberately distinct
 * from curfew-protocols: it is not an MCP, AI-host, or Sync-coordinator API.
 */
export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: json(null).headers });
    if (request.method === "GET" && url.pathname === "/health") return json({ status: "ok", envelope_version: 2 });
    if (request.method === "GET" && url.pathname === "/license") return getLicense(url, env, "session_id", "session");
    if (request.method === "GET" && url.pathname === "/license/refresh") return getLicense(url, env, "token", "refresh");
    if (request.method === "POST" && ["/license/activation", "/license/redeem", "/license/restore"].includes(url.pathname)) {
      return purchaseRequest(request, env);
    }
    if (request.method !== "POST" || url.pathname !== "/") return json({ error: "not found" }, 404);

    const body = await request.text();
    const signature = request.headers.get("Stripe-Signature");
    if (!signature || !(await verifyStripeSignature(body, signature, env.STRIPE_WEBHOOK_SECRET))) {
      return new Response("Invalid signature", { status: 400 });
    }
    const event = JSON.parse(body);
    const eventID = String(event.id ?? "");
    if (eventID && (await env.LICENSE_KV.get(`event:${eventID}`))) {
      // A Stripe dashboard resend backfills pre-restoration purchases without
      // minting a new key or changing the original payment/access decision.
      if (event.type === "checkout.session.completed") {
        const session = event.data?.object;
        if (session?.payment_status === "paid" && typeof session.id === "string") {
          const existing = await env.LICENSE_KV.get(`session:${session.id}`);
          // Historical checkouts may predate SKU metadata. Only an existing
          // issuer-stored Curfew envelope can authorize this index repair.
          const purchase = existing ? payload(existing) : null;
          if (purchase) {
            await indexPurchase(env, purchase.email, session.id);
            if (purchase.plan === "subscription" && session.mode === "subscription" &&
              typeof session.subscription === "string" && purchase.refresh_token) {
              const renewed = await env.LICENSE_KV.get(`refresh:${purchase.refresh_token}`);
              if (renewed) await env.LICENSE_KV.put(`session:${session.id}`, renewed);
              await env.LICENSE_KV.put(`subsession:${session.subscription}`, session.id);
            }
          }
        }
      }
      if (event.type === "invoice.paid" || event.type === "invoice.payment_succeeded") {
        const subscriptionID = subscriptionIDFromInvoice(event.data?.object ?? {});
        // A previously issued purchase must first be linked by checkout
        // backfill before an old signed invoice can repair its paid period.
        if (subscriptionID && await env.LICENSE_KV.get(`subsession:${subscriptionID}`)) {
          await handleInvoicePaid(event, env);
        }
      }
      return new Response("ok");
    }

    let handled = false;
    switch (event.type) {
      case "checkout.session.completed": handled = await handleCheckoutCompleted(event, env); break;
      case "invoice.paid":
      case "invoice.payment_succeeded": handled = await handleInvoicePaid(event, env); break;
      case "customer.subscription.deleted": handled = await handleSubscriptionDeleted(event, env); break;
      default: return new Response("ignored");
    }
    if (handled && eventID) await env.LICENSE_KV.put(`event:${eventID}`, "1");
    return new Response("ok");
  },
};

async function getLicense(url: URL, env: Env, parameter: string, prefix: string): Promise<Response> {
  const token = url.searchParams.get(parameter);
  if (!token) return json({ error: `${parameter} required` }, 400);
  const key = prefix === "refresh" ? await currentSubscriptionKey(env, token) :
    await env.LICENSE_KV.get(`${prefix}:${token}`);
  return key ? json({ license_key: key }) : json({ error: "not found" }, 404);
}
