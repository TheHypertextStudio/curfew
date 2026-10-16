# Website hostname ownership and recovery

## Frontend: Workers

Frontend hostname setup belongs to `landing/hosting/cloudflare.config.ts` and
native Worker deployment. `deployment/environments.json` owns shared marketing,
account, licensing, sync and native endpoints. Regenerate existing consumers
with `node scripts/deployment-config.mjs generate` after an approved edit.

Use `pnpm deploy:worker:staging` or, after production authorization,
`pnpm deploy:worker:production`. Verify the intended hostname's native route
ownership, TLS, bindings and actual serving Worker version. Follow
[website hosting](website.md) and [domain migration](domain-migration.md).
A successful deployment alone does not establish these outcomes.

PR validation receives no production Cloudflare deployment credentials. Use an
approved operator profile and the pinned native `cf` CLI for administration.
DNS and hosting retain separately approved access. Website changes do not
authorize account, license, signed-feed or service changes.

## Recovery and retirement

Retain the native deployment and DNS/route baselines privately. Roll back code
and assets through native Worker deployment history; reverse only explicitly
changed routes and DNS fields. Version rollback does not reverse routing.
Verify public DNS, HTTPS and the actual serving deployment after recovery.
No fixed observation or recovery delay is required.

Pages is no longer a frontend publication or preview target. Removing its
source tooling does not delete provider resources or authorize domain changes.
The legacy account portal remains an active dependency of production `/account`;
retain its serving host and resources until an independently approved service
migration replaces them. Preserve licensing, sync, callbacks, sessions and
provider registrations. Do not attach the production frontend to Pages as
normal setup or recovery.
