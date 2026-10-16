# License Worker bootstrap

The Curfew license issuer is an internal app-to-issuer contract, **envelope
v2**. It is not MCP, AI-host, or Curfew Sync traffic, so it is versioned and
tested in this repository rather than `curfew-protocols`.

The v2 payload is signed over its exact UTF-8 JSON bytes and contains
`email`, `product: "curfew-plus"`, `plan`, `order_id`, `issued_at`, and, for a
subscription, `expires_at` and `refresh_token`. The app accepts legacy
`curfew-pro` lifetime keys only for pre-release continuity. Do not change this
shape without updating the Worker and `LicenseEnvelopeContractTests` together.

## Fresh-clone bootstrap

Install only from the committed pnpm lockfile:

```sh
cd web
pnpm install --frozen-lockfile
pnpm test
pnpm typecheck
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

The committed `web/worker/wrangler.toml.example` has no account identifiers,
hostname, or secret. Export these non-secret values only in the operator shell:

```sh
export CURFEW_LICENSE_WORKER_NAME='example-worker-name'
export CURFEW_LICENSE_KV_NAMESPACE_ID='00000000000000000000000000000000'
export CURFEW_LICENSE_HOSTNAME='curfew-license.hypertext.studio'
export CURFEW_LICENSE_STRIPE_MODE='live'
node scripts/license-worker.mjs validate-config
node scripts/license-worker.mjs render-config --output /secure/user-owned/wrangler.toml
node scripts/license-worker.mjs dry-run --config /secure/user-owned/wrangler.toml
```

For an isolated staging Worker, use a separate KV namespace, secrets, and the
same approved Curfew hostname convention:

```sh
export CURFEW_LICENSE_WORKER_NAME='curfew-issue-license-staging'
export CURFEW_LICENSE_KV_NAMESPACE_ID='your-staging-kv-namespace-id'
export CURFEW_LICENSE_HOSTNAME='curfew-license-staging.hypertext.studio'
export CURFEW_LICENSE_STRIPE_MODE='test'
node scripts/license-worker.mjs render-config \
  --output /secure/user-owned/wrangler-staging.toml
```

The existing Stripe Test mode sandbox supports this integration. Use its
test-only products, prices, payment links and webhook endpoint, and keep that
webhook's signing secret on the staging Worker. Give the Worker a distinct
`LICENSE_PRIVATE_KEY` and KV namespace. Do not copy live keys or objects into
staging or change shared account settings during testing. A separate general
sandbox adds settings isolation and is optional for this existing integration.

`CURFEW_LICENSE_STRIPE_MODE` is required. The renderer permits `live` only for
`curfew-license.hypertext.studio` and requires `test` for other license hostnames.
It writes the runtime `STRIPE_MODE` binding. After signature verification, the
issuer requires the event's boolean `livemode` to match that binding before any
KV access, including event replay and historical index repair. Missing or invalid
configuration returns 503; missing, malformed or opposite-mode event flags return
400. Correct-mode events continue through the existing paid-purchase checks.

The guard's staging Worker Build succeeded at `e6fc60c9`; runtime mode still
requires read-back verification. For staging publication, save
`CURFEW_LICENSE_STRIPE_MODE=test` in that Worker's Build configuration and verify
the rendered runtime binding. Production configuration
and deployment require explicit owner direction; its eventual value is `live`.
Do not merge or push to a production auto-deployment branch while that stop
remains. Staging Build success does not establish the runtime mode; verify its
health field and the test-only webhook separately. Revert the code and renderer together
if rollback is needed; retain the separate KVs, signers and webhook secrets.

`GET /health` reports `stripe_mode` as exactly `test`, `live`, or `unconfigured`.
Only the first two runtime binding values are disclosed; missing or invalid
values are never echoed. This read-only response retains `Cache-Control:
no-store`, performs no purchase-store, email or rate-limit operation, and exposes
no credentials or purchase data. It includes the mode even when an unavailable
signer returns 503. The existing 200 status only establishes a configured signer;
an `unconfigured` mode still blocks webhook processing with 503. Require `test`
on staging before claiming its payment boundary is configured. Mode read-back
does not prove a checkout, signer pairing, inbox restoration, or build identity.
No build identity is reported because no authenticated version binding exists.
Reverting this diagnostic removes only the additive health field.

`validate-config` fails closed when any required field is absent or malformed.
`render-config` resolves the Worker entry point from this clone, so the
caller-selected output path does not change what Wrangler builds. `dry-run`
performs no deployment. To produce a dashboard-reviewable bundle without a
Cloudflare token, run from the Worker directory:

```sh
cd web/worker
pnpm exec wrangler deploy --dry-run \
  --config /secure/user-owned/wrangler.toml \
  --outdir /secure/user-owned/curfew-license-worker-bundle
```

Wrangler writes the bundled entry point at
`/secure/user-owned/curfew-license-worker-bundle/index.js`; its source map and
README are supporting local artifacts. The dashboard still requires separate
configuration of the `LICENSE_KV` binding, custom hostname, and encrypted
secrets. After an authorized deployment and secret upload, the read-only
endpoint check is:

```sh
node scripts/license-worker.mjs verify-endpoint --base-url https://license.example.com
```

Before opening checkout, separately verify a Stripe test event, successful
key delivery, subscription renewal, cancellation, and that the root
`landing/src/pages/index.astro` sale gate remains closed until this path is proven.

## Recorded staging proof

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
