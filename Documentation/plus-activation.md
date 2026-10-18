# Plus activation and purchase restoration

The requested outcome is checkout → **Activate in Curfew** → verified Plus,
with **Restore Purchase…** available without finding an old key or creating an
account. Existing manually entered lifetime keys remain valid offline.

## Implementation

1. The signed Stripe webhook records a paid purchase and an inbox index. A
   checkout's `complete` status alone never grants access.
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
   fallback. Subscription restoration resolves the latest refresh key.

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
stored license exists, and leaves that license unchanged. Verify restoration
for an old purchase as well as a fresh purchase. This is a licensing recovery
change, not an account-recovery or encryption-key recovery mechanism.
