# License Worker bootstrap

The Curfew license issuer is an internal app-to-issuer contract, **envelope
v2**. It is not MCP, AI-host, or Curfew Sync traffic, so it is versioned and
tested in this repository rather than `curfew-protocols`.

The v2 payload is signed over its exact UTF-8 JSON bytes and contains
`email`, `product: "curfew-plus"`, `plan`, `order_id`, `issued_at`, and, for a
subscription, `expires_at` and `refresh_token`. The app accepts legacy
`curfew-pro` lifetime keys only for pre-release continuity. Do not change this
shape without updating the Worker and `LicenseEnvelopeContractTests` together.

## Native deployment sender

The native license configuration derives both `RESTORE_EMAIL_FROM` and the
email binding's sole allowed sender from the selected deployment artifact's
`recoveryEmailFrom`. Both configured environments use `accounts@thecurfew.app`;
their portals, resources, credentials, and Stripe modes remain separate. The
sender and its allowlist must stay paired
with the environment's portal, resources, and Stripe mode.

This changes the address used for restore email when the reviewed configuration
is deployed. It does not change purchase records, license keys, rate limits, or
payment configuration. Before deployment, verify the selected sender's existing
provider authorization; a successful local build or dry-run sends no email and
does not establish delivery. Regression checks evaluate both the pinned
production/staging addresses and a changed artifact sender to detect hardcoded
fallbacks. Roll back the source/configuration together if necessary, preserving
the environment boundaries and authorized sender restriction.

## Fresh-clone bootstrap

Install only from the committed pnpm lockfile:

```sh
pnpm --dir web install --frozen-lockfile
pnpm --dir web test
pnpm --dir web typecheck
```

Generate a pair only when an authorized operator is ready. This command prints
only the standard-base64 public key, and writes the base64url 32-byte private
seed to the explicit user-owned path at mode `0600`; it refuses overwrites.

```sh
node scripts/license-worker.mjs keygen \
  --private-key-file /secure/user-owned/curfew-license-private.seed \
  --public-key-file /secure/user-owned/curfew-license-public.base64
```

Commit only the resulting public key after replacing the app's public-key
configuration. Set the private seed as the Worker `LICENSE_PRIVATE_KEY` secret
through an authorized secret-management session; never place it in a file,
environment dump, issue, or commit.

## Rotation boundary

The app artifact and Worker secret form one signing boundary: deploy a Worker
configured with the new `LICENSE_PRIVATE_KEY` before distributing an app that
embeds its matching public key. A newly rotated app intentionally rejects keys
from the prior signer. Keep the prior key material available only in the
operator's approved secret store until the pre-release transition is complete;
do not commit either private seed or add it to repository configuration.
If a seed is displayed, logged, or otherwise exposed, discard it and generate a
new pair. Update the app verifier and Worker secret together before distributing
the next app artifact; do not keep using the exposed signer.

## Local config and safe verification

Deploy with the pinned native `cf` CLI and
`web/worker/cloudflare.config.ts`. It consumes the same immutable endpoint
artifact as the app, website, and account service. A rendered Wrangler file is
not an input to `cf build` or `cf deploy`. The legacy renderer remains a local
configuration utility, not the deployment path for this migration.

Use the reviewed `environment-artifact.json` through
`CURFEW_DEPLOYMENT_ARTIFACT`, with independently pinned
`CURFEW_CONFIGURATION_COMMIT` and `CURFEW_CONFIGURATION_SHA256`. Select the
approved Cloudflare account and existing profile or protected runner credential.
Keep credentials out of source, command arguments, and build output.

For staging, set `CURFEW_LICENSE_WORKER_NAME` to the existing
`curfew-issue-license-staging` Worker and `CURFEW_LICENSE_KV_NAMESPACE_ID` to its
existing namespace from inventory. The selected artifact derives
`license-staging.thecurfew.app`, `https://staging.thecurfew.app`, and the canonical
sender. It sets Stripe mode to `test` and restricts the email binding to that
sender. Production selects its existing Worker and KV, `license.thecurfew.app`,
`https://thecurfew.app`, and Stripe mode `live`. Never substitute production
resources or credentials for staging.

From the repository root, build and inspect staging without deploying:

```sh
pnpm --dir web/worker exec cf build --mode staging
pnpm --dir web/worker exec cf deploy --prebuilt --mode staging --dry-run --provision=false
```

Inspect the resource identities, hostname ownership, sender allowlist, portal,
mode, and retained secrets before deployment. During the authorized cutover,
deploy that same accepted output with `cf deploy --prebuilt --mode staging --provision=false`;
do not rebuild it or provision replacement storage. Production
uses the controlled backend and release sequence in
[production promotion](production-domain-promotion.md), with the matching
production artifact. Keep legacy independent Git-build publication disabled.

For a domain change, retain the existing signers, namespace, purchases, refresh
records, and webhook idempotency. Change only the approved endpoints and provider
registrations. Verify sending authority, the exact From allowlist, and Apple relay
acceptance before email delivery tests. Use the existing Stripe Sandbox's
separate products, prices, keys, and webhook secrets; do not copy live objects or
change production billing settings to obtain staging evidence.

After signature verification, the issuer requires each event's boolean `livemode`
to match its configured mode before any KV access, including replay and historical
index repair. Missing configuration returns 503; malformed or opposite-mode
flags return 400. Correct-mode events retain the paid-purchase checks.

`GET /health` reports `stripe_mode` as `test`, `live`, or `unconfigured` without
purchase-store, email, or rate-limit operations. It may return 503 if the signer
is unavailable. Configured `x-curfew-configuration` and
`x-curfew-configuration-commit` headers identify the declared endpoint artifact;
they do not prove checkout, sender delivery, native restoration, or signed-app
acceptance. Require `test` on staging and verify its actual deployment identities
through `cf` before using the health response as payment-boundary evidence.

The existing read-only endpoint check is:

```sh
node scripts/license-worker.mjs verify-endpoint --base-url https://license-staging.thecurfew.app
```

Separately accept Sandbox checkout, webhook delivery, key delivery, renewal,
cancellation, refresh, and browser-to-app restoration on the new hosts. Preserve
the landing sale gate until the separate production acceptance and billing
authorization are complete. Roll back code/configuration against retained data
without discarding later writes, purchases, or revoked authority.

## Recorded staging proof

This historical proof does not establish acceptance of a later configuration,
new staging hosts, or a new signed application.

On 2026-08-01, the isolated staging configuration was exercised from the
Hypertext Studio Stripe **Sandbox** only. A dedicated `$1` staging payment link
used Stripe's `4242` test card; the resulting `checkout.session.completed` and
`invoice.paid` webhook deliveries returned HTTP `200`, and a follow-up
`GET /license?session_id=...` returned a license envelope. The staging webhook
secret was rotated before the proof and is distinct from production.

This is evidence for the staging boundary, not authorization to expose a
production checkout. Keep the root landing sale gate closed until the separate
production Worker, Stripe webhook, signing, and installed-app checks are
completed.
