# Domain migration to thecurfew.app

Production moves as one cutover. Users sign in again and reconnect Macs and assistants. Local schedules, journals, device identities, encryption keys, accounts and purchases remain. The old public website redirects permanently; retired APIs return 410 without forwarding credentials.

## Configuration ownership

`deployment/environments.json` is the source for deployable addresses. Run `node scripts/deployment-config.mjs generate` after an edit. It generates Swift endpoint profiles, native feed configuration, associated domains, public discovery files, and a commit/hash-bound artifact. CI retains the artifact as `curfew-deployment-configuration`; it is not committed because its source commit must identify the exact source revision. Backend builds require this artifact and independently pinned `CURFEW_CONFIGURATION_COMMIT` and `CURFEW_CONFIGURATION_SHA256`. The native release workflow regenerates and retains that artifact, and embeds its identity in `CurfewConfigurationCommit` and `CurfewConfigurationSHA256` in the app's Info.plist through an ignored generated build-identity configuration file.

Production, staging and local profiles are isolated. Production HTTPS origins cannot contain credentials, ports, paths, queries or fragments. Local HTTP is restricted to loopback. Relative website links and derived endpoint paths avoid duplicate configuration. Signing identities, schema identifiers, tool scopes and Keychain namespaces remain stable. OAuth resources and MCP origin schemas describe structure; server/native consumers enforce exact trusted environment identities.

## Cloudflare CLI

Use the pinned `cf@1.0.0-beta.16`. Worker projects have explicit `cloudflare.config.ts`; never run cf automatic setup over an unmigrated Wrangler project. Use `cf cli search` then `cf schema` for resource operations. Queries contain generic resource descriptions, never identifying values or credentials. CI uses explicit account IDs and approved API-token credentials; Wrangler login is not reused.

Build with `cf build --mode production`, validate with `cf deploy --prebuilt --mode production --dry-run`, then deploy the same output. Preserve IDs and the `UserCoordinator` SQLite export. The static Astro renderer is separate from its small `landing/hosting` Worker packaging entry point, preventing cf framework detection from treating a static build as Worker Build Output. D1 forward migrations and live-log streaming retain Wrangler where required; Pages artifact publication retains its existing uploader. These are explicit CLI beta exceptions.

## Cutover prerequisites

- Protocol 0.0.13 must be published to GitHub Packages and both consumers pinned to its matching tag/version.
- The domain must be delegated to the intended Cloudflare zone; DNS and valid TLS are required on every new host.
- Apple and Google callback/domain registrations and the native association document must match the new configuration.
- Verify the authenticated account sender and Stripe webhook/checkout/billing return configuration.
- Every existing passkey-only account needs a usable unused recovery code or a linked social sign-in method. Passkeys cannot be renamed to another RP ID.
- Prepare a signed/notarized new app and the new signed update feed. Do not widen staging/internal distribution.
- Export durable-data backups and capture the D1 Time Travel bookmark, resource identities, deployed versions and provider settings.

## Apply and verify

The backend's `domain:preflight`, `domain:dry-run`, `domain:apply`, and `domain:verify` commands use cf and refuse interactive authentication. Supply the exact configuration artifact/hash/commit, API token and account ID. Apply also requires `CURFEW_CUTOVER_READINESS`, a JSON receipt naming the configuration hash, backup bookmark, signed release URL and provider-verification timestamp from the past hour. The new backend must report that exact configuration and maintenance=true before revocation.

Enable maintenance, close sockets through authority fencing, apply the transactional revocation batch, wait for the fence outbox to drain, activate provider settings and new site/app release, verify live journeys, then disable maintenance. Checkpoints make a resumed apply non-destructive. Account data and encryption epochs are retained; obsolete sessions, tokens, consents, direct-unlock grants and pending commands cannot carry over. The native one-time migration deletes authorization keys only and prompts reconnection.

Attach the new apex to the existing Pages project through `cf pages domains create`; verify its activation rather than creating only a DNS CNAME. The Pages middleware performs the old-site redirect before docs/static handling. Exclude API/callback/authenticated traffic from public redirects.

## Acceptance and rollback

Acceptance includes real passkey recovery/replacement, Apple/Google sign-in, transactional email, native callback and same-device reconnection, retained encrypted-data readability, a real assistant command with Mac receipt/enforcement, Stripe test webhook, license delivery/refresh, and a verified signed app update. Passing local checks or a homepage 200 does not establish these outcomes.

Monitor these journeys through the following day. Keep the public redirect indefinitely and service retirement responses only. Roll back application/configuration versions against retained data if needed; never resurrect revoked grants or overwrite post-cutover writes. Staging retains its existing hosts. Unrelated Studio domains and support email addresses are unchanged.

## Current execution blockers

The local environment has no Cloudflare API token/account selection or Stripe credential. Production recovery audit, zone/DNS/TLS changes, provider registration, sender verification, signing/notarization, production cutover and live acceptance therefore remain unverified. No production routing or account revocation has been performed by this change.
