import type { Env, LicenseStore } from './types.js';
import core from './core.js';
import { json } from './purchases.js';

type Row = { key: string; value: string; expires_at: number | null };
export class TransactionConflict extends Error {}

/** D1 queries use the primary (no replica session). The revision is captured
 * before every record read, including scans and read-only license responses. */
export class LicenseTransaction implements LicenseStore {
  private changes = new Map<string, Row | null>();
  private cache = new Map<string, Promise<Row | null>>();
  private revision: number | undefined;
  private readonly startedAt = Date.now();
  constructor(private readonly database: D1Database) {}

  async initialize(): Promise<void> {
    const meta = await this.database
      .prepare('SELECT revision,ready FROM curfew_license_meta WHERE id=1')
      .first<{ revision: number; ready: number }>();
    if (!meta || meta.ready !== 1) throw new Error('License migration is not ready');
    this.revision = meta.revision;
  }
  private async row(key: string): Promise<Row | null> {
    if (this.changes.has(key)) return this.changes.get(key) ?? null;
    if (!this.cache.has(key))
      this.cache.set(
        key,
        this.database
          .prepare('SELECT key,value,expires_at FROM curfew_license_record WHERE key=?')
          .bind(key)
          .first<Row>(),
      );
    const row = await this.cache.get(key)!;
    return this.changes.has(key) ? (this.changes.get(key) ?? null) : row;
  }
  async get(key: string): Promise<string | null> {
    const row = await this.row(key);
    return row && (row.expires_at === null || row.expires_at > this.startedAt) ? row.value : null;
  }
  async put(key: string, value: string, options?: { expirationTtl?: number }): Promise<void> {
    this.changes.set(key, {
      key,
      value,
      expires_at: options?.expirationTtl ? this.startedAt + options.expirationTtl * 1000 : null,
    });
  }
  async delete(key: string): Promise<void> {
    this.changes.set(key, null);
  }
  async list({ prefix = '', limit = 1000 }: { prefix?: string; limit?: number } = {}) {
    if (!Number.isInteger(limit) || limit < 1 || limit > 1000)
      throw new Error('Invalid license scan bound');
    const found = await this.database
      .prepare(
        'SELECT key,value,expires_at FROM curfew_license_record WHERE key>=? AND key<? AND (expires_at IS NULL OR expires_at>?) ORDER BY key LIMIT ?',
      )
      .bind(prefix, `${prefix}\uffff`, this.startedAt, limit + 1)
      .all<Row>();
    const rows = new Map(found.results.map((row) => [row.key, row]));
    for (const row of found.results)
      if (!this.cache.has(row.key)) this.cache.set(row.key, Promise.resolve(row));
    for (const [key, row] of this.changes)
      if (key.startsWith(prefix)) {
        if (row && (row.expires_at === null || row.expires_at > this.startedAt)) rows.set(key, row);
        else rows.delete(key);
      }
    const keys = [...rows.keys()].sort();
    return {
      keys: keys.slice(0, limit).map((name) => ({ name })),
      list_complete: keys.length <= limit,
    };
  }
  async commit(): Promise<void> {
    if (this.revision === undefined) throw new Error('Transaction not initialized');
    if (this.changes.size > 128) throw new Error('License write bound exceeded');
    const id = crypto.randomUUID();
    const statements = [
      this.database
        .prepare(
          `INSERT INTO curfew_license_guard(transaction_id,valid)
      SELECT ?,CASE WHEN EXISTS(SELECT 1 FROM curfew_license_meta WHERE id=1 AND revision=? AND ready=1) THEN 1 ELSE 0 END`,
        )
        .bind(id, this.revision),
    ];
    for (const [key, row] of this.changes)
      statements.push(
        row
          ? this.database
              .prepare(
                'INSERT INTO curfew_license_record(key,value,expires_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,expires_at=excluded.expires_at',
              )
              .bind(key, row.value, row.expires_at)
          : this.database.prepare('DELETE FROM curfew_license_record WHERE key=?').bind(key),
      );
    if (this.changes.size)
      statements.push(
        this.database.prepare('UPDATE curfew_license_meta SET revision=revision+1 WHERE id=1'),
      );
    statements.push(
      this.database.prepare('DELETE FROM curfew_license_guard WHERE transaction_id=?').bind(id),
    );
    try {
      await this.database.batch(statements);
    } catch (error) {
      if (String(error).includes('CHECK constraint failed') && String(error).includes('valid'))
        throw new TransactionConflict();
      throw error;
    }
  }
}

export async function atomic<T>(
  database: D1Database,
  action: (store: LicenseTransaction) => Promise<T>,
): Promise<T> {
  for (let attempt = 0; attempt < 16; attempt++) {
    const store = new LicenseTransaction(database);
    await store.initialize();
    const result = await action(store);
    try {
      await store.commit();
      return result;
    } catch (error) {
      if (!(error instanceof TransactionConflict)) throw error;
    }
  }
  throw new Error('License transaction contention');
}

type Outbox = { message: unknown; expiresAt: number; leaseUntil?: number };
/** Durable at-least-once delivery. Concurrent drains claim a short lease. A
 * crash after sending can repeat the same usable link, never create a new one. */
export async function drainOutbox(env: Env): Promise<void> {
  if (!env.LICENSE_DB) return;
  const now = Date.now();
  // D1 has no native KV TTL. Remove expired recovery secrets atomically with
  // the revision change so an in-flight read can never validate stale state.
  await env.LICENSE_DB.batch([
    env.LICENSE_DB.prepare(
      'UPDATE curfew_license_meta SET revision=revision+1 WHERE id=1 AND ready=1 AND EXISTS(SELECT 1 FROM curfew_license_record WHERE expires_at IS NOT NULL AND expires_at<=?)',
    ).bind(now),
    env.LICENSE_DB.prepare(
      'DELETE FROM curfew_license_record WHERE expires_at IS NOT NULL AND expires_at<=? AND EXISTS(SELECT 1 FROM curfew_license_meta WHERE id=1 AND ready=1)',
    ).bind(now),
  ]);
  if (!env.EMAIL) return;
  for (let count = 0; count < 10; count++) {
    const claimed = await atomic(env.LICENSE_DB, async (store) => {
      const entries = await store.list({ prefix: 'outbox:', limit: 100 });
      for (const { name } of entries.keys) {
        const value = await store.get(name);
        if (!value) continue;
        const message = JSON.parse(value) as Outbox;
        if (message.expiresAt <= Date.now()) {
          await store.delete(name);
          continue;
        }
        if ((message.leaseUntil ?? 0) > Date.now()) continue;
        message.leaseUntil = Date.now() + 60_000;
        await store.put(name, JSON.stringify(message), {
          expirationTtl: Math.max(1, Math.ceil((message.expiresAt - Date.now()) / 1000)),
        });
        return { name, message };
      }
      return null;
    });
    if (!claimed) return;
    try {
      await env.EMAIL.send(claimed.message.message as Parameters<SendEmail['send']>[0]);
      await atomic(env.LICENSE_DB, async (store) => {
        await store.delete(claimed.name);
      });
    } catch {
      return;
    } // Leave the durable lease for the scheduled retry.
  }
}

export async function transactionalRequest(
  request: Request,
  env: Env,
  authenticatedEvent?: Record<string, any>,
): Promise<Response> {
  if (!env.LICENSE_DB) return json({ error: 'license_storage_unavailable' }, 503);
  // Cache external rate-limit outcomes for this request, not each optimistic retry.
  const limits = new Map<string, Promise<{ success: boolean }>>();
  const limit = (binding: RateLimit | undefined, name: string): RateLimit | undefined =>
    binding && {
      limit: ({ key }: { key: string }) => {
        const id = `${name}:${key}`;
        if (!limits.has(id)) limits.set(id, binding.limit({ key }));
        return limits.get(id)!;
      },
    };
  try {
    const response = await atomic(env.LICENSE_DB, async (store) => {
      const transactionalEnv: Env = {
        ...env,
        LICENSE_KV: store,
        RESTORE_IP_LIMIT: limit(env.RESTORE_IP_LIMIT, 'ip'),
        RESTORE_EMAIL_LIMIT: limit(env.RESTORE_EMAIL_LIMIT, 'email'),
        EMAIL: env.EMAIL && {
          async send(message) {
            const entry: Outbox = { message, expiresAt: Date.now() + 15 * 60_000 };
            await store.put(`outbox:${crypto.randomUUID()}`, JSON.stringify(entry), {
              expirationTtl: 15 * 60,
            });
            return { messageId: 'queued' } as EmailSendResult;
          },
        },
      };
      return core.fetch(request.clone(), transactionalEnv, authenticatedEvent);
    });
    // A committed outbox is recoverable even if delivery or the request crashes.
    if (
      request.method === 'POST' &&
      new URL(request.url).pathname === '/license/restore' &&
      response.status === 202
    )
      await drainOutbox(env);
    return response;
  } catch {
    return json({ error: 'license_storage_unavailable' }, 503);
  }
}
