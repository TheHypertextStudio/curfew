# Website hostname ownership and recovery

## Frontend: Workers

`landing/hosting/cloudflare.config.ts` owns frontend Worker identity, assets
and bindings. `deployment/environments.json` owns shared marketing, account,
licensing, sync and native endpoints. Regenerate existing consumers with
`node scripts/deployment-config.mjs generate` after an approved edit.

Administer managed Custom Domains separately through Cloudflare's native API
using approved operator access. Read the existing account, zone, hostname and
Worker/environment association before an approved change; read back that exact
association and managed DNS afterward. Keep domain provisioning out of restricted
Worker deployment configuration and credentials. Preserve more-specific account,
coordinator and other service routes; a frontend domain change does not transfer
their ownership.

Use `pnpm deploy:worker:staging` or, after production authorization,
`pnpm deploy:worker:production`. Verify the intended hostname's native route
ownership, managed domain association, TLS, selected-version bindings and actual
serving Worker version. Follow
[website hosting](website.md) and [domain migration](domain-migration.md).
A successful deployment alone does not establish these outcomes.

PR validation receives no production Cloudflare deployment credentials. Use an
approved operator profile and the pinned native `cf` CLI for administration.
DNS and hosting retain separately approved access. Website changes do not
authorize account, license, signed-feed or service changes.

## Recovery and retirement

Retain the native deployment and DNS/route baselines privately. Roll back code
and assets through native Worker deployment history; reverse only explicitly
changed domain associations, routes and DNS fields. Version rollback does not
reverse routing.
Verify public DNS, HTTPS and the actual serving deployment after recovery.
No fixed observation or recovery delay is required.

Pages is not a frontend publication, preview or recovery dependency.
Production `/account` belongs to the canonical account Worker route. The marketing
fallback must use the configured production `accountPortal` and fail closed if
that same-origin route reaches it; never restore a redirect to the retired portal.
Legacy public-domain redirects remain separate from account entry. Preserve
licensing, sync, callbacks, sessions and provider registrations during recovery.
Do not attach the production frontend to Pages as normal setup or recovery.
