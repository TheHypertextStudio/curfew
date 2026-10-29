import { beforeEach, describe, expect, it } from 'vitest';
import worker from '../src/index.js';
import { base64url, base64urlDecode } from '../src/crypto.js';
import type { Env } from '../src/types.js';
import { atomic, LicenseTransaction, TransactionConflict } from '../src/transaction-store.js';
import { SQLiteD1 } from './support/sqlite-d1.js';

class LegacyKV {
  values = new Map<string, string>();
  writes = 0;
  async get(key: string) {
    return this.values.get(key) ?? null;
  }
  async put(key: string, value: string) {
    this.writes++;
    this.values.set(key, value);
  }
  async delete(key: string) {
    this.writes++;
    this.values.delete(key);
  }
  async list({ prefix = '' } = {}) {
    return {
      keys: [...this.values.keys()]
        .filter((key) => key.startsWith(prefix))
        .map((name) => ({ name })),
      list_complete: true,
    };
  }
}

describe('public transactional fulfillment', () => {
  let env: Env & { LICENSE_DB?: D1Database };
  let db: SQLiteD1;
  let kv: LegacyKV;
  let mail: any[];
  const created = 1793200000;
  const end = 1824736000;
  beforeEach(async () => {
    db = new SQLiteD1();
    kv = new LegacyKV();
    mail = [];
    const pair = (await crypto.subtle.generateKey('Ed25519', true, [
      'sign',
      'verify',
    ])) as CryptoKeyPair;
    const der = new Uint8Array(await crypto.subtle.exportKey('pkcs8', pair.privateKey));
    env = {
      STRIPE_MODE: 'test',
      STRIPE_WEBHOOK_SECRET: 'fixture-only',
      LICENSE_PRIVATE_KEY: base64url(der.slice(-32)),
      LICENSE_KV: kv as unknown as KVNamespace,
      LICENSE_DB: db as unknown as D1Database,
      EMAIL: {
        async send(message: any) {
          mail.push(message);
          return { messageId: 'fixture' } as EmailSendResult;
        },
      },
      RESTORE_EMAIL_FROM: 'accounts@thecurfew.app',
      PURCHASE_PORTAL_URL: 'https://staging.thecurfew.app',
      RESTORE_IP_LIMIT: {
        async limit() {
          return { success: true };
        },
      },
      RESTORE_EMAIL_LIMIT: {
        async limit() {
          return { success: true };
        },
      },
    };
  });
  async function event(id: string, type: string, object: any) {
    const body = JSON.stringify({ id, type, created, livemode: false, data: { object } });
    const t = Math.floor(Date.now() / 1000);
    const secret = await crypto.subtle.importKey(
      'raw',
      new TextEncoder().encode(env.STRIPE_WEBHOOK_SECRET),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['sign'],
    );
    const sig = new Uint8Array(
      await crypto.subtle.sign('HMAC', secret, new TextEncoder().encode(`${t}.${body}`)),
    );
    return worker.fetch(
      new Request('https://issuer.example/', {
        method: 'POST',
        body,
        headers: { 'Stripe-Signature': `t=${t},v1=${Buffer.from(sig).toString('hex')}` },
      }),
      env,
    );
  }
  function checkout(session = 'cs_order', mode = 'payment', pi: string | null = 'pi_order') {
    return {
      id: session,
      created,
      mode,
      payment_status: 'paid',
      payment_intent: pi,
      invoice: mode === 'subscription' ? 'in_initial' : null,
      subscription: mode === 'subscription' ? 'sub_order' : null,
      customer_details: { email: 'buyer@example.com' },
      metadata: { curfew_sku: mode === 'payment' ? 'lifetime' : 'subscription' },
    };
  }
  const post = (path: string, body: unknown) =>
    worker.fetch(
      new Request(`https://issuer.example${path}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'CF-Connecting-IP': '192.0.2.1' },
        body: JSON.stringify(body),
      }),
      env,
    );
  const activate = (session = 'cs_order') => post('/license/activation', { session_id: session });
  const decoded = (key: string) =>
    JSON.parse(new TextDecoder().decode(base64urlDecode(key.split('.')[0])));
  const invoice = (id = 'in_initial', periodEnd = end, pi = 'pi_initial') => ({
    id,
    subscription: 'sub_order',
    customer_email: 'buyer@example.com',
    paid: true,
    status: 'paid',
    amount_remaining: 0,
    amount_paid: 2000,
    payment_intent: pi,
    lines: { data: [{ period: { end: periodEnd } }] },
  });
  const refund = (pi = 'pi_order', full = true) => ({
    id: `ch_${pi}`,
    payment_intent: pi,
    refunded: full,
    amount: 2000,
    amount_refunded: full ? 2000 : 500,
  });
  async function subscription() {
    await event(
      'evt_checkout',
      'checkout.session.completed',
      checkout('cs_order', 'subscription', null),
    );
    await event('evt_initial_invoice', 'invoice.paid', invoice());
  }

  it('rejects unauthenticated webhooks before database access', async () => {
    db.sqlite.exec('UPDATE curfew_license_meta SET ready=0');
    const response = await worker.fetch(
      new Request('https://issuer.example/', { method: 'POST', body: '{}' }),
      env,
    );
    expect(response.status).toBe(400);
    expect(db.reads).toBe(0);
  });
  it('does not advertise readiness when the authority is unconfigured or its import is unaccepted', async () => {
    db.sqlite.exec('UPDATE curfew_license_meta SET ready=0');
    expect((await worker.fetch(new Request('https://issuer.example/health'), env)).status).toBe(
      503,
    );
    expect((await event('evt_unready', 'checkout.session.completed', checkout())).status).toBe(503);
    expect(kv.writes).toBe(0);
  });
  it('invalidates read-only responses, range phantoms and ABA after another transaction commits', async () => {
    for (const kind of ['read', 'scan', 'aba']) {
      const stale = new LicenseTransaction(env.LICENSE_DB!);
      await stale.initialize();
      if (kind === 'scan') await stale.list({ prefix: 'proof:' });
      else await stale.get('proof:key');
      await atomic(env.LICENSE_DB!, async (store) => {
        await store.put('proof:key', 'changed');
      });
      if (kind === 'aba')
        await atomic(env.LICENSE_DB!, async (store) => {
          await store.delete('proof:key');
        });
      await expect(stale.commit()).rejects.toBeInstanceOf(TransactionConflict);
    }
  });
  it('rolls back mutations when a later statement fails before the event marker', async () => {
    db.failAfterStatements = 2;
    expect((await event('evt_mid_failure', 'checkout.session.completed', checkout())).status).toBe(
      503,
    );
    expect((await activate()).status).toBe(404);
    expect((await event('evt_mid_failure', 'checkout.session.completed', checkout())).status).toBe(
      200,
    );
  });
  it('keeps a durable email with the same ticket across delivery failure and scheduled retry', async () => {
    await event('evt_paid', 'checkout.session.completed', checkout());
    const send = env.EMAIL!.send;
    let attempted: any;
    env.EMAIL = {
      async send(message) {
        attempted = message;
        throw new Error('provider unavailable');
      },
    };
    expect((await post('/license/restore', { email: 'buyer@example.com' })).status).toBe(202);
    expect(mail).toHaveLength(0);
    const queued = db.sqlite
      .prepare("SELECT key,value FROM curfew_license_record WHERE key LIKE 'outbox:%'")
      .get() as any;
    expect(queued).toBeDefined();
    const body = JSON.parse(queued.value);
    body.leaseUntil = 0;
    await atomic(env.LICENSE_DB!, async (store) => {
      await store.put(queued.key, JSON.stringify(body));
    });
    env.EMAIL = { send };
    await worker.scheduled({} as ScheduledController, env);
    expect(mail).toHaveLength(1);
    expect(mail[0].text).toBe(attempted.text);
    expect(
      db.sqlite
        .prepare("SELECT count(*) AS n FROM curfew_license_record WHERE key LIKE 'outbox:%'")
        .get()!.n,
    ).toBe(0);
    const token = new URL(mail[0].text.match(/https:\/\/\S+/)[0]).hash.slice('#token='.length);
    expect((await post('/license/redeem', { token })).status).toBe(200);
  });
  it('consumes each external rate limit once when a transaction conflicts', async () => {
    let ip = 0;
    let email = 0;
    env.RESTORE_IP_LIMIT = {
      async limit() {
        ip++;
        return { success: true };
      },
    };
    env.RESTORE_EMAIL_LIMIT = {
      async limit() {
        email++;
        return { success: true };
      },
    };
    db.beforeBatch = () => {
      db.beforeBatch = null;
      db.sqlite.exec('UPDATE curfew_license_meta SET revision=revision+1');
    };
    expect((await post('/license/restore', { email: 'buyer@example.com' })).status).toBe(202);
    expect(ip).toBe(1);
    expect(email).toBe(1);
    expect(mail).toHaveLength(1);
  });
  it('joins modern invoice allocations in either event order without exposing unsupported funding', async () => {
    await event(
      'evt_checkout',
      'checkout.session.completed',
      checkout('cs_order', 'subscription', null),
    );
    const modern = { ...invoice(), payment_intent: null };
    await event('evt_modern_invoice', 'invoice.paid', modern);
    expect((await activate()).status).toBe(404);
    const allocation = (id: string, pi: string, amount: number) => ({
      id,
      invoice: 'in_initial',
      status: 'paid',
      amount_paid: amount,
      currency: '',
      payment: { type: 'payment_intent', payment_intent: pi },
    });
    await event('evt_allocation_a', 'invoice_payment.paid', allocation('inpay_a', 'pi_a', 1000));
    expect((await activate()).status).toBe(404);
    await event('evt_allocation_b', 'invoice_payment.paid', allocation('inpay_b', 'pi_b', 1000));
    expect((await activate()).status).toBe(200);
    await event('evt_refund_a', 'charge.refunded', refund('pi_a'));
    expect((await activate()).status).toBe(404);
    await event(
      'evt_allocation_replay',
      'invoice_payment.paid',
      allocation('inpay_a', 'pi_a', 1000),
    );
    expect((await activate()).status).toBe(404);
  });
  it('keeps a concurrent subscription identity stable and honors a cancellation preceding checkout', async () => {
    await event('evt_cancel_early', 'customer.subscription.deleted', { id: 'sub_order' });
    await Promise.all(
      Array.from({ length: 6 }, (_, n) =>
        event(
          `evt_first_${n}`,
          'checkout.session.completed',
          checkout('cs_order', 'subscription', null),
        ),
      ),
    );
    await event('evt_paid_invoice', 'invoice.paid', invoice());
    const first = ((await (await activate()).json()) as any).license_key;
    expect(typeof first).toBe('string');
    const before = decoded(first).refresh_token;
    await event(
      'evt_late_checkout',
      'checkout.session.completed',
      checkout('cs_order', 'subscription', null),
    );
    expect(decoded(((await (await activate()).json()) as any).license_key).refresh_token).toBe(
      before,
    );
    expect(
      db.sqlite
        .prepare("SELECT value FROM curfew_license_record WHERE key='subtoken:sub_order'")
        .get(),
    ).toBeUndefined();
  });

  it('does not restore a refunded period by replaying an earlier partial invoice snapshot', async () => {
    await event(
      'evt_checkout',
      'checkout.session.completed',
      checkout('cs_order', 'subscription', null),
    );
    const partial = {
      ...invoice(),
      payment_intent: null,
      paid: false,
      status: 'open',
      amount_remaining: 1000,
      amount_paid: 1000,
    };
    await event('evt_partial_payment', 'invoice.payment_succeeded', partial);
    const allocation = (id: string, pi: string) => ({
      id,
      invoice: 'in_initial',
      status: 'paid',
      amount_paid: 1000,
      currency: '',
      payment: { type: 'payment_intent', payment_intent: pi },
    });
    await event('evt_alloc_a', 'invoice_payment.paid', allocation('inpay_a', 'pi_a'));
    await event('evt_alloc_b', 'invoice_payment.paid', allocation('inpay_b', 'pi_b'));
    await event('evt_fully_paid', 'invoice.paid', { ...invoice(), payment_intent: null });
    expect((await activate()).status).toBe(200);
    await event('evt_refunded_b', 'charge.refunded', refund('pi_b'));
    expect((await activate()).status).toBe(404);
    await event('evt_partial_payment', 'invoice.payment_succeeded', partial);
    expect((await activate()).status).toBe(404);
  });
  it('never falls back to an overstated legacy reference after modern allocations arrive', async () => {
    await event(
      'evt_checkout',
      'checkout.session.completed',
      checkout('cs_order', 'subscription', null),
    );
    await event('evt_legacy_invoice', 'invoice.paid', invoice('in_initial', end, 'pi_a'));
    const allocation = (id: string, pi: string) => ({
      id,
      invoice: 'in_initial',
      status: 'paid',
      amount_paid: 1000,
      currency: '',
      payment: { type: 'payment_intent', payment_intent: pi },
    });
    await event('evt_alloc_a', 'invoice_payment.paid', allocation('inpay_a', 'pi_a'));
    await event('evt_alloc_b', 'invoice_payment.paid', allocation('inpay_b', 'pi_b'));
    await event('evt_refunded_b', 'charge.refunded', refund('pi_b'));
    expect((await activate()).status).toBe(404);
    await event('evt_old_again', 'invoice.paid', invoice('in_initial', end, 'pi_a'));
    expect((await activate()).status).toBe(404);
  });

  it('removes physically expired recovery and outbox data during scheduled retry', async () => {
    await atomic(env.LICENSE_DB!, async (store) => {
      await store.put('activation:expired', JSON.stringify({ expiresAt: 1 }), { expirationTtl: 1 });
      await store.put('outbox:expired', JSON.stringify({ message: {}, expiresAt: 1 }), {
        expirationTtl: 1,
      });
    });
    db.sqlite.exec("UPDATE curfew_license_record SET expires_at=1 WHERE key LIKE '%:expired'");
    await worker.scheduled({} as ScheduledController, env);
    expect(
      db.sqlite
        .prepare("SELECT count(*) AS n FROM curfew_license_record WHERE key LIKE '%:expired'")
        .get()!.n,
    ).toBe(0);
    expect(mail).toHaveLength(0);
  });
  it('fails closed without the transactional authority and leaves legacy data untouched', async () => {
    delete env.LICENSE_DB;
    expect((await event('evt_missing', 'checkout.session.completed', checkout())).status).toBe(503);
    expect(kv.writes).toBe(0);
  });
  it('commits first deliveries with distinct event IDs as one canonical license without KV writes', async () => {
    const responses = await Promise.all(
      Array.from({ length: 8 }, (_, n) =>
        event(`evt_${n}`, 'checkout.session.completed', checkout()),
      ),
    );
    expect(responses.every((response) => response.status === 200)).toBe(true);
    expect(kv.writes).toBe(0);
    const keys = await Promise.all(
      Array.from({ length: 4 }, async () => ((await (await activate()).json()) as any).license_key),
    );
    expect(new Set(keys).size).toBe(1);
    expect(typeof keys[0]).toBe('string');
  });
  it('never restores a fully refunded lifetime payment through any online delivery path', async () => {
    await event('evt_checkout', 'checkout.session.completed', checkout());
    const first = (await (await activate()).json()) as any;
    await event('evt_refund', 'charge.refunded', refund());
    await event('evt_replay', 'checkout.session.completed', checkout());
    expect((await activate()).status).toBe(404);
    expect(
      (await worker.fetch(new Request('https://issuer.example/license?session_id=cs_order'), env))
        .status,
    ).toBe(404);
    expect((await post('/license/redeem', { token: first.activation_token })).status).toBe(404);
    await post('/license/restore', { email: 'buyer@example.com' });
    const token = new URL(mail[0].text.match(/https:\/\/\S+/)[0]).hash.slice('#token='.length);
    expect((await post('/license/redeem', { token })).status).toBe(404);
  });
  it('keeps a refund that arrives before checkout and concurrent replay terminal', async () => {
    await Promise.all([
      event('evt_refund', 'charge.refunded', refund()),
      event('evt_checkout', 'checkout.session.completed', checkout()),
    ]);
    await event('evt_late', 'checkout.session.async_payment_succeeded', checkout());
    expect((await activate()).status).toBe(404);
  });
  it('preserves access after a partial refund and preserves a separate unrefunded purchase', async () => {
    await event('evt_checkout', 'checkout.session.completed', checkout());
    await event('evt_partial', 'charge.refunded', refund('pi_order', false));
    expect((await activate()).status).toBe(200);
    await event(
      'evt_other_order',
      'checkout.session.completed',
      checkout('cs_other', 'payment', 'pi_other'),
    );
    await event('evt_full', 'charge.refunded', refund());
    expect((await activate('cs_other')).status).toBe(200);
  });
  it('waits for an actual paid invoice instead of minting a provisional subscription', async () => {
    await event(
      'evt_checkout',
      'checkout.session.completed',
      checkout('cs_order', 'subscription', null),
    );
    expect((await activate()).status).toBe(404);
    await event('evt_invoice', 'invoice.paid', invoice());
    const key = ((await (await activate()).json()) as any).license_key;
    expect(decoded(key).expires_at).toBe(
      new Date((end + 3 * 86400) * 1000).toISOString().replace('.000Z', 'Z'),
    );
  });
  it('rolls back failed persistence without acknowledging or granting the purchase', async () => {
    db.failNextBatch = true;
    expect((await event('evt_failed', 'checkout.session.completed', checkout())).status).toBe(503);
    expect((await activate()).status).toBe(404);
    expect((await event('evt_failed', 'checkout.session.completed', checkout())).status).toBe(200);
    expect((await activate()).status).toBe(200);
  });
  it('removes a refunded renewal from refresh and recovery while retaining the previous paid period', async () => {
    await subscription();
    const original = ((await (await activate()).json()) as any).license_key;
    const token = decoded(original).refresh_token;
    await event(
      'evt_renewal',
      'invoice.paid',
      invoice('in_renewal', end + 365 * 86400, 'pi_renewal'),
    );
    await event('evt_refund', 'charge.refunded', refund('pi_renewal'));
    await event(
      'evt_replayed_invoice',
      'invoice.paid',
      invoice('in_renewal', end + 365 * 86400, 'pi_renewal'),
    );
    await event('evt_cancel', 'customer.subscription.deleted', { id: 'sub_order' });
    const restored = ((await (await activate()).json()) as any).license_key;
    expect(decoded(restored).expires_at).toBe(decoded(original).expires_at);
    const refreshed = await worker.fetch(
      new Request(`https://issuer.example/license/refresh?token=${token}`),
      env,
    );
    expect(decoded(((await refreshed.json()) as any).license_key).expires_at).toBe(
      decoded(original).expires_at,
    );
  });
});
