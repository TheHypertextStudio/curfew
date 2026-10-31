import core from './core.js';
import { drainOutbox, transactionalRequest } from './transaction-store.js';
import { authenticateStripeWebhook } from './stripe.js';
import type { Env } from './types.js';

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    if ((JSON.parse(env.RETIRED_LICENSE_HOSTS || '[]') as string[]).includes(url.hostname))
      return core.fetch(request, env);
    if (request.method === 'OPTIONS') return core.fetch(request, env);
    if (path === '/health') {
      const response = await core.fetch(request, env);
      const body = (await response.json()) as Record<string, unknown>;
      let ready = false;
      try {
        ready =
          !!env.LICENSE_DB &&
          (
            await env.LICENSE_DB.prepare('SELECT ready FROM curfew_license_meta WHERE id=1').first<{
              ready: number;
            }>()
          )?.ready === 1;
      } catch {
        /* Missing schema is unavailable. */
      }
      body.license_storage = ready ? 'ready' : 'unavailable';
      if (!ready) body.status = 'unavailable';
      return new Response(JSON.stringify(body), {
        status: response.ok && ready ? 200 : 503,
        headers: response.headers,
      });
    }
    let event: Record<string, any> | undefined;
    if (request.method === 'POST' && path === '/') {
      const authenticated = await authenticateStripeWebhook(request.clone(), env);
      if (authenticated instanceof Response) return authenticated;
      event = authenticated;
    }
    return transactionalRequest(request, env, event);
  },
  async scheduled(_event: ScheduledController, env: Env): Promise<void> {
    await drainOutbox(env);
  },
};
