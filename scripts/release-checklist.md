# Curfew Release Checklist

Every external step required to cut a signed, notarized, purchasable release.
One-time infrastructure setup plus the per-release sequence. Keep checkout
disabled until every license-delivery prerequisite is verified.

## One-time infrastructure

Do these in order — each step produces a secret or identifier that the
next step needs.

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

### 3. iCloud container for CloudKit sync

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
- [ ] Create a product "Curfew Pro" at the **$20** one-time price and a
      hosted **Payment Link** for it.
- [ ] Paste the Payment Link URL into `landing/index.html` (replace
      `https://buy.stripe.com/REPLACE_WITH_CURFEW_PRO_PAYMENT_LINK`).
- [ ] Developers → Webhooks → add an endpoint subscribed to
      `checkout.session.completed`, pointing at the Cloudflare Worker URL
      (see step 6).
- [ ] Save the endpoint's signing secret (`whsec_…`) — goes into
      `STRIPE_WEBHOOK_SECRET` in step 6.

### 5. Ed25519 license-signing keypair

- [ ] `bash scripts/gen-license-keypair.sh` — produces a public/private pair.
- [ ] Replace the placeholder value of `licensePublicKeyBase64` in
      `Curfew/Core/Features/LicenseGate.swift:9` with the emitted
      public key. CI (`.github/workflows/release.yml`) fails the tag
      if the placeholder is still present.
- [ ] Save the private key — goes into `LICENSE_PRIVATE_KEY` in step 6.

### 6. Cloudflare Worker for license issuance

- [ ] `npm i -g wrangler` (or `brew install cloudflare-wrangler2`).
- [ ] `wrangler login`.
- [ ] `wrangler kv namespace create LICENSE_KV` — paste the returned id
      into `wrangler.toml` under `kv_namespaces[0].id`.
- [ ] `wrangler secret put STRIPE_WEBHOOK_SECRET` — paste the `whsec_…`
      signing secret from step 4.
- [ ] `wrangler secret put LICENSE_PRIVATE_KEY` — paste the private key from step 5.
- [ ] `wrangler deploy` — note the worker URL (`*.workers.dev`).
- [ ] Point the Stripe webhook endpoint (step 4) at the worker URL.
- [ ] (Optional) Set up a custom domain: `license.hypertext.studio` →
      uncomment the `routes = [...]` block in `wrangler.toml`.

### 7. Sparkle EdDSA keypair (post-v0.1)

Sparkle remains disabled for v0.1. Its placeholder public key does not block a
release while the framework and updater UI are absent; the release workflow
also skips appcast generation. Complete this section before enabling Sparkle in
a later signed build.

- [ ] Add the Sparkle package: Xcode → Curfew target → File → Add Package
      Dependencies → `github.com/sparkle-project/Sparkle` (exact 2.x). This
      flips `#if canImport(Sparkle)` on and provides `sign_update` for CI.
- [ ] `bash scripts/gen-sparkle-keypair.sh` — emits public + private keys
      once; they are never saved to disk.
- [ ] `gh secret set SPARKLE_PRIVATE_KEY --body "<private key>"`
- [ ] Replace the `INFOPLIST_KEY_SUPublicEDKey` placeholder in
      `project.pbxproj` with `<public key>` (CI fails the tag otherwise).

### 8. Landing page hosting

- [ ] Cloudflare Pages → create a project pointing at this repo's `landing/` directory.
- [ ] Custom domain: `curfew.hypertext.studio`.
- [ ] Preview deployments on every push to `main`.

### 9. Homebrew Cask submission

- [ ] After the first signed release lands (`v1.0.0`), compute
      `shasum -a 256 Curfew-v1.0.0.dmg`.
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

Once the infrastructure above is in place, every release is:

1. Land the final commit on `main`; `just check` must be green.
2. `git tag v1.0.1 && git push --tags`. The version is derived from the
   tag — CI passes `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` to the
   archive, so there is no `project.pbxproj` version to bump by hand.
3. `.github/workflows/release.yml` runs automatically:
   - Signs with the Developer ID certificate.
   - Notarizes via `notarytool`.
   - Builds the DMG.
   - Runs `scripts/generate-appcast.sh` and attaches the signed
     `appcast.xml` to the release (skipped with a warning until the
     `SPARKLE_PRIVATE_KEY` secret is set).
   - Publishes a GitHub Release.
4. **Publish the appcast to the live feed.** Copy the release's
   `appcast.xml` asset to `https://curfew.hypertext.studio/appcast.xml`
   (the `SUFeedURL` the app polls) via Cloudflare Pages — e.g. commit it
   into `landing/` so Pages serves it. The GitHub release asset alone is
   not the feed; without this step the app never discovers the update.
5. Bump the `Casks/curfew.rb` version + sha256 and push to homebrew-cask
   (only required after the first release is out).
6. Post the release to the landing page's release notes page at
   `landing/releases/<version>.html`.

## Smoke tests after tagging

- [ ] Download the DMG from the GitHub Release.
- [ ] `spctl --assess --verbose /Applications/Curfew.app` → accepted.
- [ ] `xcrun stapler validate /Applications/Curfew.app` → stapled.
- [ ] Activate a known-good Pro license → Pro surfaces unlock.
- [ ] Paste MCP config into Claude Desktop → `curfew.status` returns live data.
- [ ] Trigger a curfew 5 minutes ahead → overlay fires at T-0.
- [ ] `brew install curfew` (after Homebrew Cask merges) installs cleanly.
