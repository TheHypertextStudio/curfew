# Website hostname ownership and retained Pages rollback

## Current frontend: Workers

New and current frontend hostname setup belongs to
`landing/hosting/cloudflare.config.ts` and native Worker deployment. Review
`deployment/environments.json` before changing origins; the shared configuration
also supplies native and backend endpoints. Regenerate its existing consumers
with `node scripts/deployment-config.mjs generate` after an approved edit.

Use the existing `pnpm deploy:worker:staging` or, after separate production
approval, `pnpm deploy:worker:production` command. Verify the intended hostname's
native route/domain ownership, TLS, bindings and actual serving Worker version.
Follow [website hosting](website.md) and [domain migration](domain-migration.md)
for readiness, cutover approval and recovery. A successful deployment alone does
not establish those outcomes. Do not attach a new production frontend hostname
to Pages as part of normal setup.

PR validation receives no production Cloudflare deployment credentials. Use an
approved operator profile and the repository's pinned native `cf` CLI for provider
administration. DNS and hosting administration retain their separately approved
access; do not expand credentials to combine operations. Website changes do not
authorize account, license, signed-feed or service changes.

## Record the retained Pages baseline

Keep the existing `curfew-landing` deployment and its recorded domains through
the agreed recovery window. Inspect them without changing routing:

```sh
pnpm exec cf pages domains list --project-name curfew-landing
```

Set `retained_hostname` to the exact existing hostname from the Pages rollback
baseline, then read its status:

```sh
pnpm exec cf pages domains get "$retained_hostname" --project-name curfew-landing
```

Retain the native deployment and DNS/route baselines with the existing Pages
artifact. The current Worker hostname is not a default Pages attachment target.
Never remove the old public redirect hostname as part of migration cleanup.

## Restore a recorded Pages domain only for approved rollback

Only an approved rollback may restore a specifically retained Pages domain that
is now absent. Confirm the recorded hostname, project and intended DNS/route
reversal before previewing its restoration:

```sh
: "${retained_hostname:?Set the exact hostname from the approved Pages rollback baseline}"
pnpm exec cf pages domains create curfew-landing --name "$retained_hostname" --dry-run
```

After that rollback is approved, restore only the recorded attachment and read
its status:

```sh
pnpm exec cf pages domains create curfew-landing --name "$retained_hostname"
pnpm exec cf pages domains get "$retained_hostname" --project-name curfew-landing
```

An existing attachment needs only the read operation. Attachment does not publish
the retained artifact or restore DNS/Worker route ownership; follow the approved
rollback plan for those operations. Pending status can persist until DNS and
certificate validation finish. Verify public DNS, HTTPS and the actual serving
deployment before treating restoration as accepted. If attachment fails, inspect
status before retrying because the provider may already have accepted it.
