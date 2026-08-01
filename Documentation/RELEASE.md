# Release runbook

Maintainer-run steps for producing a signed Curfew build and validating the
surfaces that **cannot** be proven in ad-hoc local builds. Repo-local tests
cover the app logic; this file covers the release-only path for:

- Apple Events-backed shutdown
- WidgetKit signing + App Group reads
- `SMAppService` privileged helper install/status
- CloudKit / push entitlements and real container access
- notarization / Gatekeeper / DMG smoke testing

Keep claims conservative: nothing below is considered complete until a
maintainer executes it on a signed build with real Apple credentials.

## One-time external setup

Use `scripts/release-checklist.md` for the full business/infrastructure setup
(Stripe, Cloudflare Worker, Sparkle, landing page, Homebrew). The Apple
release identifiers that must stay aligned are:

- App bundle ID: `studio.hypertext.curfew`
- Widget bundle ID: `studio.hypertext.curfew.widget`
- App Group: `group.studio.hypertext.curfew`
- CloudKit container: `iCloud.studio.hypertext.curfew`
- Privileged LaunchDaemon label: `studio.hypertext.curfew.daemon`

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

## Build a local signed release candidate

The CI release workflow uses the same archive/export path shown here. Running it
locally is the fastest way to validate shutdown/widget/helper/CloudKit behavior
before pushing a tag.

```bash
TEAM_ID="<your 10-character Apple team id>"
ARCHIVE_PATH="$PWD/build/Curfew-Release.xcarchive"
EXPORT_PATH="$PWD/build/release-export"
EXPORT_PLIST="$PWD/build/ExportOptions.plist"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$EXPORT_PLIST"

xcodebuild archive \
  -project Curfew.xcodeproj \
  -scheme Curfew \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID"

cat > "$EXPORT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>developer-id</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>manual</string>
</dict>
</plist>
EOF
```

Then export:

```bash
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST"
```

At that point the signed app should live at:

```bash
APP="$EXPORT_PATH/Curfew.app"
WIDGET="$APP/Contents/PlugIns/CurfewWidget.appex"
HELPER="$APP/Contents/Resources/curfew-daemon"
HELPER_PLIST="$APP/Contents/Library/LaunchDaemons/studio.hypertext.curfew.daemon.plist"
```

## Inspect the signed artifact before UI testing

Run these checks first so entitlement or packaging regressions are caught before
you start clicking through the app:

```bash
codesign --verify --deep --strict --verbose=2 "$APP"
spctl --assess --type execute --verbose "$APP"
codesign -d --entitlements :- "$APP"
codesign -d --entitlements :- "$WIDGET"
plutil -p "$HELPER_PLIST"
ls "$WIDGET" "$HELPER" "$HELPER_PLIST"
```

From the entitlement dumps, confirm:

- **App (v0.1)**: Apple Events automation and the App Group are present; iCloud
  and `aps-environment` are absent while CloudKit sync is disabled.
- **Widget**: sandbox + the same App Group are present.
- **Helper plist**: `Label = studio.hypertext.curfew.daemon` and
  `BundleProgram = Contents/Resources/curfew-daemon`.

If any of those are missing, stop there and fix signing/project settings before
trusting any manual smoke test result.

## Signed-build validation checklist

### 1. Shutdown (Apple Events)

Only the signed Release build carries the Apple Events entitlement, so this
check must be run from the exported app or notarized DMG install.

1. Install or copy the signed app to `/Applications/Curfew.app`.
2. Launch Curfew and open **Settings → Enforcement**.
3. Confirm the auto-shutdown controls are visible. (Debug/ad-hoc builds should
   keep them hidden.)
4. Set a short shutdown delay and move curfew a few minutes into the future.
5. Wait for lockout:
   - the lockout screen should show the shutdown countdown first
   - then Curfew should request a shutdown through `System Events`
6. If macOS prompts for Automation approval, grant Curfew permission to control
   **System Events**. If you deny/dismiss it, confirm Curfew stays locked,
   does **not** keep retrying the denied shutdown path, and shows recovery
   guidance that points to **Privacy & Security → Automation → Curfew → System Events**.
7. After the run, inspect **System Settings → Privacy & Security → Automation**
   and record whether Curfew is allowed to control System Events.

Treat this as **not release-ready** if the signed build still hides shutdown,
never prompts for Automation, or fails both attempts without an explainable OS
prompt state.

### 2. WidgetKit extension + App Group storage

The widget target is wired, but its real entitlement path only exists on the
signed Release build.

1. Confirm the extension is registered:
   ```bash
   pluginkit -m -A -D | grep -F studio.hypertext.curfew.widget
   ```
2. Add the Curfew widget from the macOS widget gallery. If it never appears,
   treat that as a signing/packaging failure.
3. Use a build where Pro/widget gating is intentionally enabled, then confirm:
   - the widget renders current phase / schedule data
   - changes in the app update the widget on the next timeline refresh
4. Confirm the shared App Group container contains the mirrored files:
   ```bash
   ls ~/Library/Group\ Containers/group.studio.hypertext.curfew/Curfew
   ```
   Expected artifacts include:
   - `widget-settings.json`
   - `activity.sqlite3`
5. While changing schedule/settings in the app, you can watch the mirroring path:
   ```bash
   log stream --predicate 'subsystem == "studio.hypertext.curfew" AND category == "widget-shared-state"' --info
   ```

Treat WidgetKit as **not release-ready** if the widget is missing from the
gallery, lacks the App Group entitlement, or never reflects shared-container
state from the signed app.

### 3. Privileged helper + login item

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
6. Log out or reboot once and confirm:
   - Curfew relaunches as expected
   - the daemon remains installed/approved
   - helper status in Settings still reflects reality
7. Uninstall via the app (or `scripts/uninstall.sh`) and confirm the helper and
   login-item statuses return to the uninstalled state.

Treat the helper path as **not release-ready** if installation only appears to
work in-app, the LaunchDaemon never shows up in `launchctl`, or the sentinel
file never appears during a real lockout.

### 4. CloudKit + push-backed sync

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

### 5. Final signed-app / DMG smoke test

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
3. Tag the release: `git tag v0.1.0 && git push origin v0.1.0`
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

- Yank the GitHub release asset and replace it with the previous DMG.
- There is no active in-app updater in the default build today; rollback is a
  manual re-download.
