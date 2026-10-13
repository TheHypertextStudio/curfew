import { isoSeconds, signLicenseKey } from "./crypto.js";
import { invoicePeriodEnd, nowSeconds, subscriptionIDFromInvoice } from "./stripe.js";
import type { Env } from "./types.js";
import { indexPurchase, payload } from "./purchases.js";

const graceSeconds = 3 * 24 * 60 * 60;
const provisionalSubscriptionSeconds = 33 * 24 * 60 * 60;

export function isCurfewCheckout(session: any): boolean {
  const metadata = session.metadata ?? {};
  const sku = metadata.curfew_sku ??
    (metadata.curfew_product_id === "curfew-plus" ? metadata.curfew_entitlement_kind : undefined);
  return (sku === "lifetime" && session.mode === "payment") ||
    (sku === "subscription" && session.mode === "subscription");
}

export async function handleCheckoutCompleted(event: any, env: Env): Promise<boolean> {
  const session = event.data?.object ?? {};
  const sessionID = String(session.id ?? "");
  const email = String(session.customer_details?.email ?? session.customer_email ?? "");
  if (!sessionID || !email || session.payment_status !== "paid" || !isCurfewCheckout(session)) return false;

  if (session.mode !== "subscription") {
    const key = await signLicenseKey({ email, plan: "lifetime", orderID: sessionID }, env.LICENSE_PRIVATE_KEY);
    await env.LICENSE_KV.put(`session:${sessionID}`, key);
    await indexPurchase(env, email, sessionID);
    return true;
  }

  const subscriptionID = String(session.subscription ?? "");
  if (!subscriptionID) return false;
  await env.LICENSE_KV.put(`subsession:${subscriptionID}`, sessionID);
  let token = await env.LICENSE_KV.get(`subtoken:${subscriptionID}`);
  if (!token) {
    token = crypto.randomUUID();
    await env.LICENSE_KV.put(`subtoken:${subscriptionID}`, token);
  }
  const pendingPeriodEnd = await env.LICENSE_KV.get(`subpending:${subscriptionID}`);
  const periodEnd = pendingPeriodEnd ? Number(pendingPeriodEnd) : nowSeconds() + provisionalSubscriptionSeconds;
  const key = await mintSubscriptionKey(env, email, sessionID, token, periodEnd);
  await Promise.all([
    env.LICENSE_KV.put(`refresh:${token}`, key),
    env.LICENSE_KV.put(`session:${sessionID}`, key),
    ...(pendingPeriodEnd ? [env.LICENSE_KV.delete(`subpending:${subscriptionID}`)] : []),
  ]);
  await indexPurchase(env, email, sessionID);
  return true;
}

export async function handleInvoicePaid(event: any, env: Env): Promise<boolean> {
  const invoice = event.data?.object ?? {};
  const subscriptionID = subscriptionIDFromInvoice(invoice);
  const periodEnd = invoicePeriodEnd(invoice);
  const email = String(invoice.customer_email ?? invoice.customer_details?.email ?? "");
  if (!subscriptionID || !periodEnd || !email) return false;
  const sessionID = await env.LICENSE_KV.get(`subsession:${subscriptionID}`);
  const existing = sessionID ? await env.LICENSE_KV.get(`session:${sessionID}`) : null;
  const purchase = existing ? payload(existing) : null;
  const token = await env.LICENSE_KV.get(`subtoken:${subscriptionID}`) ??
    (purchase?.plan === "subscription" ? purchase.refresh_token : null);
  if (!token) {
    await env.LICENSE_KV.put(`subpending:${subscriptionID}`, String(periodEnd));
    return true;
  }
  // Signed invoice replays may arrive out of order. Preserve the latest paid
  // period, including a snapshot repaired after a historical cancellation.
  if (purchase?.expires_at && Date.parse(purchase.expires_at) >= (periodEnd + graceSeconds) * 1000) return true;
  const key = await mintSubscriptionKey(env, email, sessionID ?? subscriptionID, token, periodEnd);
  await env.LICENSE_KV.put(`period:${token}:${periodEnd}`, key);
  await env.LICENSE_KV.put(`refresh:${token}`, key);
  if (sessionID) await env.LICENSE_KV.put(`session:${sessionID}`, key);
  return true;
}

export async function handleSubscriptionDeleted(event: any, env: Env): Promise<boolean> {
  const subscriptionID = String(event.data?.object?.id ?? "");
  if (!subscriptionID) return false;
  const token = await env.LICENSE_KV.get(`subtoken:${subscriptionID}`);
  await Promise.all([
    env.LICENSE_KV.delete(`subpending:${subscriptionID}`),
    env.LICENSE_KV.delete(`subtoken:${subscriptionID}`),
    ...(token ? [env.LICENSE_KV.delete(`refresh:${token}`)] : []),
  ]);
  return true;
}

function mintSubscriptionKey(env: Env, email: string, orderID: string, token: string, periodEnd: number): Promise<string> {
  return signLicenseKey(
    {
      email,
      plan: "subscription",
      orderID,
      expiresAt: isoSeconds((periodEnd + graceSeconds) * 1000),
      refreshToken: token,
    },
    env.LICENSE_PRIVATE_KEY
  );
}
