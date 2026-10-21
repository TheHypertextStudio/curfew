# Promote verified Curfew staging to production

Promotion selects the production profile from the reviewed shared configuration,
deploys the accepted artifacts, and resumes the account service after acceptance.
Staging remains a separate environment. A successful staging deployment does not
authorize a production deployment, enable sales, or publish an installer.

Use this sequence with the [domain migration](domain-migration.md),
[native release](RELEASE.md), and [website operations](website.md) runbooks.
Keep execution identities, credentials, receipts, and outstanding operational
limitations in the private acceptance ledger rather than this document.

## Inputs that must agree

- Pin the reviewed app/configuration commit, backend commit, and clean publication
  commit. Generate `deployment/generated/environment-artifact.json` from that
  configuration source. Independently pin `CURFEW_CONFIGURATION_COMMIT` and
  `CURFEW_CONFIGURATION_SHA256`; supply the exact artifact through
  `CURFEW_DEPLOYMENT_ARTIFACT` to the backend and license builds.
- Retain the matching website assets, website build seal, signed `0.0.x` candidate,
  appcast, release configuration, notarization evidence, and actual quality logs.
  Use their original provenance. A local build has no hosted candidate run ID.
- Verify the production Worker, database, Durable Object namespace, license KV,
  signing keys, provider identities, and approved Cloudflare account independently
  of staging. Keep existing resource IDs and forward migration history.
- Prepare a fresh private cutover-readiness receipt containing
  `configurationHash`, `databaseBackupBookmark`, `signedReleaseURL`, and
  `providersVerifiedAt`. Provider verification must be within the preceding hour.
  Set `CURFEW_CUTOVER_READINESS` to its private file for the operator commands.

The whole endpoint manifest is hashed, including staging. Changing staging
addresses changes shared provenance even if production addresses stay identical.
Refresh the signed candidate when native source, generated endpoints, entitlements,
or the deployment manifest changes. Do not relabel an older app or weaken source
parity checks to make it admissible.

## Acceptance before promotion

The private ledger must distinguish source checks, deployment checks, and actual
user journeys. Missing access or an unavailable foreground interaction leaves its
acceptance item open; tests and configured credentials do not close it.

| Gate                  | Required evidence                                                                                                                                                                         |
| --------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Protected staging     | Valid TLS on each configured staging host; equivalent internal-access policy installed and read back before exposure; retained D1, KV, and Durable Object identities                      |
| Identity and recovery | Exact Apple/Google callbacks and account association document; normal Apple/authenticator onboarding, Google linking, usable recovery, and replacement passkeys for the new staging RP ID |
| Native and assistant  | Matching Dev endpoints and associated domains; same-device reconnection, retained encrypted-data readability, and an assistant command received and enforced by that Mac                  |
| Licensing             | Stripe Sandbox checkout/webhook/renewal behavior, transactional email, license restoration, and the browser-to-app handoff; distinguish manual license entry from callback delivery       |
| Production candidate  | Separate signed Release app with production identities and endpoints, notarization/Gatekeeper checks, retained-data upgrade acceptance, and matching signed feed                          |
| Operations            | Recoverable backups, recovery-ready existing accounts, reviewed authority migration/checkpoint state, rollback procedure, and available monitoring coverage                               |

Dev and Release use distinct bundle, helper, Keychain, and service identities.
Changing a runtime environment variable does not convert the Dev app into the
production release. Passkeys are bound to their RP ID and do not transfer between
staging and production. Preserve existing device and encryption material through
the normal authorization-only migration and reconnection path.
Verify production provider callbacks, mail-sending authority, and associated
domains separately; do not copy staging credentials or registrations into production.

## Minimal controlled sequence

1. **Audit without activation.** In `curfew-sync`, use the protected
   `deploy-production.yml` workflow with `phase=audit`, `configuration_commit`,
   and `configuration_sha256`. With an explicitly selected account and one
   approved authentication source, the existing operator checks are:

   ```sh
   CURFEW_DEPLOYMENT_MODE=production pnpm domain:preflight
   CURFEW_DEPLOYMENT_MODE=production pnpm domain:dry-run
   ```

   Configure `CURFEW_CLOUDFLARE_PROFILE` for the existing CLI profile or
   `CLOUDFLARE_API_TOKEN` for the runner, never both. These commands require the
   pinned artifact and `CLOUDFLARE_ACCOUNT_ID`. Stop for accounts without a usable
   recovery path, identity drift, missing provider access, or incomplete backups.

2. **Prepare production in maintenance.** Select `phase=prepare` only when the
   selected configuration needs its authorization cutover. The workflow validates
   readiness, applies forward database migrations, deploys the closed backend,
   applies the checkpointed authorization migration, drains authority fences,
   and deploys the retained license artifact. For an already completed matching
   checkpoint, verify it and continue without repeating revocation. A different
   artifact hash requires a new readiness assessment.

   The protected workflow, or its existing authorized local execution path,
   builds with pinned `cf` and deploys the same prebuilt bytes:

   ```sh
   pnpm exec cf build --mode production
   pnpm exec cf deploy --prebuilt --mode production --dry-run --provision=false
   ```

   Build maintenance phases with `CURFEW_MAINTENANCE=true`. A build with the
   default value is not a closed preparation artifact. Preserve secrets and
   storage bindings; do not provision replacement resources or rebuild between
   the accepted dry-run and deployment.

3. **Complete controlled owner acceptance.** If needed, use the existing
   `bootstrap` and `acceptance` phases with the matching private, bounded owner
   policy. They retain maintenance and require completed revocation and drained
   fences; they do not rerun the cutover. Normal authentication and assurance
   remain mandatory. Keep synthetic sign-in, recovery, command, and payment
   testing in staging and Stripe Sandbox; respect the release owner's production
   testing limits.

4. **Publish only after the release gate is satisfied.** Retain a private owner
   receipt less than one hour old and bound to the exact candidate, with the
   required signed-device, retained-data/recovery,
   provider, backend, assistant, rollback, and commercial-scope evidence. The
   hosted route is `activate-production.yml` with `candidate_run_id`,
   `website_run_id`, and `receipt_sha256`. The explicit local-provenance route in
   [RELEASE.md](RELEASE.md#explicit-local-build-publication) additionally requires
   actual staging acceptance and preserved native-source parity. It uses:

   ```sh
   node scripts/publication.mjs prepare /private/publication
   node scripts/publication.mjs ready /private/publication
   node scripts/publication.mjs publish /private/publication
   ```

   These commands have different effects: `publish` makes the accepted GitHub
   release public. Deploy its prepared assets without rebuilding Astro:

   ```sh
   export CURFEW_WEBSITE_ASSETS_DIRECTORY=/private/publication/site-ready
   pnpm --dir landing/hosting exec cf build --mode production
   pnpm --dir landing/hosting exec cf deploy --prebuilt --mode production --dry-run --provision=false
   pnpm --dir landing/hosting exec cf deploy --prebuilt --mode production --provision=false
   node scripts/publication.mjs verify /private/publication
   ```

   Run from the clean reviewed app checkout with the pinned configuration and
   authorized production credentials. The final command verifies actual customer
   delivery. Installer publication does not enable Plus sales; any
   live-billing change remains a separate owner-controlled action.

5. **Resume and observe.** Use backend `phase=resume` only after the applicable
   live acceptance passes. This is the final account-availability switch, not
   an installer or sales switch. With the already accepted configuration and a
   fresh private readiness receipt, dispatch the protected workflow:

   ```sh
   gh workflow run deploy-production.yml --repo TheHypertextStudio/curfew-sync --ref main \
     -f phase=resume \
     -f configuration_commit="$CURFEW_CONFIGURATION_COMMIT" \
     -f configuration_sha256="$CURFEW_CONFIGURATION_SHA256" \
     -F cutover_readiness=@"$CURFEW_CUTOVER_READINESS"
   ```

   The workflow still enforces its environment approval, readiness validation,
   and completed checkpoint/fences. Confirm canonical account entry, certificates,
   service configuration identities, the actual installer bytes and signed feed,
   public path/query-preserving 308 redirects, and retired auth/API hosts returning
   410 without forwarding credentials. Publish the matching installation guide
   only after the public installer and feed are verified. Record the actual
   activation time and monitor through the end of the following calendar day in
   `America/Los_Angeles`; report unavailable event-log coverage explicitly.

## Recovery

Restore the retained Worker versions, endpoint configuration, and website/feed
assets against the existing data. Preserve post-cutover writes and keep revoked
authorization revoked. Retain the permanent public redirect. Durable Object
rollback must use the current `cf` export/resource identity, not the legacy
Wrangler migrations array. If public installer delivery is withdrawn, restore
matching availability copy and documentation without replacing published signed
bytes or silently reopening sales.
