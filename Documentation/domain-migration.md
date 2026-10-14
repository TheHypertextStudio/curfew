# Domain migration to thecurfew.app

Production moves as one cutover. Users sign in again and reconnect Macs and assistants. Local schedules, journals, device identities, encryption keys, accounts and purchases remain. The old public website redirects permanently; retired APIs return 410 without forwarding credentials.

## Configuration ownership

`deployment/environments.json` is the source for deployable addresses. Run `node scripts/deployment-config.mjs generate` after an edit. It generates Swift endpoint profiles, native feed configuration, associated domains, public discovery files, and a commit/hash-bound artifact. CI retains the artifact as `curfew-deployment-configuration`; it is not committed because its source commit must identify the exact source revision. Backend builds require this artifact and independently pinned `CURFEW_CONFIGURATION_COMMIT` and `CURFEW_CONFIGURATION_SHA256`. The native release workflow regenerates and retains that artifact, and embeds its identity in `CurfewConfigurationCommit` and `CurfewConfigurationSHA256` in the app's Info.plist through an ignored generated build-identity configuration file.

Production, staging and local profiles are isolated. Production HTTPS origins cannot contain credentials, ports, paths, queries or fragments. Local HTTP is restricted to loopback. Relative website links and derived endpoint paths avoid duplicate configuration. Signing identities, schema identifiers, tool scopes and Keychain namespaces remain stable. OAuth resources and MCP origin schemas describe structure; server/native consumers enforce exact trusted environment identities.

## Cloudflare CLI

License Worker builds also require `CURFEW_DEPLOYMENT_ARTIFACT`, independently
pinned `CURFEW_CONFIGURATION_COMMIT` and `CURFEW_CONFIGURATION_SHA256`. Its cf
configuration verifies that artifact before reading endpoints, retains the
existing account/Worker/KV identities, and records the shared provenance in
health response headers. CI tests the real cf configuration against alternate
domains and performs Worker tests/typecheck plus a build/prebuilt dry-run.
The license project owns its Vitest root and test discovery, including when
the backend pipeline checks out the app as a nested configuration source.
Before production activation, disable the independent license Worker Git build
so its legacy Wrangler command cannot race the coordinated cf deployment.
Preserve signing secrets; the pinned cf deployment retains existing secret
bindings. Roll back using the previous artifact and matching configuration,
never by creating a replacement namespace or signing key.

Use the pinned `cf@1.0.0-beta.16`. Worker projects have explicit `cloudflare.config.ts`; never run cf automatic setup over an unmigrated Wrangler project. Use `cf cli search` then `cf schema` for resource operations. Queries contain generic resource descriptions, never identifying values or credentials. CI uses explicit account IDs and approved API-token credentials; Wrangler login is not reused.

Build with `cf build --mode production`, validate with `cf deploy --prebuilt --mode production --dry-run`, then deploy the same output. Preserve IDs and the `UserCoordinator` SQLite export. The static Astro renderer is separate from its small `landing/hosting` Worker packaging entry point, preventing cf framework detection from treating a static build as Worker Build Output. D1 forward migrations and live-log streaming retain Wrangler where required; Pages artifact publication retains its existing uploader. Email Sending onboarding also retains the Cloudflare dashboard or Wrangler email commands because the pinned cf command catalog does not expose that service. Verify the selected zone and the resulting SPF, DKIM, DMARC and bounce records. These are explicit CLI beta exceptions.

## Cutover prerequisites

- Protocol 0.0.13 must be published to GitHub Packages and both consumers pinned to its matching tag/version.
- The domain must be delegated to the intended Cloudflare zone; DNS and valid TLS are required on every new host.
- Apple and Google callback/domain registrations and the native association document must match the new configuration.
- Verify the authenticated account sender and Stripe webhook/checkout/billing return configuration.
- Every existing passkey-only account needs a usable unused recovery code or a linked social sign-in method. Passkeys cannot be renamed to another RP ID.
- Prepare a signed/notarized new app and the new signed update feed. Do not widen staging/internal distribution.
- Export durable-data backups and capture the D1 Time Travel bookmark, resource identities, deployed versions and provider settings.

## Apply and verify

The backend's `domain:preflight`, `domain:dry-run`, `domain:apply`, and `domain:verify` commands use cf and refuse interactive authentication. Supply the exact configuration artifact/hash/commit, API token and account ID. Prepare and resume validate the full readiness receipt before schema or deployment mutations. Apply repeats that validation immediately before revocation and requires `CURFEW_CUTOVER_READINESS`, a JSON receipt naming the configuration hash, backup bookmark, signed release URL and provider-verification timestamp from the past hour. The new backend must report that exact configuration and maintenance=true before revocation.

Enable maintenance, close sockets through authority fencing, apply the transactional revocation batch, wait for the fence outbox to drain, activate provider settings and new site/app release, verify live journeys, then disable maintenance. Checkpoints make a resumed apply non-destructive. Account data and encryption epochs are retained; obsolete sessions, tokens, consents, direct-unlock grants and pending commands cannot carry over. The native one-time migration deletes authorization keys only and prompts reconnection.

Attach the new apex to the existing Pages project through `cf pages domains create`; verify its activation rather than creating only a DNS CNAME. The Pages middleware performs the old-site redirect before docs/static handling. Exclude API/callback/authenticated traffic from public redirects.

## Acceptance and rollback

The website pipeline compiles the Pages middleware before retention, executes
its redirect/retirement and documentation-mode tests, and seals the complete
static output against the shared configuration. Publication consumes those
retained files; it does not rebuild the app, website, or middleware.

After the candidate's acceptance gates pass, store the exact owner receipt as
the production environment secret `CURFEW_RELEASE_ACCEPTANCE_RECEIPT`. Dispatch
`activate-production.yml` on main with its SHA-256, the successful candidate run,
and the successful main website run. Both runs and the current main/tag must
identify the same source revision. The receipt remains private, must match the
candidate, and expires after one hour. It is never published as a release asset.

Activation requires both Pages hostnames to be active, valid new-site TLS, and
the configuration-matched account/sync services in maintenance plus the
configuration-matched license issuer. It publishes the exact signed DMG, feed,
and candidate identity to GitHub before uploading the retained Pages output
with bundling disabled from a fresh directory without checkout Functions, so
the uploader cannot compile source again. The pinned cf release explicitly
rejects legacy Pages publication, so this uploader retains the documented Wrangler exception; cf
still inspects custom domains. Existing documentation mode and project bindings
are retained. A retry reuses matching public release assets and refuses changed
bytes. Draft retries use authenticated release discovery and read asset digests
back by release ID before publication; a failed site publication can retry the
same release without replacing assets or restoring revoked authorization. Final checks require the exact live
feed, public path/query-preserving 308, and callback retirement without redirect.

Acceptance includes real passkey recovery/replacement, Apple/Google sign-in, transactional email, native callback and same-device reconnection, retained encrypted-data readability, a real assistant command with Mac receipt/enforcement, Stripe test webhook, license delivery/refresh, and a verified signed app update. Passing local checks or a homepage 200 does not establish these outcomes.

The cf Durable Object export conversion is one-way: Cloudflare retains the existing namespace, but subsequent rollbacks must use cf exports with the same Worker/export/resource identities. Roll back code and assets through that configuration; do not redeploy the legacy Wrangler migrations array.

Monitor these journeys through the following day. Keep the public redirect indefinitely and service retirement responses only. Roll back application/configuration versions against retained data if needed; never resurrect revoked grants or overwrite post-cutover writes. Staging retains its existing hosts. Unrelated Studio domains and support email addresses are unchanged.

## Provider inventory and candidate identity

The website PR workflow runs a read-only inventory using the existing repository Cloudflare token and pinned cf CLI. It reports each operation independently, so Pages access cannot be mistaken for Worker, DNS, or database permission. The output contains selected infrastructure metadata and secret names only. It never exports credentials or account data. Missing permission is a prerequisite to resolve before mutation.

The candidate retains both `environment-artifact.json` and `release-configuration.json`. Native `CurfewConfigurationSHA256` and candidate `configurationSHA256` identify the same endpoint artifact consumed by the backend. `releaseConfigurationSHA256` separately seals the resolved Sparkle public key and source file digests. Changing a configured domain requires no candidate code change; the resolved feed must match the approved manifest. Candidate retention does not activate the site, update feed, or service.
