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
- [-] Native tests: exact link routing, cryptographic verification, offline
  relaunch, preserving active purchases, restoration, cancellation/races.
- [-] Browser tests: checkout action, delayed delivery, fallback, restore form,
  fragment privacy, keyboard access, failure and retry.
- [ ] Update user help, backlog and test mapping for the finished flow.
- [ ] Full unit tests, format/lint, app build, issuer typecheck/tests, website
  build and browser acceptance; inspect rendered app and website.
- [ ] Provision the existing issuer's email binding and rate limits, backfill
  legacy paid purchase indexes, and verify real inbox delivery in Stripe test
  mode against a signed app with the matching signer.
- [ ] Deploy the verified issuer and website, distribute the app, and verify
  actual checkout → activation plus restoration. Keep the public sale gate
  closed until production acceptance; do not call local fixtures purchase proof.

## Operational boundary

The current production issuer `/health` returns HTTP 200. The recorded staging
issuer hostname does not resolve on 2026-10-13; restore email provisioning and
the signer/environment pairing require fresh provider verification. Existing
keys and GET delivery endpoints remain compatible. Reverting the new UI and
POST routes restores manual activation; stored signed keys remain untouched.

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
