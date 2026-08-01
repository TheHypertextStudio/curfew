# Curfew v0.1 release runbook

v0.1 is blocked until automated checks pass and signed-device evidence is
recorded in `Documentation/release-evidence/v0.1.0.md`. A local build is not
distribution proof.

## Shipping contract

- Deployment floor: macOS 26.
- Enabled: WidgetKit, local MCP, authenticated privileged helper, Apple
  Events shutdown, App Group sharing, and Sparkle updates.
- Compiled but hidden and dormant: CloudKit and Calendar.
- Release app entitlements: Apple Events, App Group, non-sandboxed app, and
  disabled library validation for bundled Sparkle XPC services.
- Intentionally absent: iCloud container and APS entitlements.
- App identity: Team ID `39AB9DY3K8`, bundle ID
  `studio.hypertext.curfew`.

## Required credentials

The release workflow requires Apple Developer ID and notarization credentials,
`SPARKLE_PRIVATE_KEY`, `CLOUDFLARE_API_TOKEN`, and
`CLOUDFLARE_ACCOUNT_ID`. Missing update or deployment credentials are fatal
before the artifact is published. The Sparkle private key must exist only in
the `SPARKLE_PRIVATE_KEY` secret; run
`bash scripts/gen-sparkle-keypair.sh TheHypertextStudio/curfew` to rotate it
without printing or persisting the private seed.

Use `scripts/release-checklist.md` for the full business and infrastructure
setup. `Documentation/license-worker-bootstrap.md` is the sole issuer path:
`scripts/license-worker.mjs` renders a caller-owned config from
`web/worker/wrangler.toml.example`. Prove a separate workers.dev Worker with
Stripe test mode before configuring production hostname, KV, secrets, or
checkout.

## Automated gate

Run from the repository root:

```bash
swiftformat Curfew CurfewTests CurfewUITests
swiftformat Curfew CurfewTests CurfewUITests --lint
swiftlint lint --strict
just check
just test-ui
```

Run the full unit suite three consecutive times and the ownership suite
repeatedly. A UI test host that cannot enable automation is a release blocker,
not a pass.

Create the signed Release archive with the same Developer ID identity used by
CI, export it, then validate the exported app:

```bash
xcodebuild archive \
  -project Curfew.xcodeproj \
  -scheme Curfew \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath build/Curfew-Release.xcarchive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Developer ID Application' \
  DEVELOPMENT_TEAM=39AB9DY3K8

bash scripts/verify-release-artifact.sh build/release-export/Curfew.app
```

The verifier checks the embedded Sparkle framework, live feed URL, non-placeholder
public key, Widget extension, all three helper binaries, nested signatures,
Gatekeeper assessment, and exact app entitlements.

## Release automation

For a `v0.1.0` tag, `.github/workflows/release.yml`:

1. Runs the quality gate and rejects placeholder or missing keys.
2. Archives and exports the Developer ID app.
3. Notarizes and staples the app.
4. Verifies the app artifact.
5. Builds, signs, notarizes, and staples the DMG.
6. Publishes the signed DMG to the GitHub release.
7. Signs an appcast whose enclosure points at that exact asset.
8. Attaches the appcast, deploys it to
   `https://curfew.hypertext.studio/appcast.xml`, and compares the live bytes.

Any failure stops the release. Do not announce or update the Homebrew cask
until the downloaded GitHub artifact passes the signed-device gate.

## Signed-device gate

Use a sacrificial Mac. Record date, macOS build, artifact SHA-256, commands,
outcomes, and failures in the evidence file.

### Distribution

1. Download the GitHub Release DMG, not a local replacement.
2. Run `spctl --assess --type open --context context:primary-signature` on the
   DMG and `spctl --assess --type execute` on the installed app.
3. Run `xcrun stapler validate` on both artifacts.
4. Install by dragging from the DMG and launch from `/Applications`.
5. Confirm the artifact hash matches the release evidence.

### Widget and App Group

1. Confirm `studio.hypertext.curfew.widget` appears in `pluginkit -m -A -D`.
2. Add each supported Curfew widget from the gallery.
3. Change the schedule and verify the widget refreshes from the App Group.
4. Verify the signed app and Widget entitlements contain the same App Group.

### Authenticated helper

1. Install and approve the helper in Settings; verify the UI reports a ready
   authenticated channel and `launchctl print
   system/studio.hypertext.curfew.daemon` succeeds.
2. Arm a short lockout and confirm the daemon-owned state file exists at
   `/Library/Application Support/Curfew/lockout-state.json`, with a root-owned
   `0755` parent directory and `0600` file.
3. Reboot during an active deadline and verify the app recovers the daemon's
   deadline.
4. Force-quit the app during a disposable lockout and verify the daemon invokes
   the one-shot `shutdown -h +1` path only after heartbeat age exceeds 90
   seconds. This intentionally powers off the sacrificial Mac.
5. Verify natural expiry and an approved override both clear daemon state.
6. Verify in-app uninstall is rejected while locked, then succeeds after
   completion and removes daemon registration before user state.
7. Reinstall, then run `scripts/uninstall.sh`; verify launchd registration and
   root-owned state are removed through `sudo`.

### Shutdown permission

Run one short lockout with Automation permission granted and one with it denied.
Granted permission must permit `System Events` shutdown. Denied permission must
leave lockout active, avoid retry churn, and point the user to System Settings.

### Product flow

1. Activate and remove a known-good Pro license.
2. Call `curfew.status` through the bundled MCP server and compare it with UI.
3. Exercise the five-minute warning through lockout.
4. Confirm override cooldown, reason length, and hold-to-confirm behavior.
5. Confirm CloudKit and Calendar UI never appears and neither engine emits
   activity in the shipping build.

### Sparkle staging upgrade

1. Produce a signed `0.0.99` staging build with `SUFeedURL` set to
   `https://curfew.hypertext.studio/appcast-staging.xml`.
2. Publish a staging appcast for the signed `0.1.0` candidate using the same
   EdDSA key and candidate DMG.
3. Install `0.0.99`, choose **Check for Updates…**, and complete the upgrade.
4. Verify the relaunched app is the signed `0.1.0` candidate and Gatekeeper
   accepts it.

## CI boundary

Pull-request CI runs on macOS 26 and passes unsigned build settings because
fork-safe runners have no Apple account or provisioning profile. Signed
archives, notarization, and installed-device validation remain release-only
steps requiring the credentials listed above.

## Rollback

Remove the release and live appcast immediately. Restore the last known-good
appcast and DMG together so the feed never points to a missing or mismatched
asset. A helper protocol regression requires shipping a newer signed app; do
not weaken client authentication or delete active root state to roll back.
