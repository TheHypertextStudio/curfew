import { isoSeconds, signLicenseKey } from './crypto.js';
import { invoicePeriodEnd, subscriptionIDFromInvoice } from './stripe.js';
import type { Env } from './types.js';
import { digest, indexPurchase, payload } from './purchases.js';
import {
  invoiceIsFunded,
  recordAllocation,
  recordCheckoutFunding,
  recordInvoiceFunding,
  stripeID,
  type InvoiceFact,
} from './funding.js';

const graceSeconds = 3 * 24 * 60 * 60;
export function isCurfewCheckout(session: any): boolean {
  const metadata = session.metadata ?? {};
  const sku =
    metadata.curfew_sku ??
    (metadata.curfew_product_id === 'curfew-plus' ? metadata.curfew_entitlement_kind : undefined);
  return (
    (sku === 'lifetime' && session.mode === 'payment') ||
    (sku === 'subscription' && session.mode === 'subscription')
  );
}

export async function handleCheckoutCompleted(event: any, env: Env): Promise<boolean> {
  const session = event.data?.object ?? {};
  const sessionID = stripeID(session.id);
  const email = String(session.customer_details?.email ?? session.customer_email ?? '');
  if (!sessionID || !email || session.payment_status !== 'paid' || !isCurfewCheckout(session))
    return false;
  await recordCheckoutFunding(session, env);
  const existing = await env.LICENSE_KV.get(`session:${sessionID}`);
  const purchase = existing ? payload(existing) : null;
  if (session.mode === 'payment') {
    const pi = await env.LICENSE_KV.get(`order-payment:${sessionID}`);
    if (!pi) throw new Error('Paid checkout is missing payment provenance');
    if (await env.LICENSE_KV.get(`refund:${pi}`)) return true;
    if (!purchase)
      await env.LICENSE_KV.put(
        `session:${sessionID}`,
        await signLicenseKey(
          { email, plan: 'lifetime', orderID: sessionID },
          env.LICENSE_PRIVATE_KEY,
        ),
      );
    await indexPurchase(env, purchase?.email ?? email, sessionID);
    return true;
  }
  const subscriptionID = stripeID(session.subscription);
  if (!subscriptionID) return false;
  await env.LICENSE_KV.put(`subsession:${subscriptionID}`, sessionID);
  let token =
    (await env.LICENSE_KV.get(`subidentity:${subscriptionID}`)) ??
    purchase?.refresh_token ??
    (await env.LICENSE_KV.get(`subtoken:${subscriptionID}`));
  if (!token) token = crypto.randomUUID();
  await env.LICENSE_KV.put(`subidentity:${subscriptionID}`, token);
  if (!(await env.LICENSE_KV.get(`subcancel:${subscriptionID}`)))
    await env.LICENSE_KV.put(`subtoken:${subscriptionID}`, token);
  // Keep the paid checkout association while its invoice/payment events are
  // pending. There is no arbitrary grant based on webhook processing time.
  await indexPurchase(env, purchase?.email ?? email, sessionID);
  await reconcileSubscription(subscriptionID, env);
  return true;
}

export async function handleInvoicePaid(event: any, env: Env): Promise<boolean> {
  const invoice = event.data?.object ?? {};
  const subscriptionID = subscriptionIDFromInvoice(invoice);
  const periodEnd = invoicePeriodEnd(invoice);
  const email = String(invoice.customer_email ?? invoice.customer_details?.email ?? '');
  const invoiceID = stripeID(invoice.id);
  const amountPaid = Number(invoice.amount_paid);
  if (
    !subscriptionID ||
    !periodEnd ||
    !email ||
    !invoiceID ||
    invoice.status !== 'paid' ||
    invoice.amount_remaining !== 0 ||
    !Number.isSafeInteger(amountPaid) ||
    amountPaid <= 0
  )
    return false;
  const fact: InvoiceFact = {
    id: invoiceID,
    subscriptionID,
    email,
    periodEnd,
    amountPaid,
    currency: String(invoice.currency ?? ''),
  };
  await recordInvoiceFunding(invoice, fact, env);
  await reconcileSubscription(subscriptionID, env);
  return true;
}

export async function handleInvoicePayment(event: any, env: Env): Promise<boolean> {
  const invoiceID = await recordAllocation(event.data?.object ?? {}, env);
  if (!invoiceID) return false;
  const invoice = await env.LICENSE_KV.get(`invoice:${invoiceID}`);
  if (invoice)
    await reconcileSubscription((JSON.parse(invoice) as InvoiceFact).subscriptionID, env);
  return true;
}

async function reconcileSubscription(subscriptionID: string, env: Env): Promise<void> {
  let token =
    (await env.LICENSE_KV.get(`subidentity:${subscriptionID}`)) ??
    (await env.LICENSE_KV.get(`subtoken:${subscriptionID}`));
  let sessionID = await env.LICENSE_KV.get(`subsession:${subscriptionID}`);
  if (!sessionID && token) {
    const retained = await env.LICENSE_KV.get(`refresh:${token}`);
    sessionID = retained ? (payload(retained)?.order_id ?? null) : null;
  }
  if (!sessionID) return; // An unrelated invoice never creates a Curfew order.
  const existing = await env.LICENSE_KV.get(`session:${sessionID}`);
  token ??= existing ? (payload(existing)?.refresh_token ?? null) : null;
  if (!token) return;
  const invoices = await env.LICENSE_KV.list({
    prefix: `subinvoice:${subscriptionID}:`,
    limit: 1000,
  });
  if (!invoices.list_complete) throw new Error('Subscription history requires operator review');
  let latest: { key: string; end: number } | null = null;
  for (const { name } of invoices.keys) {
    const invoiceID = await env.LICENSE_KV.get(name);
    const stored = invoiceID ? await env.LICENSE_KV.get(`invoice:${invoiceID}`) : null;
    if (!stored || !(await invoiceIsFunded(env, invoiceID!))) continue;
    const invoice = JSON.parse(stored) as InvoiceFact;
    const periodKey = `period:${token}:${invoice.periodEnd}:${invoice.id}`;
    let key = await env.LICENSE_KV.get(periodKey);
    if (!key) {
      key = await signLicenseKey(
        {
          email: invoice.email,
          plan: 'subscription',
          orderID: sessionID,
          expiresAt: isoSeconds((invoice.periodEnd + graceSeconds) * 1000),
          refreshToken: token,
        },
        env.LICENSE_PRIVATE_KEY,
      );
      await env.LICENSE_KV.put(periodKey, key);
      await env.LICENSE_KV.put(`key-invoice:${await digest(key)}`, invoice.id);
    }
    if (!latest || invoice.periodEnd > latest.end) latest = { key, end: invoice.periodEnd };
  }
  if (latest) {
    await env.LICENSE_KV.put(`session:${sessionID}`, latest.key);
    await env.LICENSE_KV.put(`refresh:${token}`, latest.key);
  }
}

export async function handleSubscriptionDeleted(event: any, env: Env): Promise<boolean> {
  const subscriptionID = stripeID(event.data?.object?.id);
  if (!subscriptionID) return false;
  const token = await env.LICENSE_KV.get(`subtoken:${subscriptionID}`);
  if (token) await env.LICENSE_KV.put(`subidentity:${subscriptionID}`, token);
  await env.LICENSE_KV.put(`subcancel:${subscriptionID}`, '1');
  await env.LICENSE_KV.delete(`subtoken:${subscriptionID}`);
  await env.LICENSE_KV.delete(`subpending:${subscriptionID}`);
  if (token) await env.LICENSE_KV.delete(`refresh:${token}`);
  return true;
}
