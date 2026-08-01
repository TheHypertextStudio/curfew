# License issuer single-path migration

## Decision

Curfew will have exactly one supported license-issuer implementation:
`web/worker/` plus `scripts/license-worker.mjs`. The historical root
`wrangler.toml`, `scripts/issue-license.ts`, and
`scripts/gen-license-keypair.sh` will be removed.

## Why

The legacy path mints the obsolete `curfew-pro` contract and signs the
base64url payload text. The current app verifier and tested Worker use the
`curfew-plus` envelope-v2 contract and sign exact UTF-8 JSON bytes. Keeping
both paths lets an operator deploy an issuer whose licenses the shipping app
will reject.

## Scope

- Remove the three obsolete root-level issuer artifacts.
- Replace all remaining documentation references with the reproducible
  `web/worker` template and `scripts/license-worker.mjs` commands.
- Keep the landing-page sale gate closed: this migration does not enable
  checkout or modify Stripe production configuration.
- Preserve the isolated workers.dev staging path and its separate KV namespace
  and secrets.

## Operator flow

1. Install locked Worker dependencies with `pnpm install --dir web
   --frozen-lockfile`.
2. Generate a keypair with `license-worker.mjs keygen` into a caller-owned
   mode-0600 path; commit only the public verifier as part of a separately
   reviewed app release.
3. Set only non-secret Worker identifiers in the shell, validate them, and
   render an untracked config from `web/worker/wrangler.toml.example`.
4. Bundle with the documented dry-run command, then deploy only from the
   rendered configuration in an authorized Cloudflare session.
5. Upload the matching `LICENSE_PRIVATE_KEY` and Stripe webhook secret through
   the secret store, verify `/health`, and prove test-mode delivery before
   opening checkout.

## Safety and rollback

- No private seed, Stripe secret, account ID, KV namespace ID, or payment link
  is committed.
- Production and staging stay isolated by rendered configuration, distinct
  worker names, KV namespaces, and secrets.
- A release already using the legacy issuer must not be treated as compatible
  with the current app. Rollback means restoring the previous signed app and
  matching external signer together, not redeploying the obsolete source into
  the current release path.

## Verification

- A regression test asserts that the obsolete root issuer files and legacy
  deployment references are absent.
- Existing Worker crypto, config-rendering, typecheck, and bootstrap tests
  remain green.
- Documentation search finds no legacy issuer command or `curfew-pro` rollout
  reference outside historical release notes, if any.
- Full Curfew unit tests, format, lint, and Debug build remain green.

