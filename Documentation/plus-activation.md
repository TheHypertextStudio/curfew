# Plus activation and purchase restoration

The requested outcome is checkout → **Activate in Curfew** → verified Plus,
with **Restore Purchase…** available without finding an old key or creating an
account. Existing manually entered lifetime keys remain valid offline.

## Implementation

1. The signed Stripe webhook records a paid Curfew purchase and an inbox index.
   The SKU and checkout mode must match; completion alone never grants access.
2. The confirmation page exchanges its checkout session for a random 256-bit
   activation ticket. **Activate in Curfew** opens the correct build's URL
   scheme. The ticket lasts 15 minutes and stores only a hashed bearer token.
3. Curfew redeems the ticket against its fixed issuer, verifies the signed v2
   envelope, saves it, and opens Settings → About with the activation result.
   A failed or expired incoming key preserves the current purchase.
4. **Restore Purchase…** requests a link at the purchase email address. Rate
   limits apply per source IP and normalized inbox. The same email and HTTP
   response are sent for known and unknown inboxes; purchase details are
   disclosed only after proof of inbox control. Email contains no license key.
5. The restore page keeps the ticket in the URL fragment, clears it from browser
   history, and offers **Restore in Curfew**. Manual key entry is an available
   fallback. Subscription restoration resolves the latest refresh key or the
   retained paid-period snapshot after cancellation. Legacy lifetime keys take
   precedence over expired subscriptions.

Background renewal only replaces the exact subscription captured before its
request, with a verified key for the same refresh token and no earlier expiry.
Failed refreshes preserve the current purchase. Restore sheet dismissal belongs
to the successful request that opened it; canceled requests cannot dismiss a
later sheet.

Tickets are retryable until expiry so an email scanner or repeated OS callback
does not consume them. They are bearer capabilities; never log them. The
license signature remains authoritative. Recovery cannot unlock account data,
enroll devices, change enforcement, or authenticate a Curfew account.

This extends the existing internal issuer contract, not the MCP/Sync wire
format. No `curfew-protocols` or coordinator change is required.

## Execution and acceptance

- [x] Worker regressions observed failing for missing activation/recovery and
  unpaid checkouts; implement ticket redemption and inbox recovery.
- [x] Native tests: exact link routing, cryptographic verification, offline
  relaunch, preserving active purchases, restoration, cancellation/races.
- [x] Browser tests: checkout action, delayed delivery, fallback, restore form,
  fragment privacy, keyboard access, failure and retry.
- [ ] Update user help, backlog and test mapping for the finished flow.
- [x] Full unit tests, format/lint, app build, issuer typecheck/tests, website
  build and browser acceptance; inspect rendered app and website.
- [x] Provision staging email and rate limits; verify real sandbox checkout and
  inbox restoration against a signed app with the matching signer.
- [ ] Apply the approved production restore-email binding and rate limits
  before the coordinated issuer/site/client rollout.
- [ ] Backfill historical paid purchase indexes in the matching Stripe
  environment and verify an old purchase restores through the hosted page.
- [ ] Deploy the verified issuer and website, distribute the app, and verify
  actual checkout → activation plus restoration. Keep the public sale gate
  closed until production acceptance; do not call local fixtures purchase proof.

## Operational boundary

**Stripe environment isolation:** the owner requires staging and production to
remain separate. Stop live Stripe mutations, real payment submissions and
production purchase-service deployment pending explicit owner direction. The
earlier test checkout used the account's shared Test mode environment, not a
separately provisioned general sandbox. On inspection, Stripe lists zero of
five general sandboxes. Its Test mode shares some settings with live mode, so
that walkthrough establishes test-payment behavior but not full configuration
isolation. The existing Test mode sandbox can support this checkout/restore
integration using its test-only products, links and webhook secret. Creating an
additional general sandbox is optional and is not a prerequisite for this flow.
Do not change shared account settings during testing or copy live credentials
or objects into staging. The deployed webhook handlers
lack an explicit expected `livemode` check. A local, tested guard now requires
an explicit `STRIPE_MODE` binding and rejects an opposite-mode or malformed
event before KV access, including replay/backfill. It has not been pushed or
deployed. Separate Worker KVs and Ed25519 signers already exist and must remain
separate.

The earlier requirement to create a general sandbox was an agent interpretation,
not an owner instruction. It has been removed. The owner correctly identified
the existing Test mode sandbox; no additional sandbox creation was approved.

Live mutations made before this correction: `curfew_sku=lifetime` on
`plink_1TzTyyAREPz33Avb9vvmySJI` and `curfew_sku=subscription` on
`plink_1TzU00AREPz33Avbc4pqHz5W`. Both remain saved. No production checkout,
price, redirect, payment method or webhook was changed in this turn. Do not
silently revert these entries; that is another production configuration change
and requires owner direction. All further Stripe inspection is read-only until
the intended environment and allowed mutation are explicit.

The production issuer `/health` reports envelope v2. Staging has a verified
public signer, restricted restore email and successful signed-app checkout and
restoration. Apple CI credentials are configured; Cloudflare publication access,
actual release signing/notarization and coordinated rollout remain unfinished.
Existing keys and GET delivery endpoints remain compatible.
Reverting the new UI and POST routes restores manual activation; stored signed
keys remain untouched.

## Verification record — 2026-10-13

- Issuer: eight Vitest cases pass; TypeScript typecheck and local Wrangler bundle
  pass. Seven flow regressions include the original six red cases and the
  legacy-index resend case, observed failing before implementation.
- Native: all 1,056 unit-test cases pass on the separate full-unit rerun, and
  the unsigned Debug build passes. Five new activation cases pass, including
  the suspended-request duplicate-callback regression observed red first.
  SwiftFormat check and strict SwiftLint pass (328 files, zero violations).
- Website: source checks, typecheck, lint, format and build pass; all 30 browser
  acceptance checks pass across Chromium, Firefox and WebKit. All 48 repository
  script tests pass. Public documentation remains on the released manual flow
  until the new client and issuer are accepted and distributed.
- A combined native unit/UI run exposed the existing 150 ms sync-cadence test's
  timing sensitivity; its isolated rerun and the full unit-only rerun pass.
  No sync production code or assertion was changed.
- The new native UI test reaches the Restore button but cannot click through
  another `studio.hypertext.curfew.studio.dev` process's full-screen overlay.
  Do not dismiss, disable or bypass that other process to make a test pass.
  Run the interaction on the isolated CI runner and inspect the real UI.
- Provider check: the CLI's cached OAuth session is for **WillieCubed**, account
  `18f90fa11cf0a87145be4a1517e41217`, not the Hypertext Studio account configured
  by this repository. No provider mutation was performed. Its empty email-domain
  list does not establish Studio's email configuration. No Stripe API key or
  approved noninteractive Studio Cloudflare credential is in this shell.

### Issuer recovery configuration

Use the existing production/test issuer, KV namespace and signer; do not rotate
keys as part of this change. Add `EMAIL` with an approved sender allowlist,
`RESTORE_EMAIL_FROM`, an HTTPS `PURCHASE_PORTAL_URL` for the corresponding website,
`RESTORE_IP_LIMIT` (5 requests/60 seconds), and `RESTORE_EMAIL_LIMIT`
(1 request/60 seconds). Use distinct rate-limit namespace IDs per environment.
`web/worker/wrangler.local.jsonc` is a local-only, no-secret example and the source
for generated binding types; never deploy its zero KV ID or localhost URL.
Missing recovery bindings fail with 503 while existing manual activation and
legacy GET license delivery continue working.

After deployment, resend historical **paid** `checkout.session.completed`
events through the matching Stripe environment's signed webhook delivery. A
previously handled event adds its purchase index only when the corresponding
stored Curfew license exists, even if historical checkout metadata is missing.
For subscriptions, retain any existing renewed snapshot during that repair.
If cancellation already deleted the old renewal, resend the latest paid invoice
after the checkout backfill. Its signed paid-period snapshot repairs recovery;
it does not change billing or restart the canceled subscription. Verify restoration
for an old purchase as well as a fresh purchase. This is a licensing recovery
change, not an account-recovery or encryption-key recovery mechanism.

### Verified studio provider state

The existing Chrome session reaches the **Hypertext Studio** account. Its Email
Sending dashboard lists `curfew.hypertext.studio` as **Enabled**, with DNS
**Configured**, and a 1,000-email daily quota. Use the existing approved sending
domain: `purchases@curfew.hypertext.studio`. No domain onboarding or credential
creation is needed. The `curfew-issue-license` production Worker serves
`curfew-license.hypertext.studio` and deploys from this repository main branch.
Its existing deployment at docs commit `bdd703f` confirms that docs merges also
trigger issuer builds; preserve existing bindings and signer while coordinating
the client/site/issuer release. Dashboard inspection has not changed resources.

### Review verification — 2026-10-13

- All six reviewer findings have source fixes and regression coverage. The issuer
  product, cancellation, and legacy-key regressions failed before the fixes;
  all 11 issuer tests and TypeScript checks now pass.
- The existing silent-refresh path was observed clearing a valid purchase on an
  invalid response. Eight native activation tests pass after the refresh and
  restore-generation fixes. Full native verification passes with parallel test
  workers disabled: 81 XCTest tests and 926 Swift Testing tests, plus the Debug
  build. The parallel run hit the existing 150/200 ms sync-test deadlines; both
  affected suites passed separately. No sync assertion or production source changed.
- SwiftFormat apply/check and strict SwiftLint pass (329 files). Website source,
  lint, format, types and build pass; all 30 browser checks and 50 script tests pass.
- CI on the initial PR revision passed native unit/build, issuer, website, and docs
  checks. The interaction test opened the restore sheet but failed to open manual
  entry after Cancel. It now waits for sheet dismissal and enabled controls before
  the next click; that change still requires fresh isolated CI verification.
- The production generator supports `CURFEW_LICENSE_RESTORE_ENABLED=1` with an
  approved `CURFEW_LICENSE_RESTORE_FROM`, HTTPS `CURFEW_LICENSE_PORTAL_URL`, and
  distinct positive `CURFEW_LICENSE_RESTORE_IP_NAMESPACE_ID` and
  `CURFEW_LICENSE_RESTORE_EMAIL_NAMESPACE_ID`. Existing three-field deployment
  configuration remains compatible with recovery disabled. A bundle using the
  verified production identifiers and restricted sender passed Wrangler dry-run;
  no provider permission has been granted and no email sent.

### Legacy recovery and concurrent delivery

Sixteen issuer tests pass after further failing-first regressions for metadata-free
legacy purchases, renewal retention before cancellation, invoice replay after a
historical cancellation, UTF-8 inbox addresses, and concurrent out-of-order invoice
completion. Paid invoice snapshots use immutable `period:<token>:<period-end>`
records. Activation, restoration and refresh select the greatest valid expiry
across those records and older pointers; convenience pointer races cannot erase
a paid period. At most 1,000 period records are read per subscription; incomplete
lists fail closed. KV propagation still requires actual provider acceptance.

Nine native activation tests pass, including canceling an activation before its
queued task starts. Full nonparallel verification passes: 81 XCTest and 927 Swift
Testing tests, Debug build, SwiftFormat and strict SwiftLint. The latest native
interaction CI still failed to expand manual entry after sheet dismissal; the
test now targets the visible native disclosure arrow rather than its label's
midpoint. Fresh CI must verify that change. The scoped follow-up review reports
no remaining actionable findings in the recovery fixes.

### Repeatable purchase-test inbox

Use a fixed owner-controlled tagged address with the convention
`<owner>+curfew-purchases-test@gmail.com`; Gmail delivers tagged addresses to the
existing inbox. Set `CURFEW_PURCHASE_TEST_EMAIL` in the local test environment,
not committed source, to that recipient. Test-mode Stripe checkout and restoration
must use the exact same address. Search that recipient and the Curfew sender to
verify a newly received message; record its timestamp and provider message ID
without logging the restore ticket or signed key. Do not create a disposable
third-party mailbox, another account, or DNS routing just for this walkthrough.
This convention follows [Google's inbox guidance](https://support.google.com/a/users/answer/9282734).

### Approved provider preparation

The owner approved restricted restore email on 2026-10-13. The existing Studio
issuer's build settings now persist all five recovery variables, with the
`purchases@curfew.hypertext.studio` sender, `https://curfew.hypertext.studio` portal,
and rate-limit namespace IDs `1781921001`/`1781921002`. A fresh dashboard tab
confirmed persistence after Save. Runtime remains the prior issuer with its
existing KV and secrets; the new bindings take effect only after the reviewed
generator/code deploys. No signing credential was created, read, or rotated.
No email has been sent. The connected owner inbox supplies the tagged test
recipient locally. Stripe's test dashboard currently requires sign-in; the actual
test checkout and inbox restore remain pending.

### Staging pairing verified during the walkthrough

Stripe is now signed in to the Hypertext Studio sandbox. Its existing destination
`Curfew staging license Worker` points to
`https://curfew-issue-license-staging.hypertext-studio.workers.dev/`; `/health`
returns envelope v2. The retained Worker and its `curfew-license-keys-staging`
namespace exist. The missing `curfew-license-staging.hypertext.studio` DNS name
did not imply a missing test service. No secret value was revealed.

The existing test Worker is connected to this repository's reviewed
`codex/plus-activation` branch, root `web`, using the same configuration-render
deployment command and existing `curfew-issue-license-builds` credential. Its KV
binding and both encrypted secrets remain in place. Build variables select the
retained Worker/KV and first-party staging hostname; recovery remains disabled
until its restricted sender binding is prepared. The next branch push triggers
its first repository deployment. After the hostname is live, update the existing
Stripe destination URL while retaining its signing secret before making a test
purchase. Production checkout and the production issuer are unchanged.

Native activation and renewal now share `LicenseEndpoint`: production uses
`curfew-license.hypertext.studio`; development and Studio Dev use the fixed
`curfew-license-staging.hypertext.studio`. A missing environment-selection contract
failed before implementation. The full nonparallel unit run (81 XCTest and
928 Swift Testing tests), Debug build, SwiftFormat, and strict SwiftLint pass.
Incoming links still cannot choose an issuer, and signature verification remains
unchanged. The installed signer pairing still needs the real test checkout.

The exact-head native CI suite passed format, lint, units and build. Its purchase
interaction still failed at manual entry after clicking the recorded disclosure
arrow: the license field never appeared. This is the failing behavior proof for
replacing that narrow disclosure target with a standard accessible button. The
button exposes Expanded/Collapsed state, retains the draft, and the UI test uses
its accessible name rather than geometry. A local rerun first hit the development
provisioning profile's missing Associated Domains capability; an unsigned UI run
stalled before test execution and was canceled. Hosted interaction verification
is still required. No enforcement settings or running lockout were changed.

### Current sandbox deployment and checkout preparation

Cloudflare build `b3a94171-e45b-41ec-9d8e-8d53579a126f` deployed commit
`3f12cda3e4371b6b3b535b3ff643a5355d680327` to the retained staging issuer,
version `f7ce105d-291c-4da4-b95f-0bb27e43ab8f`, at 100 percent traffic.
The first-party staging health endpoint returns envelope v2 and the activation
route rejects an invalid request with HTTP 400. The existing Stripe destination
now points to `https://curfew-license-staging.hypertext.studio/`, retaining its
three selected events and encrypted signing secret.

The existing sandbox payment link has `curfew_sku=lifetime` metadata and its
saved After payment redirect is temporarily
`http://127.0.0.1:4325/success?session_id={CHECKOUT_SESSION_ID}`. The preview uses
the deployed staging issuer and `curfew-dev` scheme; it is a real-provider check,
not hosted website acceptance. The retained website staging Worker has no route
or Git build, and GitHub's staging environment has no deployment credential.
Unauthenticated access to the required GitHub npm package registry returns 401.
Do not widen credentials or undo the paused Pages migration to conceal this gap.
A hosted portal and sender-restricted staging recovery are still required for
actual inbox restoration. Production sale availability remains unchanged.

Rollback for the manual-entry interaction is reverting the Button/conditional
content to the prior disclosure; stored keys and issuer behavior are unaffected.

### Hosted purchase preview deployment

The website staging environment is assigned only
`curfew-site-staging.hypertext.studio`. Its account/sync coordinator domains and
all production routing stay as configured. The route contract failed first when
the staging route was empty. Revert that route and roll back the previous Worker
version to remove the purchase preview; no purchase or account storage changes.

The preview deployment uses a public prerelease containing only built static
website files, paired with an exact source commit and SHA-256. Cloudflare skips
package installation, fetches that artifact, verifies the checksum and source
revision, then deploys with pinned Wrangler and the existing build credential.
Build dependencies and registry authentication remain in the validated GitHub
workflow/local build. No new persistent credential or broader token is required.
The public release marker records the revision, staging issuer, and `curfew-dev`
scheme. Hosted runtime, signed activation and inbox restoration still require
verification after deployment.

The staged artifact is published as prerelease `curfew-site-preview-a83e1d6`,
source `a83e1d6925647f505cc2adbd005012465471e680`, with SHA-256
`a2c3eb7b0cf1b1c786140b408724851f1ffccf050b512747f2fd719895aae585`.
Its 50 public files (4.3 MB archive) contain no package credentials or environment
files. Both purchase pages select the staging issuer and `curfew-dev` scheme.
An unauthenticated download produced the same checksum. The existing staging
website Worker is connected to the reviewed branch and existing build token,
with preview builds disabled and `SKIP_DEPENDENCY_INSTALL=1`. Its build checks out
the released revision before fetching and checking the archive, so subsequent
branch changes cannot silently change the candidate. Hosted build verification
is pending.

### Actual purchase and signer acceptance

The existing sandbox link completed a $1 test-card checkout using the dedicated
purchase-test alias. Stripe returned to the confirmation page and the deployed
staging issuer delivered a `curfew-plus` lifetime envelope with the matching
inbox and an activation ticket. Its signature does not verify against the app's
embedded public key, or any prior public key recorded in LicenseGate history.
No private signing seed was viewed, copied, changed, or rotated. Native activation
is not accepted until the development build pins the actual staging public key.

`GET /health` now exposes only the current Ed25519 public verification key in
standard base64, alongside status and envelope version. The runtime derives it
from its configured signer internally; it never returns the private JWK or seed.
A malformed or missing signer produces a generic 503. Tests first failed for the
absent public key and false healthy response, then verified the exact public-only
JSON and a real issued envelope signature. Existing signing stays non-extractable.
All 18 issuer tests and type checking pass. This endpoint does not configure app
trust dynamically: production and development pins remain build-time decisions.

The retained website preview deployed successfully in build
`a2a5a713-531d-418a-ae1b-5aaf3db4af2a`, Worker version
`f43d6c5f-c7f5-431c-b573-12d0cb69cff3`. Its public release marker matches the
artifact source revision, staging issuer and development scheme. Cloudflare
required an explicit shallow fetch of the pinned revision and `NODE_VERSION`
24.20.0. The existing build credential successfully uploaded the static assets;
no credential expansion was needed. The dedicated restore page renders over HTTPS.

The user separately approved restricted email for the staging issuer. All eight
build variables persisted and deployed in build
`2ddc598d-e2d9-4bff-976e-e1a7b0eeed36`, version
`f693e63e-ab9f-4513-9a76-049582d4f649`. A restore request from the hosted staging
page delivered the expected message to the approved purchase-test inbox at
2026-10-13 22:08:25 UTC. SPF, DKIM and DMARC passed, and Gmail placed it in the
Inbox. Native restoration remains pending.

The hosted UI failure recording at `a83e1d6` shows the manual-entry button in
Expanded state and a visible unnamed text field. This corrects the earlier hit
testing diagnosis: the failing lookup missed the field's accessibility name. The
field now has an explicit License key label and `license-key-input` identifier;
the UI test checks Expanded and queries that identifier. Hosted CI at `8399b8a4`
passed `testPurchaseRestoreAndManualActivationAreReachable` in 12.392 seconds.
Reverting the label affects accessibility/test lookup only.

Public-key health rollback is reverting the added response field/helper; license
keys and purchase storage are unchanged. Keep public help and production sales
on the released flow until client, service and website acceptance is complete.

### Build-bound license trust and main sync

The retained staging public key is
`Yvu91gvPfXzgg375axY/mPHQMA/0ejiDPFZuDn8/qE4=`. It verifies the actual paid
sandbox envelope. Development builds now pin this key; production retains
`wws4nqf0o6zvtOONgWITcqquPv6kIhd57WT2WLgMIvQ=`. No private seed changed.

Licensing selects its environment from the bundle/executable identity with an
empty environment dictionary, following the account endpoint policy. The signer,
redemption/restore issuer, renewal issuer and activation URL scheme share that
selection. An inherited `CURFEW_FLAVOR=development` cannot redirect production
licensing or enable sandbox keys. Tests still inject keys, services and flavors
explicitly. The new production-bundle regression failed first for the missing
build-bound selector; all 12 activation tests then passed. Reverting this pairing
disables sandbox activation while retaining production trust and stored keys.

Main's `c5fb4f69` was cherry-picked without a merge commit, preserving the published
activation branch and local signer work. The Mintlify files already match main;
the local server at port 3317 was restarted and the licensing page refreshed.

Final local verification passed: 12 targeted activation tests, 81 XCTest cases
and 937 Swift Testing cases in the complete unit suite, strict SwiftLint,
SwiftFormat and the unsigned Debug build. A normal CUA launch of that Debug app
did not reach its UI. A one-second process sample shows the main thread blocked
in `WidgetSharedStateStore.sync(settings:)` → `Data.write` → `open` during model
initialization. This prevents native link acceptance on this launch; it does not
establish a licensing failure or successful activation. No widget settings,
permissions, retained data or enforcement state were reset to bypass it.

A fresh staging restore email also arrived at 22:23:57 UTC. Opening its link
cleared the fragment and showed **Restore in Curfew** with the development
scheme. The sandbox payment-link editor required Stripe reauthentication when
saving the hosted return URL; its persistence remains unverified.

The normal signed Debug build fails before compilation because `Mac Team
Provisioning Profile: studio.hypertext.curfew.dev` lacks Associated Domains and
`com.apple.developer.associated-domains`. No signing account, profile, certificate
or permission was created or widened. A correctly provisioned signed client is
still required for final installed-app acceptance.

### Installed-client acceptance

The real paid sandbox checkout activates Plus through the confirmation page's
primary action. Debug acceptance covers warm and inactive cold launches, inbox
restoration without manual key entry, and a retained verified lifetime purchase
in a fresh process. The initial Debug startup block cleared before this proof.

The owner-clicked checkout also activates the exact signed Studio Dev candidate;
a fresh candidate process retains the verified entitlement. The standard
`StudioDev` build uses the existing T95VDD3A4W profile and passes deep, strict
signature verification. Its source is `5c494d330c0106b7f71cbcda75fd2c8bb2832158`
and CDHash is `3ba7ebcc2a780953a8ce6d02ac7b5270de304110`.

The installed and candidate apps had identical signing authority, bundle/team
identifiers and entitlements before a same-identity update. Another concurrent
install subsequently replaced the Applications copy with an older licensing UI;
that copy remains intact. Acceptance uses the exact candidate in DerivedData.
The previous installed app is retained at
`/tmp/curfew-studio-dev-before-5c494d33.app` for rollback.

The signed native **Restore Purchase…** form delivered a real message to the
approved test inbox at 23:11:47 UTC, with SPF, DKIM and DMARC passing. Its hosted
link clears the fragment and presents **Restore in Curfew** with the Studio Dev
scheme. After the owner clicked that action, the exact signed candidate showed
**Curfew Plus is active.**, **Verified** and the lifetime entitlement. Signed
checkout, restoration and retained entitlement are now observed end to end.

The hosted artifact is prerelease `curfew-site-preview-5c494d3`: 50 public files,
archive SHA-256
`988ae95d423348458729b636858d66cc35482456f1ea3a013c2361721d217a64`.
Build `44b453ca-4af2-4f4f-9c47-0ed081a095f8` verified its checksum and deployed
version `b7a0ee3e-f606-4c4f-854a-30c7c5cd3d55`. The public marker and purchase HTML
confirm the exact source, staging issuer and `curfew-studio-dev` scheme at
`curfew-site-staging.hypertext.studio`. Reopening the Stripe sandbox editor
confirms its saved hosted success redirect includes `{CHECKOUT_SESSION_ID}`.

Every hosted check at `5c494d33` passes, including native format/lint/unit/build,
issuer, website, docs and screenshot capture. The native purchase interaction
passed in 14.237 seconds.

Production distribution and coordinated issuer/site rollout remain pending.
The production issuer resolves and reports healthy envelope v2, but its older
deployment does not expose a public key. First-party licensing docs return 404.
The Release Sparkle public-key setting is still a placeholder.

The owner selected GitHub release configuration. The documented production Apple
team and Studio Cloudflare account IDs are saved; secret metadata now lists
`APPLE_TEAM_ID`, `CLOUDFLARE_ACCOUNT_ID` and the retained `SPARKLE_PRIVATE_KEY`.
Repository, accessible organization and production-environment metadata contain
no other release secrets. Approved certificate, notarization-key and deployment-
token sources are needed to configure the remaining inputs. Secret values must
stay out of chat. A scoped local check found `AuthKey_K5G9T6UX59.p8` in Downloads;
its Apple account, issuer and role still need confirmation before reuse. The two
downloaded certificates are Mac App Store distribution certificates for
T95VDD3A4W, not Developer ID certificates. The local signing-identity inventory
contains development and Mac App Store identities, with no Developer ID
Application identity. No relevant Apple or Cloudflare credential is present in
the shell environment. An organization-secret metadata refresh was stopped by
GitHub's API rate limit; no authentication scope was changed.

Both staging build checks pass at evidence commit
`f1cfb193d241374ece4267a8a37335e267103403`. Apple Developer inspection now has a
working in-app sign-in page awaiting the owner; no private key was uploaded or
new certificate created. The stale Chrome connection could not retain its tabs.

### Verified Apple release account

The owner completed Apple sign-in. The authenticated Studio account is Hypertext
Studio, LLC, team `T95VDD3A4W`. It has Developer ID Application certificate
`XVQ7Y8JRL8` and Developer-role team key **Studio Notarization**, ID `W7P5H42MGS`.
The downloaded public certificate confirms the Studio team and has SHA-256
fingerprint `D6D5BE372FF992DED26BA680E70F0C1AABC46A3D2EEDF7F01BBCB01227DFE124`.

The local `AuthKey_K5G9T6UX59.p8` does not match that notarization key. Scoped
configuration, Downloads, Documents and project-file searches, plus indexed
filename lookup, found no matching notarization file or signing `.p12`/`.pfx`.
No private key was uploaded, read from Keychain or regenerated. The verified
issuer `fd6e9c9a-cb8f-49b0-accf-dce2180b1440` is now saved as
`APPLE_API_ISSUER` in this repository's Actions secrets. Its production
environment still has no secrets.

Release source and the saved `APPLE_TEAM_ID` still name `39AB9DY3K8`. Changing
them to the verified Studio team and provisioning dedicated CI signing and
notarization credentials are awaiting the owner's requested confirmation. The
prepared notarization key has the Developer role; Apple team API keys cover all
apps in the team. Existing credentials are retained. The certificate form is
prepared for the G2 Developer ID authority, with no CSR or certificate created.

The Studio Cloudflare account lists an active **Curfew production GitHub
Actions** token. This repository has no corresponding deployment secret. Token
metadata alone does not provide its value or authorize reuse from another
system; no Cloudflare credential was changed.

### Approved CI credential provisioning

The owner approved dedicated CI credentials, protected local storage, GitHub
secret configuration and the Studio team correction. Apple issued Developer ID
Application certificate `9954666T44` for `T95VDD3A4W`. Its SHA-256 fingerprint is
`2911C79C76F5614F3F84E7F291B070052FECC3069FE587F5BF21247010E7FB52`, and its
public key matches the generated RSA signing key. The protected PKCS#12 includes
the G2 intermediate. Certificate validity ends on 2027-11-12.

The new **Curfew GitHub Notarization** key is `3P5K858QJ5`, with Developer access.
`notarytool history` authenticated successfully and returned no previous
submissions. This proves credential access; no app notarization is claimed.
The six Apple release inputs are now configured in this repository's Actions
secrets. Private files have mode `0600` under
`~/.config/curfew/release-credentials` (directory `0700`). Secret uploads used
stdin; no private values were printed or passed in command arguments. Existing
Apple credentials remain active.

The Release app, widget and artifact verifier now agree on `T95VDD3A4W`, matching
the saved team secret. The signing-team regression failed before that source
change and passed afterward; all twelve release-policy tests pass. Bundle IDs,
license signers and enforcement behavior are unchanged. Roll back the source
team and verifier together only with matching approved signing credentials.

Native revalidation found that `LifecycleWiringTests` read the sandbox license
retained by the real Debug walkthrough. Its reconciliation test also failed in
isolation before the fixture correction. The helper now supplies a license gate
backed by its existing per-test defaults suite, preserving the saved purchase
and the test's original free-to-Plus assertions. This is test isolation only.

Final verification passes: twelve activation cases; the isolated lifecycle
regression; 81 XCTest and 937 Swift Testing cases across 162 suites; SwiftFormat
apply/check and strict SwiftLint (zero violations in 332 files); and the unsigned
Debug build. Review found no actionable regression in the team correction or
fixture isolation. Developer ID archive/export, notarization, stapling and
Gatekeeper acceptance remain unverified.

Current main `adf41e70` is incorporated without a merge commit. A merge-tree
check succeeds. Revalidation of the combined source passes 81 XCTest and 939
Swift Testing cases, the CurfewKit package suites, formatting, strict lint,
the unsigned Debug build and release-policy checks. The signing-team correction
and fixture fix remain intact after the sync.

Remaining release inputs include the Cloudflare deployment credential and
production execution with the retained Sparkle signing seed. The release job
now derives the public key from that seed, passes it into the archive, and checks
the exported app embeds the exact key. Appcast signing precedes DMG publication.
No updater key was regenerated or retrieved from GitHub. Four helper regressions
and two workflow regressions were observed red first; all 57 script tests pass.
The published RFC 8032 seed/public-key vector passes, and a signature made by the
pinned Sparkle tool verifies with the helper's derived fixture key.

Fresh provider inspection confirms `curfew-site-production` does not exist. The
issuer's approved restricted email/rate-limit Build variables are saved, but its
current runtime still has the old deployment's KV and encrypted signer/webhook
bindings. Do not call the restore binding live until the new source is deployed.
Appcast publication still targets the existing Pages path; reconcile that
publisher with the website migration before tagging a release. No website
cutover, new Cloudflare credential, or native release was performed.

Raw command-line HTTP requests to both staging and production Curfew hosts return
Cloudflare error 1010. This is a client-filter response, not proof of an issuer or
website outage. No firewall setting or request identity was changed.

The live Stripe links originally had no metadata. Saved and verified
`curfew_sku=lifetime` on `plink_1TzTyyAREPz33Avb9vvmySJI` and
`curfew_sku=subscription` on `plink_1TzU00AREPz33Avbc4pqHz5W`, matching the new
issuer's paid-checkout guard. Both retain the existing `success.html` redirect,
which matches Astro's file output. Historical sessions do not acquire this new
metadata; recovery backfill still requires the existing paid-license evidence.
Removing these two metadata entries reverts this provider change. No checkout
or charge was submitted.

Authenticated Cloudflare inspection confirms the existing `curfew-landing`
Pages project owns `curfew.hypertext.studio`, with automatic deployments paused
at `7616316e`. Its native direct-upload publisher remains available for review;
no automatic deploy was resumed. The owner approved the Pages-only account token,
expiring October 14, 2027. Token `0e598bba29877a654849a2f1f5111340` is active
with Pages Write across the Studio account; Cloudflare's form offers no
individual Pages-project scope. Its account verification succeeds and it can
read the existing `curfew-landing` project's main production branch. The private
value is stored in the mode-600 protected release folder and Curfew's repository
Actions secret `CLOUDFLARE_API_TOKEN`, through stdin. No deployment was performed.

Final release-script verification: all 57 repository script tests pass, including
the six regressions observed failing first. Full native unit tests, unsigned
Debug build, SwiftFormat check (zero of 332 files) and strict SwiftLint (zero
violations) pass. Review found no actionable defect. Actual retained-secret
execution, signed/notarized distribution and production purchase acceptance
remain pending.

The local Stripe mode guard has nine runtime regressions observed failing first
and passing afterward. Configuration rendering has six regressions observed
failing first; all 61 script tests now pass. All 28 issuer tests and TypeScript
checks pass. Wrangler-generated bindings include `STRIPE_MODE`, and dry-runs
with recovery both enabled and disabled produce valid staging bundles with
`STRIPE_MODE=test`. Review found no actionable defect. The full native unit
suite, unsigned Debug build, SwiftFormat check and strict SwiftLint also pass.
No Stripe mutation or deployment occurred in this verification turn. The source
is retained in a local commit only, because pushing would trigger the staging
Worker build before its existing Test mode webhook and required binding are
reviewed. An additional general sandbox is not required for that review.
