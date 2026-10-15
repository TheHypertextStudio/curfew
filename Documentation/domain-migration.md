# Domain migration to thecurfew.app

The public website can move before the account services and native release. The
service cutover remains coordinated: users sign in again and reconnect Macs and
assistants. Local schedules, journals, device identities, encryption keys,
accounts and purchases remain. The old public website redirects permanently;
service endpoints retire only during the service cutover.

## Public website first

Dispatch `deploy-public-website.yml` on main to publish the exact successful
main website artifact independently of Apple provisioning or a native release.
The workflow verifies its complete byte tree, source/configuration identity,
active Pages domains and TLS through the pinned cf CLI. It retains the Pages
uploader exception and does not rebuild the website during publication.

This phase keeps website account links on the existing portal derived from
`legacySiteOrigin`, preserves the current signed appcast bytes if one exists,
and leaves a missing feed absent. Existing download links, service hostnames,
provider registrations, sessions and account Worker routes remain in place.
Only public Pages routes acquire the permanent path/query-preserving redirect.
The retained middleware runs with a public-phase binding in a small module
wrapper. Credential-bearing requests stay on the existing host; retirement
responses remain part of the later service activation. No credential payload
is redirected between hosts.
The selected documentation mode remains unchanged. No signed application or
GitHub release is created by this workflow.

After publication, verify the new canonical homepage, public redirects, retained
feed state and existing account access. The publication artifact records the
previous Pages deployment IDs for rollback. Restore that Pages deployment if
the public site fails; do not roll back account data or revoke authentication.
The later coordinated activation removes the wrapper, replaces these temporary account links with
the new portal and publishes the approved signed feed.

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

Build with `cf build --mode production`, validate with `cf deploy --prebuilt --mode production --dry-run --provision=false`, then deploy the same output. Preserve IDs and the `UserCoordinator` SQLite export. The static Astro renderer is separate from its small `landing/hosting` Worker packaging entry point, preventing cf framework detection from treating a static build as Worker Build Output. The pinned cf release applies forward D1 migrations with the existing database IDs and bookkeeping history. Wrangler remains for local/test configuration, generated types and live logs; Pages artifact publication retains its existing uploader. Email Sending onboarding also retains the Cloudflare dashboard or Wrangler email commands because the pinned cf command catalog does not expose that service. Verify the selected zone and the resulting SPF, DKIM, DMARC and bounce records. These are explicit CLI beta exceptions.

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
