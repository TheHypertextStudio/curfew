# Curfew Release Checklist

Every external step required to cut a signed, notarized, purchasable release.
One-time infrastructure setup plus the per-release sequence. Keep checkout
disabled until every license-delivery prerequisite is verified.

## One-time infrastructure

Do these in order — each step produces a secret or identifier that the
next step needs.

### 0. Fast path: `just setup`

`scripts/setup.mjs` is a legacy initial-production bootstrap for purchase
infrastructure. It generates a signing keypair and creates Stripe resources;
use the native deployment commands for existing environments so their signer,
purchase store and credentials are retained. Frontend publication uses the
separate website commands. Apple, notarization, Sparkle and Cask setup remain
separate.

Prerequisites it can't do for you (do these first):

- [ ] Enable Stripe **Managed Payments** on the Hypertext Studio account
      (account-level eligibility — no API).
- [ ] Verify the existing approved `cf` profile or protected runner credential,
      explicit Cloudflare account/zone, and permissions for the intended operation.
      Do not assume Wrangler authentication carries over to `cf`.

For an initial production setup, review the plan first. Execution requires
separate release-owner authorization. Test credentials are rejected before
provider access; staging uses its existing isolated license configuration.

```sh
# Review the production plan, including its checkout confirmation URL:
STRIPE_API_KEY=sk_live_… STRIPE_SUB_AMOUNT=4000 just setup --live
# Live billing setup requires its separate release-owner authorization:
STRIPE_API_KEY=sk_live_… STRIPE_SUB_AMOUNT=4000 just setup --yes --live
```

Env: `STRIPE_LIFETIME_AMOUNT` (cents, default 2000), `STRIPE_SUB_AMOUNT` (cents;
omit to ship lifetime-only), `STRIPE_SUB_INTERVAL` (`year`|`month`),
`RECREATE_WEBHOOK=1` to rotate the webhook secret, `SKIP_WORKER`/`SKIP_KEYPAIR`/
`SKIP_STRIPE=1` to skip a phase.

Manual steps that remain **after** the script (no API for these):

- [ ] **Mintlify** dashboard → connect this GitHub repo (`web/docs/`) and serve
      the `/docs` subpath of the production origin in shared configuration.
      The marketing Worker proxies the accepted `https://curfew.mintlify.site`
      upstream, including the `/docs/mcp` guide alias.
- [ ] Commit the values the script injected: the Ed25519 public key in
      `LicenseGate.swift` and the payment-link URLs/price in
      `landing/src/pages/index.astro`.

Steps 4–8 below are the manual fallback / reference for what the script does.

### 1. Apple Developer

- [ ] Enroll `Hypertext Studio` in the Apple Developer Program.
- [ ] Generate a **Developer ID Application** certificate in Keychain
      Access → Certificate Assistant → Request a Certificate from a
      Certificate Authority.
- [ ] Upload the CSR in Apple Developer → Certificates, download the
      `.cer`, double-click to install in the login Keychain.
- [ ] Export the cert + private key as `.p12` (right-click the certificate
      in Keychain Access → Export). Remember the password.
- [ ] Base64-encode: `base64 -i cert.p12 -o cert.p12.base64`.
- [ ] `gh secret set APPLE_CERTIFICATE < cert.p12.base64`
- [ ] `gh secret set APPLE_CERTIFICATE_PASSWORD --body "<password>"`
- [ ] `gh secret set APPLE_TEAM_ID --body "<10-char team id from Developer portal>"`

### 2. Apple notarization API key

- [ ] App Store Connect → Users and Access → Keys → Create a new
      **App Manager** key.
- [ ] Download the `.p8` — it can only be downloaded once.
- [ ] `gh secret set APPLE_API_ISSUER --body "<issuer UUID>"`
- [ ] `gh secret set APPLE_API_KEY_ID --body "<10-char key id>"`
- [ ] `gh secret set APPLE_API_PRIVATE_KEY < AuthKey_XXXX.p8`

### 3. iCloud container for CloudKit sync (deferred, not an initial candidate gate)

- [ ] App Store Connect → CloudKit Database → Create container
      `iCloud.studio.hypertext.curfew`.
- [ ] Schema: record types `Schedule`, `LockoutState`, `Device`,
      `DeviceActivity` (the app creates them on first write; no manual
      schema work needed).
- [ ] Mark `Device` and `DeviceActivity` as **Queryable** in the CloudKit
      dashboard. The cross-device "which Macs are active" view runs a query;
      without a queryable index it silently returns nothing (the app logs
      this at `.error`).
- [ ] Promote Production schema from Development before the first
      release tag.

### 4. Stripe (Managed Payments / merchant of record)

Stripe is the seller of record, so it handles VAT/sales tax, receipts, and
fraud — no separate tax-filing service is needed.

- [ ] Create / sign in to the Hypertext Studio Stripe account and enable
      **Managed Payments** (public preview — confirm eligibility).
- [ ] Create the Curfew Plus lifetime and subscription products and their
      hosted Payment Links only after the production issuer is ready.
- [ ] Keep `landing/src/pages/index.astro`'s sale gate in place until the production
      purchase-to-license delivery path is proven end to end. Do not commit a
      hosted payment-link URL before that proof.
- [ ] Developers → Webhooks → add an endpoint subscribed to
      `checkout.session.completed`, `invoice.paid`, and
      `customer.subscription.deleted`, pointing at the production Worker URL
      from step 6.
- [ ] Save the endpoint's signing secret (`whsec_…`) for the production
      `STRIPE_WEBHOOK_SECRET`. It must never be reused by staging.

### 5. Ed25519 license-signing keypair

- [ ] Follow `Documentation/license-worker-bootstrap.md` and run
      `node scripts/license-worker.mjs keygen` with a caller-owned private
      path. The private seed is written at mode `0600` and must not be
      committed or printed.
- [ ] Replace `LicenseGate.configuredPublicKeyBase64` with the emitted public
      key in a separately reviewed app change. CI rejects the all-zero
      placeholder verifier on a release tag.
- [ ] Store the matching private seed only as the production
      `LICENSE_PRIVATE_KEY` Worker secret in step 6.

### 6. Cloudflare Worker for license issuance

- [ ] Install from the locked workspace and select the reviewed shared endpoint
      artifact with independently pinned `CURFEW_DEPLOYMENT_ARTIFACT`,
      `CURFEW_CONFIGURATION_COMMIT`, and `CURFEW_CONFIGURATION_SHA256`.
      Follow `Documentation/license-worker-bootstrap.md` for the native `cf` path.
- [ ] Select the existing staging Worker and KV from inventory through
      `CURFEW_LICENSE_WORKER_NAME` and `CURFEW_LICENSE_KV_NAMESPACE_ID`.
      Keep its namespace, signer, provider credentials, and purchase data separate
      from production; a domain change does not create replacement resources.
- [ ] Verify the artifact-derived Stripe mode: `test` for the dedicated staging
      Sandbox and `live` for production. Confirm a signed opposite-mode event is
      rejected before purchase-store access. Keep test products, links and webhook
      secrets separate from live billing.
- [ ] Build the staging artifact with
      `pnpm --dir web/worker exec cf build --mode staging`, then inspect
      `pnpm --dir web/worker exec cf deploy --prebuilt --mode staging --dry-run --provision=false`.
      Verify bindings, sender allowlist, canonical portal, and resource identities.
      A rendered Wrangler file does not configure these native `cf` commands.
- [ ] During the authorized staging cutover, deploy the same prebuilt output with
      provisioning disabled. Production uses the controlled sequence in
      `Documentation/production-domain-promotion.md`; changing a mode flag does not
      waive production backup, provider, signing, recovery, or acceptance gates.
- [ ] Read back the retained KV, encrypted secrets and selected custom domains.
      Keep `STRIPE_WEBHOOK_SECRET` and `LICENSE_PRIVATE_KEY` in approved secret
      storage; never put their values in source, rendered config, or arguments.
- [ ] Verify the staging issuer at `https://license-staging.thecurfew.app` with
      `node scripts/license-worker.mjs verify-endpoint --base-url https://license-staging.thecurfew.app`.
      Verify production separately at `https://license.thecurfew.app` when its
      activation is authorized; provider changes remain with that release owner.
- [ ] Prove Sandbox checkout, webhook delivery, renewal, cancellation, license
      refresh, and browser-to-app restoration before acceptance. No real-card
      fixture or production billing change is part of the staging proof.

### 7. Sparkle EdDSA keypair (candidate prerequisite)

Sparkle is linked exactly at `2.9.4`. `Curfew/Info.plist` contains the final
feed URL and public key; CI rejects a placeholder and treats a missing private
key as fatal before publishing.

- [x] Link `sparkle-project/Sparkle` exactly at `2.9.4` and require
      `SPUStandardUpdaterController`.
- [x] Run `bash scripts/gen-sparkle-keypair.sh TheHypertextStudio/curfew`.
      The script uploads `SPARKLE_PRIVATE_KEY` directly and prints only the
      public key; it never writes or displays the private seed.
- [x] Put the emitted public key in `Curfew/Info.plist` as `SUPublicEDKey`.
- [ ] Verify repository Actions contains `SPARKLE_PRIVATE_KEY` without reading
      or rotating it.

### 8. Landing page hosting

Use the existing native Astro and Worker commands described in
[`Documentation/website.md`](../Documentation/website.md). Website publication
and preview do not run through whole-product billing setup. Retain account,
licensing and sync ownership and the absent feed until a genuine signed release.

The hosting setup does **not** authorize a sale: keep the root landing sale gate
closed until the production Stripe webhook and signed-app license delivery are
independently verified. Verify actual Mintlify guides, navigation, assets and
search on the serving Worker.

### 9. Homebrew Cask submission

- [ ] After the first signed 0.0.x release is activated (for example `v0.0.1`), compute
      `shasum -a 256 Curfew-v0.0.1.dmg` for those exact retained bytes.
- [ ] Paste the sha and version into `Casks/curfew.rb`.
- [ ] Fork `homebrew/homebrew-cask`, PR `Casks/curfew.rb`.
- [ ] Run `brew style --fix` and `brew audit --new --cask` locally before PR.

### 10. Branded DMG installer art (optional but recommended)

The DMG is the install experience. `scripts/build-dmg.sh` auto-layers branded
assets when they exist — without them it falls back to plain Finder chrome, so
this is never a release blocker.

- [ ] Drop `scripts/dmg-assets/background.png` — **1160×800** (the @2x of the
      580×400 install window). Design it against the fixed icon positions: the
      app glyph at the left, the Applications drop-link at the right, with a
      "drag to install" arrow between.
- [ ] (Optional) Drop `scripts/dmg-assets/volume.icns` for a custom mounted-
      volume icon.
- [ ] Preview locally with `just dmg` — builds an unsigned DMG and opens it so
      you can eyeball the window before tagging. CI uses the same script, so
      what you see is what ships.

### Heads-up: deployment-target reach

The project's minimum is **macOS 26 (Tahoe)** (`depends_on macos: ">= :tahoe"`
in the cask; the matching deployment target in the Xcode project). That
excludes everyone not yet on the latest macOS. If wider reach matters at
launch, consider lowering the deployment target to macOS 14/15 before the first
tag — purely a product call, but it materially changes the addressable audience.
The release workflow runs on `macos-26` to match the target.

## Per-release sequence

Once the infrastructure above is in place, prepare a candidate, not an implicit
production publication. Follow `Documentation/RELEASE.md` for owner-controlled
activation after real signed-device/provider/recovery evidence.

1. Land the final commit on `main`; `just check` must be green.
2. Only when authorized, tag the next `v0.0.x`. The version is derived from the
   tag — CI passes `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` to the
   archive, so there is no `project.pbxproj` version to bump by hand.
3. `.github/workflows/release.yml` runs automatically:
   - Requires Developer ID Application signing under Studio team T95VDD3A4W.
   - Notarizes via `notarytool`.
   - Verifies the signed app, then builds/signs/notarizes/staples the DMG.
   - Generates a signed appcast for the future exact asset and verifies its
     Ed25519 signature against the signed app's public key.
   - Retains `curfew-signed-candidate`, with exact DMG/feed/configuration hashes
     and notarization receipts. No public release, site or feed is activated.
4. Run every signed-device check in `Documentation/RELEASE.md` and record the
   artifact hash and outcome in `Documentation/release-evidence/v0.0.1.md` (or the
   next exact 0.0.x ledger). Inspect the owner receipt and coordinate backend,
   provider and domain activation manually. A receipt is not production proof.
5. Bump the `Casks/curfew.rb` version + sha256 and push to homebrew-cask
   (only required after the first release is out).
6. Post the release to the landing page's release notes page at
   `landing/releases/<version>.html`.

## Smoke tests on the retained candidate (authorized validation host only)

- [ ] Download the retained DMG from the exact successful Actions run.
- [ ] `spctl --assess --verbose /Applications/Curfew.app` → accepted.
- [ ] `xcrun stapler validate /Applications/Curfew.app` → stapled.
- [ ] Activate a known-good Pro license → Pro surfaces unlock.
- [ ] Paste MCP config into Claude Desktop → `curfew.status` returns live data.
- [ ] Trigger a curfew 5 minutes ahead → overlay fires at T-0.
- [ ] `brew install curfew` (after Homebrew Cask merges) installs cleanly.

## Rest companion artifact acceptance

Build the app and companion for distribution architectures rather than treating the native Debug test destination as a universal artifact. Verify the embedded `Curfew.saver` with `scripts/verify-release-artifact.sh`: both arm64 and x86_64 executable slices, bounded and consistent Mach-O architecture records, the companion identifier and independent version, and its approved Developer ID signature/team. A native bundle load establishes only the current host slice. It does not prove execution inside the screensaver process or on the other host architecture.

Production activation and public installer publication remain held until explicitly released. Archive/signing execution requires final source integration and the current isolated resource allocation; source verification does not establish either.
