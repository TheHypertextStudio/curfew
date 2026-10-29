#!/usr/bin/env node
/** Offline preparation only. No provider calls, credentials, or ready switch. */
import { readFile, open } from 'node:fs/promises';
import { createHash, createPublicKey, verify } from 'node:crypto';

const args = process.argv.slice(2);
const option = (name) => {
  const i = args.indexOf(name);
  if (i < 0 || !args[i + 1]) throw new Error(`Missing ${name}`);
  return args[i + 1];
};
const hash = (value) => createHash('sha256').update(value).digest('base64url');
const text = (value) => `CAST(X'${Buffer.from(value).toString('hex')}' AS TEXT)`;
try {
  if (args[0] !== 'prepare')
    throw new Error(
      'Use prepare with snapshot, provenance, mode, namespace, public-key and output',
    );
  const mode = option('--mode'),
    namespace = option('--namespace');
  if (!['production', 'staging'].includes(mode) || !/^[a-f0-9]{32}$/.test(namespace))
    throw new Error('Invalid import environment');
  const snapshotBytes = await readFile(option('--snapshot')),
    proofBytes = await readFile(option('--provenance'));
  if (snapshotBytes.length > 20 * 1024 * 1024 || proofBytes.length > 20 * 1024 * 1024)
    throw new Error('Import input exceeds review bound');
  const snapshot = JSON.parse(snapshotBytes),
    proof = JSON.parse(proofBytes);
  if (
    snapshot.version !== 1 ||
    proof.version !== 1 ||
    snapshot.mode !== mode ||
    proof.mode !== mode ||
    snapshot.namespaceID !== namespace
  )
    throw new Error('Import environment/provenance mismatch');
  if (
    !Array.isArray(snapshot.records) ||
    snapshot.records.length > 10000 ||
    !Array.isArray(proof.orders) ||
    !Array.isArray(proof.invoices) ||
    !Array.isArray(proof.refunds)
  )
    throw new Error('Invalid import inventory');
  const publicBytes = Buffer.from(option('--public-key'), 'base64');
  if (publicBytes.length !== 32) throw new Error('Expected matching Ed25519 public key');
  const publicKey = createPublicKey({
    key: Buffer.concat([Buffer.from('302a300506032b6570032100', 'hex'), publicBytes]),
    format: 'der',
    type: 'spki',
  });
  const records = new Map();
  for (const row of snapshot.records) {
    if (
      typeof row.key !== 'string' ||
      typeof row.value !== 'string' ||
      records.has(row.key) ||
      row.key.includes('\0') ||
      row.value.includes('\0') ||
      row.key.startsWith('migration:') ||
      row.key.startsWith('outbox:')
    )
      throw new Error('Unsafe or duplicate snapshot record');
    if (Buffer.byteLength(row.key) > 512 || Buffer.byteLength(row.value) > 128 * 1024)
      throw new Error('Snapshot record exceeds issuer bound');
    if (
      row.expiration !== undefined &&
      (!Number.isSafeInteger(row.expiration) || row.expiration <= 0)
    )
      throw new Error('Invalid record expiration');
    records.set(row.key, {
      value: row.value,
      expires: row.expiration === undefined ? null : row.expiration * 1000,
    });
  }
  const put = (key, value) => records.set(key, { value, expires: null });
  const orders = new Map(proof.orders.map((order) => [order.sessionID, order]));
  if (orders.size !== proof.orders.length) throw new Error('Duplicate purchase provenance');
  for (const order of proof.orders) {
    if (typeof order.sessionID !== 'string' || !order.sessionID.startsWith('cs_'))
      throw new Error('Invalid purchase provenance');
    if (
      order.plan === 'lifetime' &&
      typeof order.paymentIntent === 'string' &&
      order.paymentIntent.startsWith('pi_')
    )
      put(`order-payment:${order.sessionID}`, order.paymentIntent);
    else if (
      order.plan !== 'subscription' ||
      typeof order.subscriptionID !== 'string' ||
      !order.subscriptionID.startsWith('sub_')
    )
      throw new Error('Missing payment/subscription provenance');
  }
  const invoices = new Map();
  for (const invoice of proof.invoices) {
    if (
      typeof invoice.id !== 'string' ||
      !invoice.id.startsWith('in_') ||
      typeof invoice.subscriptionID !== 'string' ||
      typeof invoice.email !== 'string' ||
      !Number.isSafeInteger(invoice.periodEnd) ||
      invoice.periodEnd <= 0 ||
      !Number.isSafeInteger(invoice.amountPaid) ||
      invoice.amountPaid <= 0 ||
      !Array.isArray(invoice.payments) ||
      !invoice.payments.length ||
      invoices.has(invoice.id)
    )
      throw new Error('Invalid invoice provenance');
    const ids = new Set();
    let total = 0;
    for (const payment of invoice.payments) {
      if (
        typeof payment.id !== 'string' ||
        !payment.id.startsWith('pi_') ||
        ids.has(payment.id) ||
        !Number.isSafeInteger(payment.amountPaid) ||
        payment.amountPaid <= 0
      )
        throw new Error('Invalid invoice allocation');
      ids.add(payment.id);
      total += payment.amountPaid;
      put(
        `invoice-payment:${invoice.id}:import:${payment.id}`,
        JSON.stringify({
          paymentIntent: payment.id,
          amountPaid: payment.amountPaid,
          currency: invoice.currency ?? '',
        }),
      );
    }
    if (total < invoice.amountPaid) throw new Error('Incomplete invoice funding provenance');
    const fact = {
      id: invoice.id,
      subscriptionID: invoice.subscriptionID,
      email: invoice.email,
      periodEnd: invoice.periodEnd,
      amountPaid: invoice.amountPaid,
      currency: invoice.currency ?? '',
    };
    invoices.set(invoice.id, fact);
    put(`invoice:${invoice.id}`, JSON.stringify(fact));
    put(`subinvoice:${invoice.subscriptionID}:${invoice.id}`, invoice.id);
  }
  for (const refund of proof.refunds) {
    if (
      typeof refund.paymentIntent !== 'string' ||
      !refund.paymentIntent.startsWith('pi_') ||
      typeof refund.fullyRefunded !== 'boolean'
    )
      throw new Error('Invalid refund provenance');
    if (refund.fullyRefunded) put(`refund:${refund.paymentIntent}`, '1');
  }
  let unresolved = 0,
    licenses = 0;
  for (const [name, row] of records) {
    if (!/^(session|refresh|period):/.test(name)) continue;
    const parts = row.value.split('.');
    if (parts.length !== 2) throw new Error('Invalid historical license envelope');
    const body = Buffer.from(parts[0], 'base64url'),
      signature = Buffer.from(parts[1], 'base64url');
    if (!verify(null, body, publicKey, signature))
      throw new Error('Historical license signature does not match selected signer');
    const purchase = JSON.parse(body),
      plan = purchase.plan ?? 'lifetime';
    licenses++;
    if (
      !['curfew-plus', 'curfew-pro'].includes(purchase.product) ||
      !['lifetime', 'subscription'].includes(plan) ||
      typeof purchase.order_id !== 'string'
    )
      throw new Error('Invalid historical license product');
    const order = orders.get(purchase.order_id);
    if (!order || order.plan !== plan) {
      unresolved++;
      continue;
    }
    if (plan === 'subscription') {
      const invoice = [...invoices.values()].find(
        (invoice) =>
          invoice.subscriptionID === order.subscriptionID &&
          Date.parse(purchase.expires_at) === (invoice.periodEnd + 3 * 86400) * 1000,
      );
      if (!invoice || typeof purchase.refresh_token !== 'string' || !purchase.refresh_token) {
        unresolved++;
        continue;
      }
      put(`key-invoice:${hash(row.value)}`, invoice.id);
      put(`subidentity:${order.subscriptionID}`, purchase.refresh_token);
      put(`subsession:${order.subscriptionID}`, purchase.order_id);
      put(`period:${purchase.refresh_token}:${invoice.periodEnd}:${invoice.id}`, row.value);
    }
  }
  const receipt = JSON.stringify({
    version: 1,
    mode,
    namespaceID: namespace,
    snapshotSHA256: hash(snapshotBytes),
    provenanceSHA256: hash(proofBytes),
    records: records.size,
    licenses,
    unresolved,
  });
  const schema = await readFile(
    new URL('../web/worker/migrations/0001_license_store.sql', import.meta.url),
    'utf8',
  );
  const sourceKey = text('migration:source'),
    sourceValue = text(receipt);
  const closed = `EXISTS(SELECT 1 FROM curfew_license_meta WHERE id=1 AND ready=0)`;
  const matching = `NOT EXISTS(SELECT 1 FROM curfew_license_record WHERE key=${sourceKey} AND value<>${sourceValue})`;
  const statements = [
    schema,
    `INSERT OR IGNORE INTO curfew_license_record(key,value,expires_at) SELECT ${sourceKey},${sourceValue},NULL WHERE ${closed};`,
  ];
  for (const [key, row] of records)
    statements.push(
      `INSERT OR IGNORE INTO curfew_license_record(key,value,expires_at) SELECT ${text(key)},${text(row.value)},${row.expires ?? 'NULL'} WHERE ${closed} AND ${matching};`,
    );
  // D1 SQL imports do not support explicit BEGIN. Partial import stays closed;
  // an identical retry is additive and a different snapshot cannot mix in.
  const output = await open(option('--output'), 'wx', 0o600);
  try {
    await output.writeFile(statements.join('\n') + '\n');
  } finally {
    await output.close();
  }
  console.log(JSON.stringify({ records: records.size, licenses, unresolved, ready: false }));
  if (unresolved) process.exitCode = 2;
} catch (error) {
  console.error(error instanceof Error ? error.message : 'Import preparation failed');
  process.exitCode = 1;
}
