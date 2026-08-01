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
pnpm install --dir web --frozen-lockfile
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

The committed `web/worker/wrangler.toml.example` has no account identifiers,
hostname, or secret. Export these non-secret values only in the operator shell:

```sh
export CURFEW_LICENSE_WORKER_NAME='example-worker-name'
export CURFEW_LICENSE_KV_NAMESPACE_ID='00000000000000000000000000000000'
export CURFEW_LICENSE_HOSTNAME='license.example.com'
node scripts/license-worker.mjs validate-config
node scripts/license-worker.mjs render-config --output /secure/user-owned/wrangler.toml
node scripts/license-worker.mjs dry-run --config /secure/user-owned/wrangler.toml
```

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
`landing/index.html` sale gate remains closed until this path is proven.
