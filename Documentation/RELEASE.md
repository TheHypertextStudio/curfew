# Curfew v0.1 release runbook

v0.1 is blocked until automated checks pass and signed-device evidence is
recorded in `Documentation/release-evidence/v0.1.0.md`. A local build is not
distribution proof.

- Apple Events-backed shutdown
- WidgetKit signing + App Group reads
- `SMAppService` privileged helper install/status
- task-scoped Chrome extension and native-host acceptance
- CloudKit / push entitlements and real container access
- notarization / Gatekeeper / DMG smoke testing

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

Use `scripts/release-checklist.md` for the full business/infrastructure setup
(Stripe, Cloudflare Worker, Sparkle, landing page, Homebrew), and
`Documentation/license-worker-bootstrap.md` for the sole reproducible issuer
path: `scripts/license-worker.mjs` renders a caller-owned config from
`web/worker/wrangler.toml.example`. Prove a separate
`curfew-license-staging.hypertext.studio` Worker with Stripe test mode before
configuring the production KV binding, secrets, or checkout. The Apple release
identifiers that must stay aligned are:

## Automated gate

Before running the signed-build checks below, make sure these external
prerequisites exist:

1. **Apple signing + notarization credentials**
   - `APPLE_TEAM_ID`
   - `APPLE_CERTIFICATE`
   - `APPLE_CERTIFICATE_PASSWORD`
   - `APPLE_API_ISSUER`
   - `APPLE_API_KEY_ID`
   - `APPLE_API_PRIVATE_KEY`

2. **CloudKit / push-backed Pro sync** (optional until the feature is enabled)
   - Provision `iCloud.studio.hypertext.curfew`.
   - Promote the production schema before release.
   - Expect the signed app to create/use these record types:
     - `Settings`
     - `Device`
     - `DeviceActivity`
     - `LockoutState`
   - Only enable `cloudSyncEnabled` in a shipping build after the signed-build
     verification below passes.

3. **Release entitlements**
   - The conservative v0.1 `Curfew/Curfew-Release.entitlements` carries:
     - `com.apple.security.automation.apple-events = true`
     - `com.apple.security.application-groups = group.studio.hypertext.curfew`
   - It deliberately omits iCloud and `aps-environment` while CloudKit and
     push-backed sync are disabled. Reintroduce and validate those entitlements
     only in the release that enables `cloudSyncEnabled`.
   - `CurfewWidget/CurfewWidget.entitlements` must continue to carry:
     - `com.apple.security.app-sandbox = true`
     - `com.apple.security.application-groups = group.studio.hypertext.curfew`

4. **Helper packaging**
   - The app bundle must contain:
     - `Curfew.app/Contents/Resources/curfew-daemon`
     - `Curfew.app/Contents/Library/LaunchDaemons/studio.hypertext.curfew.daemon.plist`
   - The plist must keep `BundleProgram = Contents/Resources/curfew-daemon`.
   - The Xcode bundle phase must sign `curfew-ctl`, `curfew-mcp`, and
     `curfew-daemon` with `EXPANDED_CODE_SIGN_IDENTITY`; copying SwiftPM's
     ad-hoc linker signature into `Contents/Resources` is not sufficient.

## Build against Curfew Sync staging

The isolated Dev app's Debug configuration selects staging by default. It binds
the staging account portal, OAuth issuer/resource, sync API, MCP resource, and
daemon command JWKS together; the bundle phase forwards the same setting to
every embedded SwiftPM executable.
Staging also uses a separate account-encryption Keychain service, so acceptance
testing cannot read or overwrite production account keys. The Debug app installs
`studio.hypertext.curfew.dev.daemon`, and its root-owned state lives under
`/Library/Application Support/Curfew (Dev)`.

```bash
xcodebuild build \
  -project Curfew.xcodeproj \
  -scheme Curfew \
  -configuration Debug \
  -destination 'platform=macOS'
```

The build hard-fails if `CURFEW_STAGING` is combined with Release, if the helper
plist does not match the app flavor, or if the flag has any other value. A
staging build therefore cannot be archived as Curfew or replace the production
LaunchDaemon. Debug also exposes the shipping MCP and privileged-helper controls
so the Dev app can complete the documented enrollment and remote-lock acceptance
path. Release selects production services and features.

## Build a local signed release candidate

The CI release workflow uses the same archive/export path shown here. Running it
locally is the fastest way to validate shutdown/widget/helper/CloudKit behavior
before pushing a tag.

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

```bash
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP"
codesign -d --entitlements :- "$APP"
codesign -d --entitlements :- "$WIDGET"
APP_TEAM="$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
HELPER_TEAM="$(codesign -dv --verbose=4 "$HELPER" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
test -n "$APP_TEAM" && test "$HELPER_TEAM" = "$APP_TEAM"
plutil -p "$HELPER_PLIST"
ls "$WIDGET" "$HELPER" "$HELPER_PLIST"
```

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

`SMAppService` install/status behavior only becomes trustworthy on a signed app
running on a real machine.

1. In Curfew, open **Settings → Integrations** and click **Install** for the
   privileged helper.
2. Confirm the UI lands in either **Running** or **Needs approval** and does
   not fail silently.
3. Open **System Settings → General → Login Items & Extensions** and confirm:
   - Curfew's login item row appears
   - the helper approval/install row appears if macOS requires approval
4. Optional shell-side inspection:
   ```bash
   sudo launchctl print system/studio.hypertext.curfew.daemon
   ```
5. Start a lockout and verify the sentinel path is real on disk:
   ```bash
   ls -l "/Library/Application Support/Curfew/lockout-active"
   ```
6. With the login session locked, deliver a signed staging remote-lock command
   and confirm the daemon updates its root-owned deadline without waiting for
   the session to unlock:
   ```bash
   sudo ls -l "/Library/Application Support/Curfew/lockout-deadline.json"
   ```
   Do not use a shutdown command for this acceptance check.
7. Log out or reboot once and confirm:
   - Curfew relaunches as expected
   - the daemon remains installed/approved
   - helper status in Settings still reflects reality
8. Uninstall via the app (or `scripts/uninstall.sh`) and confirm the helper and
   login-item statuses return to the uninstalled state.

Treat the helper path as **not release-ready** if installation only appears to
work in-app, the LaunchDaemon never shows up in `launchctl`, or the sentinel
file never appears during a real lockout.

### 4. Task-scoped Chrome enforcement

Build the development extension and load `web/extension/dist/development` in
Chrome. Confirm that Chrome reports extension ID
`loammdknmfbkjnckaeeagnmakinknbck`. Launch the matching Debug app, install its
development native host, and confirm that Settings reports a fresh extension
heartbeat and a responding host.

Use a non-production Docket task for acceptance. Connect Docket, let both setup
facts become true, and enable browser enforcement. Verify an unknown top-level
page blocks before it renders. Confirm that the blocker shows the current task,
the normalized hostname, and the initial question. Exercise one challenge, one
denial, one bounded grant, expiry, a task switch, the fixed paused-session break,
and an offline host. Inspect `chrome.storage.local` and confirm that neither the
justification nor the challenge answer exists.

Disable enforcement before cleanup. Confirm that Chrome has no Curfew dynamic
rules. Then remove the matching native-host manifest and unload the extension.
The Debug screenshot fixtures prove layout only. They do not satisfy this
acceptance check. The signed release and Web Store draft must repeat the same
flow with the production identity before release.

### 5. CloudKit + push-backed sync

CloudKit requires real Apple-side provisioning plus a future signed build that
adds the iCloud and APS entitlements when `cloudSyncEnabled` is enabled.

1. Confirm the signed app entitlement dump includes:
   - `com.apple.developer.icloud-container-identifiers = iCloud.studio.hypertext.curfew`
   - `aps-environment = production`
2. Use a signed build where `cloudSyncEnabled` is intentionally enabled and a
   valid Pro license is active.
3. Launch the app on an iCloud-signed-in Mac and watch sync logs:
   ```bash
   log stream --predicate 'subsystem == "studio.hypertext.curfew" AND category == "cloudkit-sync"' --info
   ```
4. Make a settings change and confirm the CloudKit Dashboard shows activity for:
   - `Settings`
   - `Device`
   - `DeviceActivity`
   - `LockoutState`
5. On a second signed machine (or another clean validation environment signed
   into the same iCloud account), confirm:
   - the device appears in **Settings → Devices**
   - a settings mutation on machine A syncs to machine B
   - lockout/warning state handoff behaves plausibly once both devices are active

Treat CloudKit as **not release-ready** if the feature only works locally, the
record types never appear in production, or the signed build still behaves like
the entitlement/container are absent.

### 6. Final signed-app / DMG smoke test

After the feature-specific checks above, do a final sanity pass on the shipped
artifact:

```bash
xcrun stapler validate "$APP"
```

- Install from the DMG or exported app.
- Verify app launch, schedule save/load, warning → overlay transition, and
  override recovery.
- Run `Curfew.app/Contents/Resources/curfew-ctl status` and confirm the output
  matches the UI.
- Paste the Claude Desktop config from **Settings → Integrations** and confirm
  `curfew_status` responds.
- Paste a known-good Pro license and confirm only the explicitly enabled Pro
  previews in that build unlock.

## Shipping a release

1. Update `MARKETING_VERSION` + `CURRENT_PROJECT_VERSION` in `Curfew.xcodeproj`.
2. Push the final commit to `main`; `just check` should already be green.
3. Tag the release: `git tag v0.0.1 && git push origin v0.0.1`
4. `.github/workflows/release.yml` will resolve the public `curfew-protocols` SPM dependency without an additional repository secret, then:
   - run `just check`
   - archive with Developer ID signing
   - notarize with `notarytool`
   - staple/build the DMG
   - upload the DMG as a GitHub Release asset
   - skip Sparkle appcast generation and upload until Sparkle is explicitly
     provisioned; the initial build has no updater UI
5. Download the GitHub Release DMG and repeat the final smoke test above on the
   actual shipped artifact before announcing the release.

The pull-request CI workflow also runs on `macos-26` so its test host matches
Curfew's macOS 26 deployment target; running it on an older macOS image cannot
execute the app or its tests. Its Debug test/build artifacts deliberately pass
unsigned build settings on the `xcodebuild` command line because fork-safe GitHub
runners have no Apple account or provisioning profile. Signed release archives,
notarization, and the distribution smoke test remain release-only steps with
explicit Apple credentials.

## Rollback

Remove the release and live appcast immediately. Restore the last known-good
appcast and DMG together so the feed never points to a missing or mismatched
asset. A helper protocol regression requires shipping a newer signed app; do
not weaken client authentication or delete active root state to roll back.
