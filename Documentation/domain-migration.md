# Domain migration to thecurfew.app

The public website can move before the account services and native release. The
service cutover remains coordinated: users sign in again and reconnect Macs and
assistants. Local schedules, journals, device identities, encryption keys,
accounts and purchases remain. The old public website redirects permanently;
service endpoints retire only during the service cutover.

## Public website first

The public marketing frontend uses the native Astro build and the production
mode in `landing/hosting/cloudflare.config.ts`. Follow
[website operations](website.md#production-and-rollback): review successful main
website checks and the accepted staging output, build with native `cf build`,
inspect its prebuilt deployment dry-run, then obtain production cutover approval
before native `cf deploy`. There is no separate website preparation wrapper,
publication receipt format or Pages-only publishing workflow.

The marketing Worker's account fallback derives from the selected environment's
`accountPortal`. Production account entry stays on `thecurfew.app/account`,
owned by the account Worker. If that route reaches the marketing Worker instead,
it returns a noncached 503 rather than redirecting back to itself. Never use
`legacySiteOrigin` as an authentication destination. Staging retains its account
service binding and separate configured identity.

The marketing Worker delegates public documentation to the accepted Mintlify
upstream. A website-only deployment preserves service routes, provider
registrations and genuine signed appcast bytes. Unpublished installers and
purchases remain unavailable; a missing feed stays absent until the native
release owner publishes the accepted signed release.

Capture current managed domain associations, DNS, route ownership and native
deployment versions before cutover. Verify the canonical site, documentation, public redirects, account
entry and feed state after publication. Use native Worker deployment history
for code rollback and reverse only approved domain, DNS and route changes. Keep
recorded associations and DNS/routes available for explicit reversal. No fixed
recovery delay applies. Retiring provider resources is a separate authorized
operation. Keep the old public hostname as a permanent 308 redirect with matching
paths and query strings; retired service hosts and legacy authenticated endpoints return
410 without forwarding credentials or callback payloads. Do not retain a second
production account portal. Signed native publication and coordinated service
activation retain their existing release-owner workflows.

Managed Custom Domains use separate native API administration under approved
operator access, as described in [hostname ownership](website-domain-preparation.md).
Keep domain provisioning out of restricted Worker deployment configuration.
Pages is not a frontend publication or recovery dependency; retain the existing
account, coordinator and other service owners.

## Configuration ownership

`deployment/environments.json` is the source for deployable addresses. Run `node scripts/deployment-config.mjs generate` after an edit. It generates Swift endpoint profiles, native feed configuration, associated domains, public discovery files, and a commit/hash-bound artifact. CI retains the artifact as `curfew-deployment-configuration`; it is not committed because its source commit must identify the exact source revision. Backend builds require this artifact and independently pinned `CURFEW_CONFIGURATION_COMMIT` and `CURFEW_CONFIGURATION_SHA256`. The native release workflow regenerates and retains that artifact, and embeds its identity in `CurfewConfigurationCommit` and `CurfewConfigurationSHA256` in the app's Info.plist through an ignored generated build-identity configuration file.

Production, staging and local profiles are isolated. Production HTTPS origins cannot contain credentials, ports, paths, queries or fragments. Local HTTP is restricted to loopback. Relative website links and derived endpoint paths avoid duplicate configuration. Signing identities, schema identifiers, tool scopes and Keychain namespaces remain stable. OAuth resources and MCP origin schemas describe structure; server/native consumers enforce exact trusted environment identities.

`purchasePortalOrigin` optionally selects the website that serves purchase
confirmation and restoration; it defaults to `siteOrigin`. Staging uses the
protected frontend hostname independently of its account portal and passkey
identity. The configuration validator applies the same origin restrictions and
production/staging isolation to this field. Both native license deployment and
the recovery configuration renderer use it for emailed restoration links. Native
purchase entry and initial checkout confirmation also use the purchase website.

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

Build with `cf build --mode production`, validate with `cf deploy --prebuilt --mode production --dry-run --provision=false`, then deploy the same output. Preserve IDs and the `UserCoordinator` SQLite export. The static Astro renderer is separate from its small `landing/hosting` Worker packaging entry point, preventing cf framework detection from treating a static build as Worker Build Output. The pinned cf release applies forward D1 migrations with the existing database IDs and bookkeeping history. Wrangler remains for local/test configuration, generated types and live logs. Email Sending onboarding also retains the Cloudflare dashboard or Wrangler email commands because the pinned cf command catalog does not expose that service. Verify the selected zone and the resulting SPF, DKIM, DMARC and bounce records. These are explicit CLI beta exceptions.

## Cutover prerequisites

- Protocol 0.0.13 must be published to GitHub Packages and both consumers pinned to its matching tag/version.
- The domain must be delegated to the intended Cloudflare zone; DNS and valid TLS are required on every new host.
- Apple and Google callback/domain registrations and the native association document must match the new configuration.
- Verify the authenticated account sender and Stripe webhook/checkout/billing return configuration.
- Every existing passkey-only account needs a usable unused recovery code or a linked social sign-in method. Passkeys cannot be renamed to another RP ID.
- Prepare a signed/notarized new app and the new signed update feed. Do not widen staging/internal distribution.
- Export durable-data backups and capture the D1 Time Travel bookmark, resource identities, deployed versions and provider settings.

## Apply and verify

The backend's `domain:preflight`, `domain:dry-run`, `domain:apply`, and `domain:verify` commands use cf and refuse interactive authentication. Supply the exact configuration artifact/hash/commit, API token and account ID. Every production mutating phase validates the full readiness receipt before schema or deployment mutations. Apply repeats that validation immediately before revocation and requires `CURFEW_CUTOVER_READINESS`, a JSON receipt naming the configuration hash, backup bookmark, signed release URL and provider-verification timestamp from the past hour. The new backend must report that exact configuration and maintenance=true before revocation.

Enable maintenance, close sockets through authority fencing, apply the transactional revocation batch, wait for the fence outbox to drain, activate provider settings and new site/app release, verify live journeys, then disable maintenance. Checkpoints make a resumed apply non-destructive. Account data and encryption epochs are retained; obsolete sessions, tokens, consents, direct-unlock grants and pending commands cannot carry over. The native one-time migration deletes authorization keys only and prompts reconnection.

The protected backend workflow has five explicit phases. `audit` is read-only. `prepare` deploys closed maintenance, applies the idempotent authorization cutover and deploys the retained license artifact. `bootstrap` and `acceptance` keep maintenance enabled, require the matching completed checkpoint and drained fences before deployment, and never repeat revocation or deploy licensing. `resume` removes the exception after live acceptance. Every deployment consumes the prebuilt reviewed artifact with provisioning disabled.

For owner testing, supply `CURFEW_MAINTENANCE_ACCEPTANCE_POLICY` only as a protected environment secret. It is private operational configuration, separate from endpoint manifests, workflow inputs and release artifacts. It must bind the environment, exact configuration hash/source commit and current issue/expiry times. Bootstrap lasts at most ten minutes and selects the canonical email Apple actually verifies. Use the existing Apple sign-in plus authenticator path, complete normal AAL2 and recovery enrollment, then link Google through the ordinary protected account flow. Anonymous passkey aliases and Google-only first-account creation stay closed. Acceptance lasts at most one hour and pins the resulting Curfew user ID and linked Google account ID; it does not select access by a later editable email. Verify the provider-shared identity before enabling bootstrap.

The policy selects one principal and grants no authentication, assurance, scope, consent, device or recovery authority. Explicit HTTP admission follows transport limiting; all normal guards remain mandatory. Recovery, billing and command writes are owner-scoped and deadline-bound. Hibernatable sockets capture their original private deadline, close when idle at expiry and cannot extend their authority through policy renewal or old handoff reuse. Missing, malformed, mismatched or expired policy closes access automatically. CI writes exclusive mode-0600 inputs, rechecks the policy immediately before deployment and always removes the transient files. Prepare/resume explicitly deploy `disabled` rather than retaining a stale exception.

Staging uses its existing domains, database and provider assignments with a separately protected staging policy. Normal deployment remains the default; maintenance rehearsal is opt-in and requires confirmed isolated test data plus a fresh backup/provider/release receipt. Its workflow supplies only the policy secret and retains existing provider credentials. Stage checkpoint/fence checks select the staging database explicitly through cf. Rehearse before production enablement; source tests and dry-runs cannot stand in for provider callbacks, native reconnection, email, payments or physical-device acceptance.

Use the native production marketing Worker for the public apex. Verify its route ownership and TLS. Its Worker handles declared public redirects before docs/static handling. Keep account, API, callback and authenticated traffic with their service owner; do not claim legacy-host routing for the marketing Worker while it serves the account portal.

## Acceptance and rollback

The website pipeline validates the ordinary Worker and browser behavior and
seals static output against the shared configuration. The signed native release
workflow consumes those retained files without rebuilding Astro or the app.

After the candidate's acceptance gates pass, use the publication path matching
its actual provenance. For a hosted candidate, store the exact owner receipt as
the production environment secret `CURFEW_RELEASE_ACCEPTANCE_RECEIPT` and dispatch
`activate-production.yml` on main with its SHA-256, the successful candidate run,
and the successful main website run. Both runs and the current main/tag must
identify the same source revision.

For an owner-authorized local candidate, follow
[explicit local-build publication](RELEASE.md#explicit-local-build-publication).
Retain the real test logs, signing evidence and exact clean native source; record
local provenance without a hosted run ID. The reviewed publication source must
preserve all native inputs and consume the matching retained website and endpoint
artifact. Actual staging acceptance and every existing owner gate still apply.
Neither path permits a rebuilt or relabeled app to reuse old acceptance.

The receipt remains private, must match the candidate, and expires after one
hour. It is never published as a release asset. Readiness checks and signed bytes
do not establish device, provider or staging acceptance.

Activation requires valid website TLS, configuration-matched account/sync
services in maintenance, and the configuration-matched license issuer. It
publishes the exact signed DMG, feed and candidate identity to GitHub, then adds
the signed feed to a copy of the verified static output. Native `cf build`
packages that directory through the production `assetsDirectory` input, selected
with the absolute `CURFEW_WEBSITE_ASSETS_DIRECTORY` environment value. A prebuilt
dry-run and deployment both disable provisioning. The Worker configuration and
Mintlify bindings remain the ordinary production configuration.

A retry reuses matching public release assets and refuses changed bytes. Draft
retries use authenticated release discovery and read asset digests back by
release ID before publication. A failed site publication can retry the same
release without replacing assets or restoring revoked authorization. Final
checks require the exact live feed, public path/query-preserving 308, and
callback retirement without redirect during coordinated service activation.
These service-cutover requirements do not gate independent marketing releases.

Acceptance includes real passkey recovery/replacement, Apple/Google sign-in, transactional email, native callback and same-device reconnection, retained encrypted-data readability, a real assistant command with Mac receipt/enforcement, Stripe test webhook, license delivery/refresh, and a verified signed app update. Passing local checks or a homepage 200 does not establish these outcomes.

The cf Durable Object export conversion is one-way: Cloudflare retains the existing namespace, but subsequent rollbacks must use cf exports with the same Worker/export/resource identities. Roll back code and assets through that configuration; do not redeploy the legacy Wrangler migrations array.

Verify these journeys after activation and monitor authentication, recovery,
reconnection, billing, licensing and updates through the following day. Use
staging and Stripe Sandbox for synthetic acceptance; production verification must
respect the owner's current testing and billing limits. Keep the public redirect
indefinitely and service retirement responses only. Roll back
application/configuration versions against retained data if needed; never
resurrect revoked grants or overwrite post-cutover writes. Staging retains its
existing hosts. Unrelated Studio domains and support email addresses are unchanged.

## Provider inventory and candidate identity

Provider inspection uses the pinned native cf CLI under approved operator authentication. PR validation receives no production Cloudflare deployment credentials. Inspect each service and its permissions independently: Pages access does not establish Worker, DNS or database permission. Resolve missing access before an approved mutation and keep credentials and account data private.

The candidate retains both `environment-artifact.json` and `release-configuration.json`. Native `CurfewConfigurationSHA256` and candidate `configurationSHA256` identify the same endpoint artifact consumed by the backend. `releaseConfigurationSHA256` separately seals the resolved Sparkle public key and source file digests. Changing a configured domain requires no candidate code change; the resolved feed must match the approved manifest. Candidate retention does not activate the site, update feed, or service.
