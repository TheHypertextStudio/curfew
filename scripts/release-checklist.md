# Curfew Release Checklist

Every external step required to cut a signed, notarized, purchasable release.
One-time infrastructure setup plus the per-release sequence. Keep checkout
disabled until every license-delivery prerequisite is verified.

## One-time infrastructure

Do these in order — each step produces a secret or identifier that the
next step needs.

### 0. Fast path: `just setup`

`scripts/setup.mjs` automates the **web/purchase** infrastructure — steps 4
(Stripe product/prices/payment-links/webhook), 5 (license keypair), 6
(Worker deploy + secrets), and 8 (landing + `/docs` proxy deploy) — in one
idempotent run. It does *not* touch the Apple/notarization/iCloud/Sparkle/Cask
steps (1–3, 7, 9–10); do those separately.

Prerequisites it can't do for you (do these first):

- [ ] Enable Stripe **Managed Payments** on the Hypertext Studio account
      (account-level eligibility — no API).
- [ ] `pnpm -C web/worker exec wrangler login` as **willie@hypertext.studio**
      (the script refuses any other account).

Run it (dry run prints the plan; `--yes` executes; add `--live` only with an
`sk_live_…` key):

```sh
# Test mode, both SKUs ($20 lifetime + $40/yr subscription):
STRIPE_API_KEY=sk_test_… STRIPE_SUB_AMOUNT=4000 just setup --yes
# Also attach the curfew.hypertext.studio Pages domain automatically:
CLOUDFLARE_API_TOKEN=… STRIPE_API_KEY=sk_live_… STRIPE_SUB_AMOUNT=4000 just setup --yes --live
```

Env: `STRIPE_LIFETIME_AMOUNT` (cents, default 2000), `STRIPE_SUB_AMOUNT` (cents;
omit to ship lifetime-only), `STRIPE_SUB_INTERVAL` (`year`|`month`),
`RECREATE_WEBHOOK=1` to rotate the webhook secret, `SKIP_WORKER`/`SKIP_KEYPAIR`/
`SKIP_STRIPE`/`SKIP_PAGES=1` to skip a phase.

Manual steps that remain **after** the script (no API for these):

- [ ] **Mintlify** dashboard → connect this GitHub repo and set the project to
      serve from the **`/docs` subpath** of `curfew.hypertext.studio`. The Pages
      Function in `web/landing/functions/_middleware.js` reverse-proxies
      `/docs` → `curfew.mintlify.dev` without rewriting the path, so Mintlify
      must be told it lives under `/docs`.
- [ ] Commit the values the script injected: the Ed25519 public key in
      `LicenseGate.swift` and the payment-link URLs/price in
      `web/landing/index.html`.

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
- [ ] Create the Curfew Plus lifetime and subscription products and their
      hosted Payment Links only after the production issuer is ready.
- [ ] Keep `web/landing/index.html`'s sale gate in place until the production
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

- [ ] Install from the locked workspace and validate only non-secret settings:
      `pnpm install --dir web --frozen-lockfile`, then set
      `CURFEW_LICENSE_WORKER_NAME`, `CURFEW_LICENSE_KV_NAMESPACE_ID`, and
      `CURFEW_LICENSE_HOSTNAME` and run
      `node scripts/license-worker.mjs validate-config`.
- [ ] Render an untracked deployment config from
      `web/worker/wrangler.toml.example` with
      `node scripts/license-worker.mjs render-config --output
      /secure/user-owned/wrangler.toml`.
- [ ] Bundle before deployment with
      `node scripts/license-worker.mjs dry-run --config
      /secure/user-owned/wrangler.toml`.
- [ ] In an authorized Hypertext Studio Cloudflare session, deploy only the
      rendered config using `cd web/worker && pnpm exec wrangler deploy
      --config /secure/user-owned/wrangler.toml`.
- [ ] Bind the production `LICENSE_KV`, configure the production custom
      hostname, then upload `STRIPE_WEBHOOK_SECRET` and `LICENSE_PRIVATE_KEY`
      as encrypted Worker secrets. Do not put either value in Git, a rendered
      config, or command-line arguments.
- [ ] Verify `node scripts/license-worker.mjs verify-endpoint --base-url
      https://curfew-license.hypertext.studio`; only then point the production
      Stripe webhook at that hostname.
- [ ] Prove checkout, renewal, cancellation, and license refresh first with
      a distinct Stripe test-mode Worker/KV/secrets configuration; do not use
      a real card for that proof.

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

- [ ] Cloudflare Pages → create a project (`curfew-landing`) pointing at this
      repo's `web/landing/` directory.
- [ ] Custom domain: `curfew.hypertext.studio`.
- [ ] Preview deployments on every push to `main`.
- [ ] **Docs proxy:** the landing project ships a Pages Function
      (`web/landing/functions/_middleware.js`) that reverse-proxies `/docs` and
      `/docs/*` to `curfew.mintlify.dev`. In the Mintlify dashboard, connect this
      repo (docs source in `web/docs/`) and set the project to serve from the
      `/docs` subpath of `curfew.hypertext.studio`. The proxy does not rewrite
      the path, so Mintlify must know it lives under `/docs`.

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
     `appcast.xml` to the release only after Sparkle is provisioned. Until
     then it publishes only the notarized DMG.
   - Publishes a GitHub Release.
4. **If (and only if) a later release enables Sparkle, publish its generated
   `appcast.xml`** to `https://curfew.hypertext.studio/appcast.xml` (the
   `SUFeedURL` the app polls) via Cloudflare Pages — e.g. commit it into
   `web/landing/` so Pages serves it. The GitHub release asset alone is not the
   feed; without this step the app never discovers the update. v0.1 skips
   this step because Sparkle is deliberately unlinked.
5. Bump the `Casks/curfew.rb` version + sha256 and push to homebrew-cask
   (only required after the first release is out).
6. Post the release to the landing page's release notes page at
   `web/landing/releases/<version>.html`.

## Smoke tests after tagging

- [ ] Download the DMG from the GitHub Release.
- [ ] `spctl --assess --verbose /Applications/Curfew.app` → accepted.
- [ ] `xcrun stapler validate /Applications/Curfew.app` → stapled.
- [ ] Activate a known-good Pro license → Pro surfaces unlock.
- [ ] Paste MCP config into Claude Desktop → `curfew.status` returns live data.
- [ ] Trigger a curfew 5 minutes ahead → overlay fires at T-0.
- [ ] `brew install curfew` (after Homebrew Cask merges) installs cleanly.
