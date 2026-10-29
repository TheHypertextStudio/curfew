import { base64url, base64urlDecode } from './crypto.js';
import type { Env, LicenseRequest } from './types.js';
import { keyIsFunded } from './funding.js';

const ticketSeconds = 15 * 60;
const tokenPattern = /^[A-Za-z0-9_-]{43}$/;

interface Ticket {
  expiresAt: number;
  sessionID?: string;
  emailHash?: string;
}

export async function digest(value: string): Promise<string> {
  return base64url(
    new Uint8Array(await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))),
  );
}

export async function indexPurchase(env: Env, email: string, sessionID: string): Promise<void> {
  const hash = await digest(email.trim().toLowerCase());
  await env.LICENSE_KV.put(`purchase:${hash}:${sessionID}`, sessionID);
}

async function ticket(env: Env, owner: Omit<Ticket, 'expiresAt'>): Promise<string> {
  const token = base64url(crypto.getRandomValues(new Uint8Array(32)));
  await env.LICENSE_KV.put(
    `activation:${await digest(token)}`,
    JSON.stringify({
      ...owner,
      expiresAt: Date.now() + ticketSeconds * 1000,
    }),
    { expirationTtl: ticketSeconds },
  );
  return token;
}

interface LicensePayload {
  order_id: string;
  plan: 'lifetime' | 'subscription';
  email: string;
  refresh_token?: string;
  expires_at?: string;
}

export function payload(key: string): LicensePayload | null {
  try {
    const value = JSON.parse(
      new TextDecoder('utf-8', { fatal: true }).decode(base64urlDecode(key.split('.')[0])),
    );
    const plan = value.plan ?? 'lifetime';
    if (
      typeof value.email !== 'string' ||
      !(
        value.product === 'curfew-plus' ||
        (value.product === 'curfew-pro' && plan === 'lifetime')
      ) ||
      !(plan === 'lifetime' || plan === 'subscription')
    )
      return null;
    return { ...value, plan };
  } catch {
    return null;
  }
}

export async function currentKey(env: Env, sessionID: string): Promise<string | null> {
  const key = await env.LICENSE_KV.get(`session:${sessionID}`);
  if (!key) return null;
  const token = payload(key)?.refresh_token;
  return token
    ? currentSubscriptionKey(env, token, key)
    : (await keyIsFunded(env, key, 'lifetime', payload(key)?.order_id ?? sessionID))
      ? key
      : null;
}

export async function currentSubscriptionKey(
  env: Env,
  token: string,
  fallback?: string,
): Promise<string | null> {
  // Invoice periods are immutable. Concurrent webhook completions may replace
  // a convenience pointer out of order, but cannot erase a later paid period.
  const periods = await env.LICENSE_KV.list({ prefix: `period:${token}:`, limit: 1000 });
  if (!periods.list_complete) return null;
  const candidates = [
    fallback,
    await env.LICENSE_KV.get(`refresh:${token}`),
    ...(await Promise.all(periods.keys.map(({ name }) => env.LICENSE_KV.get(name)))),
  ];
  const funded = await Promise.all(
    [...new Set(candidates)].map(async (key) => {
      if (!key) return null;
      const purchase = payload(key);
      return purchase?.plan === 'subscription' &&
        purchase.refresh_token === token &&
        Number.isFinite(Date.parse(purchase.expires_at ?? '')) &&
        (await keyIsFunded(env, key, purchase.plan, purchase.order_id))
        ? key
        : null;
    }),
  );
  return (
    funded
      .filter((key): key is string => key !== null)
      .sort(
        (a, b) => Date.parse(payload(b)!.expires_at!) - Date.parse(payload(a)!.expires_at!),
      )[0] ?? null
  );
}

async function restoredKey(env: Env, emailHash: string): Promise<string | null> {
  // Each paid order gets its own index entry, avoiding a read/modify/write race
  // between purchases. Bound reads; an exceptional >100-order inbox needs support.
  const purchases = await env.LICENSE_KV.list({ prefix: `purchase:${emailHash}:`, limit: 100 });
  if (!purchases.list_complete) return null;
  const keys = (
    await Promise.all(
      purchases.keys.map(async ({ name }) => {
        const sessionID = await env.LICENSE_KV.get(name);
        return sessionID ? currentKey(env, sessionID) : null;
      }),
    )
  ).filter((key): key is string => key !== null);
  const lifetime = keys.find((key) => payload(key)?.plan === 'lifetime');
  if (lifetime) return lifetime;
  return (
    keys
      .filter(
        (key) =>
          payload(key)?.plan === 'subscription' &&
          Number.isFinite(Date.parse(payload(key)?.expires_at ?? '')),
      )
      .sort(
        (a, b) => Date.parse(payload(b)!.expires_at!) - Date.parse(payload(a)!.expires_at!),
      )[0] ?? null
  );
}

export async function purchaseRequest(request: LicenseRequest, env: Env): Promise<Response> {
  const body = await smallJSON(request);
  if (!body) return json({ error: 'invalid_request' }, 400);
  switch (new URL(request.url).pathname) {
    case '/license/activation': {
      const sessionID = body.session_id;
      if (typeof sessionID !== 'string' || !/^cs_[A-Za-z0-9_]{1,200}$/.test(sessionID)) {
        return json({ error: 'invalid_session' }, 400);
      }
      const key = await currentKey(env, sessionID);
      if (!key) return json({ error: 'purchase_pending' }, 404);
      return json({ license_key: key, activation_token: await ticket(env, { sessionID }) });
    }
    case '/license/redeem': {
      if (typeof body.token !== 'string' || !tokenPattern.test(body.token))
        return json({ error: 'invalid_token' }, 400);
      const stored = await env.LICENSE_KV.get(`activation:${await digest(body.token)}`);
      if (!stored) return json({ error: 'link_unavailable' }, 404);
      const owner = JSON.parse(stored) as Ticket;
      if (!Number.isFinite(owner.expiresAt) || owner.expiresAt <= Date.now())
        return json({ error: 'link_expired' }, 410);
      const key = owner.sessionID
        ? await currentKey(env, owner.sessionID)
        : owner.emailHash
          ? await restoredKey(env, owner.emailHash)
          : null;
      // Tickets remain usable until expiry so browser scanners, retries, and a
      // second app delivery cannot consume a person's purchase recovery link.
      return key ? json({ license_key: key }) : json({ error: 'purchase_not_found' }, 404);
    }
    case '/license/restore':
      return restore(request, body, env);
    default:
      return json({ error: 'not_found' }, 404);
  }
}

async function restore(
  request: LicenseRequest,
  body: Record<string, unknown>,
  env: Env,
): Promise<Response> {
  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  if (email.length > 254 || !/^[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+$/.test(email))
    return json({ error: 'invalid_email' }, 400);
  if (
    !env.EMAIL ||
    !env.RESTORE_EMAIL_FROM ||
    !env.PURCHASE_PORTAL_URL ||
    !env.RESTORE_IP_LIMIT ||
    !env.RESTORE_EMAIL_LIMIT
  ) {
    return json({ error: 'restore_unavailable' }, 503);
  }
  const origin = new URL(env.PURCHASE_PORTAL_URL);
  if (
    origin.protocol !== 'https:' &&
    !(origin.protocol === 'http:' && origin.hostname === 'localhost')
  ) {
    return json({ error: 'restore_unavailable' }, 503);
  }
  const emailHash = await digest(email);
  const ip = request.headers.get('CF-Connecting-IP');
  if (
    !ip ||
    !(await env.RESTORE_IP_LIMIT.limit({ key: await digest(ip) })).success ||
    !(await env.RESTORE_EMAIL_LIMIT.limit({ key: emailHash })).success
  )
    return json({ error: 'too_many_requests' }, 429);
  const token = await ticket(env, { emailHash });
  const link = `${origin.origin}/restore#token=${token}`;
  try {
    // Send the same proof-of-inbox link whether or not a purchase exists. Only
    // its holder can discover that, and neither response nor email has a key.
    await env.EMAIL.send({
      to: email,
      from: { email: env.RESTORE_EMAIL_FROM, name: 'Curfew' },
      subject: 'Restore your Curfew Plus purchase',
      text: `Open this link to restore Curfew Plus:\n${link}\n\nThis link expires in 15 minutes. If you didn't request it, ignore this email.`,
      html: `<p><a href="${link}">Restore Curfew Plus</a></p><p>This link expires in 15 minutes. If you didn't request it, ignore this email.</p>`,
    });
  } catch {
    return json({ error: 'restore_unavailable' }, 503);
  }
  return json({ status: 'check_email' }, 202);
}

async function smallJSON(request: LicenseRequest): Promise<Record<string, unknown> | null> {
  if (!request.headers.get('Content-Type')?.startsWith('application/json')) return null;
  const reader = request.body?.getReader();
  if (!reader) return null;
  let length = 0;
  let text = '';
  const decoder = new TextDecoder();
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    length += value.byteLength;
    if (length > 4096) {
      await reader.cancel();
      return null;
    }
    text += decoder.decode(value, { stream: true });
  }
  try {
    const value: unknown = JSON.parse(text + decoder.decode());
    return value !== null && typeof value === 'object' && !Array.isArray(value)
      ? (value as Record<string, unknown>)
      : null;
  } catch {
    return null;
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
      'Referrer-Policy': 'no-referrer',
    },
  });
}
