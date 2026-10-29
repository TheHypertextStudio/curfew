import type { Env } from './types.js';
import { digest } from './purchases.js';

export const stripeID = (value: any): string =>
  typeof value === 'string' ? value : typeof value?.id === 'string' ? value.id : '';
interface InvoiceFact {
  id: string;
  subscriptionID: string;
  email: string;
  periodEnd: number;
  amountPaid: number;
  currency: string;
}
interface Allocation {
  paymentIntent: string;
  amountPaid: number;
  currency: string;
}

export async function recordCheckoutFunding(session: any, env: Env): Promise<void> {
  const pi = stripeID(session.payment_intent);
  const invoice = stripeID(session.invoice);
  if (session.mode === 'payment' && pi) await env.LICENSE_KV.put(`order-payment:${session.id}`, pi);
  if (session.mode === 'subscription' && invoice)
    await env.LICENSE_KV.put(`order-invoice:${session.id}`, invoice);
}

export async function recordInvoiceFunding(
  invoice: any,
  fact: InvoiceFact,
  env: Env,
): Promise<void> {
  const previous = await env.LICENSE_KV.get(`invoice:${fact.id}`);
  const accepted = previous ? (JSON.parse(previous) as InvoiceFact) : null;
  if (
    accepted &&
    (accepted.subscriptionID !== fact.subscriptionID ||
      accepted.periodEnd !== fact.periodEnd ||
      accepted.currency !== fact.currency)
  )
    throw new Error('Inconsistent paid invoice provenance');
  const requirement = accepted
    ? { ...fact, amountPaid: Math.max(accepted.amountPaid, fact.amountPaid) }
    : fact;
  await env.LICENSE_KV.put(`invoice:${fact.id}`, JSON.stringify(requirement));
  await env.LICENSE_KV.put(`subinvoice:${fact.subscriptionID}:${fact.id}`, fact.id);
  const pi = stripeID(invoice.payment_intent);
  if (pi)
    await env.LICENSE_KV.put(
      `invoice-payment:${fact.id}:legacy:${pi}`,
      JSON.stringify({ paymentIntent: pi, amountPaid: fact.amountPaid, currency: fact.currency }),
    );
  for (const allocation of invoice.payments?.data ?? []) await recordAllocation(allocation, env);
}

export async function recordAllocation(allocation: any, env: Env): Promise<string | null> {
  const invoiceID = stripeID(allocation.invoice);
  const pi =
    allocation.payment?.type === 'payment_intent'
      ? stripeID(allocation.payment.payment_intent)
      : '';
  if (
    allocation.status !== 'paid' ||
    !invoiceID ||
    !pi ||
    typeof allocation.id !== 'string' ||
    !Number.isSafeInteger(allocation.amount_paid) ||
    allocation.amount_paid <= 0
  )
    return null;
  await env.LICENSE_KV.put(
    `invoice-payment:${invoiceID}:${allocation.id}`,
    JSON.stringify({
      paymentIntent: pi,
      amountPaid: allocation.amount_paid,
      currency: String(allocation.currency ?? ''),
    }),
  );
  return invoiceID;
}

export async function invoiceIsFunded(env: Env, invoiceID: string): Promise<boolean> {
  const stored = await env.LICENSE_KV.get(`invoice:${invoiceID}`);
  if (!stored) return false;
  const invoice = JSON.parse(stored) as InvoiceFact;
  const entries = await env.LICENSE_KV.list({
    prefix: `invoice-payment:${invoiceID}:`,
    limit: 100,
  });
  if (!entries.list_complete) return false;
  const paid = new Map<string, number>();
  const modern = entries.keys.filter(
    ({ name }) => !name.startsWith(`invoice-payment:${invoiceID}:legacy:`),
  );
  // Actual allocation records take precedence, even while incomplete or
  // refunded. A legacy aggregate must never fill their missing funding.
  const authoritative = modern.length ? modern : entries.keys;
  for (const { name } of authoritative) {
    const value = await env.LICENSE_KV.get(name);
    if (!value) continue;
    const allocation = JSON.parse(value) as Allocation;
    if (
      (invoice.currency && allocation.currency !== invoice.currency) ||
      (await env.LICENSE_KV.get(`refund:${allocation.paymentIntent}`))
    )
      continue;
    // A legacy invoice PI and its modern InvoicePayment describe the same
    // funding. Never count that payment twice when both events are backfilled.
    paid.set(
      allocation.paymentIntent,
      Math.max(paid.get(allocation.paymentIntent) ?? 0, allocation.amountPaid),
    );
  }
  return (
    Number.isSafeInteger(invoice.amountPaid) &&
    invoice.amountPaid > 0 &&
    [...paid.values()].reduce((sum, amount) => sum + amount, 0) >= invoice.amountPaid
  );
}

export async function keyIsFunded(
  env: Env,
  key: string,
  plan: string,
  orderID: string,
): Promise<boolean> {
  if (plan === 'lifetime') {
    const pi = await env.LICENSE_KV.get(`order-payment:${orderID}`);
    return !!pi && !(await env.LICENSE_KV.get(`refund:${pi}`));
  }
  const invoice = await env.LICENSE_KV.get(`key-invoice:${await digest(key)}`);
  return !!invoice && invoiceIsFunded(env, invoice);
}

export async function fullRefund(event: any, env: Env): Promise<boolean> {
  const charge = event.data?.object;
  const pi = stripeID(charge?.payment_intent);
  // charge.refunded also fires for partial refunds. Only confirmed full
  // refunds close this payment; no tombstone comes from refund initiation.
  if (!pi || charge?.refunded !== true) return false;
  await env.LICENSE_KV.put(`refund:${pi}`, '1');
  return true;
}

export type { InvoiceFact };
