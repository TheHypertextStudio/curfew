#!/usr/bin/env node
// Local workerd + D1 proof. Ephemeral fixture keys; no network/provider payments.
import assert from 'node:assert/strict';
import { createHmac, generateKeyPairSync } from 'node:crypto';
import { realpathSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const cfRequire = createRequire(
  realpathSync(require.resolve('../web/worker/node_modules/cf/package.json')),
);
const { Miniflare, convertV4MiniflareOptions } = cfRequire('miniflare');
const { privateKey } = generateKeyPairSync('ed25519');
const seed = privateKey
  .export({ type: 'pkcs8', format: 'der' })
  .subarray(-32)
  .toString('base64url');
const secret = 'local-runtime-fixture-only';
const runtime = new Miniflare(
  convertV4MiniflareOptions({
    port: 0,
    workers: [
      {
        name: 'issuer',
        modules: true,
        scriptPath: fileURLToPath(
          new URL(
            '../web/worker/.cloudflare/output/v0/workers/default/bundle/index.js',
            import.meta.url,
          ),
        ),
        compatibilityDate: '2026-07-31',
        d1Databases: { LICENSE_DB: 'local-license-fixture' },
        kvNamespaces: ['LICENSE_KV'],
        bindings: { STRIPE_MODE: 'test', STRIPE_WEBHOOK_SECRET: secret, LICENSE_PRIVATE_KEY: seed },
      },
    ],
  }),
);
try {
  const db = await runtime.getD1Database('LICENSE_DB');
  assert.equal((await runtime.dispatchFetch('https://license.example/health')).status, 503);
  const schema = await readFile(
    new URL('../web/worker/migrations/0001_license_store.sql', import.meta.url),
    'utf8',
  );
  await db.batch(
    schema
      .split(';')
      .filter((sql) => sql.trim())
      .map((sql) => db.prepare(sql)),
  );
  await db.prepare('UPDATE curfew_license_meta SET ready=1 WHERE id=1').run();
  assert.equal((await runtime.dispatchFetch('https://license.example/health')).status, 200);
  const event = async (id, type, object) => {
    const body = JSON.stringify({
      id,
      type,
      created: Math.floor(Date.now() / 1000),
      livemode: false,
      data: { object },
    });
    const t = Math.floor(Date.now() / 1000),
      signature = createHmac('sha256', secret).update(`${t}.${body}`).digest('hex');
    return runtime.dispatchFetch('https://license.example/', {
      method: 'POST',
      headers: { 'Stripe-Signature': `t=${t},v1=${signature}` },
      body,
    });
  };
  const checkout = {
    id: 'cs_runtime',
    mode: 'payment',
    payment_status: 'paid',
    payment_intent: 'pi_runtime',
    customer_details: { email: 'fixture@example.com' },
    metadata: { curfew_sku: 'lifetime' },
  };
  const responses = await Promise.all(
    Array.from({ length: 8 }, (_, n) =>
      event(`evt_runtime_${n}`, 'checkout.session.completed', checkout),
    ),
  );
  assert.ok(responses.every((response) => response.status === 200));
  const activate = () =>
    runtime.dispatchFetch('https://license.example/license/activation', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ session_id: 'cs_runtime' }),
    });
  const first = await activate();
  assert.equal(first.status, 200);
  const purchase = await first.json();
  await event('evt_runtime_refund', 'charge.refunded', {
    id: 'ch_runtime',
    payment_intent: 'pi_runtime',
    refunded: true,
    amount: 2000,
    amount_refunded: 2000,
  });
  await event('evt_runtime_late', 'checkout.session.async_payment_succeeded', checkout);
  assert.equal((await activate()).status, 404);
  assert.equal(
    (await runtime.dispatchFetch('https://license.example/license?session_id=cs_runtime')).status,
    404,
  );
  const redeemed = await runtime.dispatchFetch('https://license.example/license/redeem', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ token: purchase.activation_token }),
  });
  assert.equal(redeemed.status, 404);
  assert.equal((await (await runtime.getKVNamespace('LICENSE_KV')).list()).keys.length, 0);
  console.log(
    'Curfew workerd/D1 readiness, concurrent first delivery, refund replay and recovery checks passed.',
  );
} finally {
  await runtime.dispose();
}
