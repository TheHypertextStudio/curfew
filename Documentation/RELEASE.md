# Curfew 0.0.x candidate and activation runbook

Public activation is blocked until actual signed-device, provider, retained-data
and operational evidence exists for the exact candidate. Current evidence lives in
`Documentation/release-evidence/v0.0.1.md`; the old v0.1 ledger is historical, not
approval to use a non-0.0.x version. A local build is not distribution proof.

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
- App identity: Hypertext Studio, LLC team `T95VDD3A4W`, bundle ID
  `studio.hypertext.curfew`.

## Required credentials

Curfew CI uses a dedicated Developer ID Application certificate and Developer-role
notarization API key for Studio team `T95VDD3A4W`. The six Apple inputs below are
configured in repository Actions secrets. The protected local backup lives at
`~/.config/curfew/release-credentials`; keep its files private and transmit secret
values through stdin. Existing Studio credentials remain active. Successful
`notarytool history` authentication does not establish artifact notarization.

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

Candidate retention in this **public repository is publicly retrievable by
signed-in readers**, not private/internal distribution. By default signing and
upload are blocked. The owner must explicitly approve that exposure by setting
`CURFEW_PUBLIC_CANDIDATE_RETENTION_APPROVED=true`, or first implement/review an
access-controlled retention path. This source change does not set the variable
or authorize widening an internal build's distribution.

1. **Apple signing + notarization credentials**
   - `APPLE_TEAM_ID`
   - `APPLE_CERTIFICATE`
   - `APPLE_CERTIFICATE_PASSWORD`
   - `APPLE_API_ISSUER`
   - `APPLE_API_KEY_ID`
   - `APPLE_API_PRIVATE_KEY`
   - `APPLE_PROVISIONING_PROFILES`: a JSON array containing the Base64-encoded
     Developer ID provisioning profiles for `studio.hypertext.curfew` and
     `studio.hypertext.curfew.widget`. Keep the original identifiers and Studio
     team; do not substitute Personal Team or development profiles.
   - Export the approved profiles to the existing private Secret Manager entry
     `curfew-apple-provisioning-profiles` and the repository secret. Never put
     their contents in workflow inputs, source files, or release artifacts.

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
   - The conservative initial `Curfew/Curfew-Release.entitlements` carries:
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

Prefer the retained CI candidate. For an explicitly authorized local build, the
owner must supply the existing private seed securely; never retrieve/export a
GitHub secret, generate a replacement key, or assume a Debug key matches. On the
exact clean candidate commit, generate the shared endpoints, then resolve and seal the Release inputs:

```bash
mkdir -p release
node scripts/deployment-config.mjs generate
SPARKLE_PUBLIC_KEY=$(node scripts/release-candidate.mjs derive-update-key)
env -u SPARKLE_PRIVATE_KEY xcodebuild -showBuildSettings -json \
  -project Curfew.xcodeproj -scheme Curfew -configuration Release \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  INFOPLIST_KEY_SUPublicEDKey="$SPARKLE_PUBLIC_KEY" > release/resolved-settings.json
node scripts/release-candidate.mjs verify-update-key release/resolved-settings.json
node scripts/release-configuration.mjs record \
  release/resolved-settings.json release/release-configuration.json > release/release-configuration.sha256
CURFEW_CONFIGURATION_SHA256=$(node -p "JSON.parse(require('fs').readFileSync('deployment/generated/environment-artifact.json')).sha256")
```

```bash
xcodebuild archive \
  -project Curfew.xcodeproj \
  -scheme Curfew \
  -configuration Release \
  -destination 'platform=macOS' \
  -archivePath build/Curfew-Release.xcarchive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY='Developer ID Application' \
  DEVELOPMENT_TEAM=T95VDD3A4W \
  MARKETING_VERSION=0.0.1 CURRENT_PROJECT_VERSION=0.0.1 \
  INFOPLIST_KEY_SUPublicEDKey="$SPARKLE_PUBLIC_KEY" \
  CURFEW_CONFIGURATION_COMMIT="$(git rev-parse HEAD)" \
  CURFEW_CONFIGURATION_SHA256="$CURFEW_CONFIGURATION_SHA256"

bash scripts/verify-release-artifact.sh build/release-export/Curfew.app \
  release/release-configuration.json 0.0.1
```

Seal the shared endpoint artifact and resolved signing key with `scripts/release-configuration.mjs` at the exact clean candidate commit before archiving. The generator creates deterministic endpoint inputs; the release snapshot records their digests.
Export with `method=developer-id`, then notarize and staple before verification.
The candidate job derives the public update key from the existing private seed
in process memory, passes it explicitly as `INFOPLIST_KEY_SUPublicEDKey`, and
checks resolved Release settings before archive. The source placeholder remains
fail-closed for local archives without that explicit verified override. Never
assume a Debug key matches, print the private seed, or rotate it to get a pass.
The verifier checks Sparkle, the existing production feed, public key, Widget, all
four embedded executables, nested signatures, Developer ID Application authority, Studio team,
exact 0.0.x version, embedded configuration hash/commit, Gatekeeper, stapling and
exact app entitlements.

## Release automation

For a strict `v0.0.x` tag, `.github/workflows/release.yml`:

1. Runs the unsigned quality gate and rejects placeholder or missing keys.
2. Imports the Developer ID certificate only after quality checks finish, then
   validates and installs both approved production profiles. Archive and export
   select their exact UUIDs separately for the app and widget. Unsigned
   quality-check dependencies must not run with the certificate or temporary
   signing keychain available.
3. Notarizes and staples the app.
4. Verifies the app artifact.
5. Builds, signs, notarizes, and staples the DMG.
6. Signs an appcast whose enclosure identifies the future exact GitHub asset.
7. Verifies that signature with the public key from the signed app and records
   DMG/feed hashes, Studio team, version, run, source and configuration identity.
8. Retains `curfew-signed-candidate` for 30 days, with DMG, appcast, configuration,
   manifest and notarization receipts. It does not publish a GitHub Release,
   deploy a site/feed, or access Cloudflare secrets.

After signing and before upload, an always-run cleanup removes the job-owned temporary signing
keychain (including the imported private key), certificate P12 and notarization
P8, plus job-installed provisioning profiles and their temporary configuration.
The installer rejects wrong bundles/teams, expired or development profiles, and
missing account association authority before installation. Apple/Xcode still
validate the signed profile and certificate during archive/export; source tests
do not prove that an issued production profile is available or usable.
Existing installed profiles and auxiliary files are never replaced. Independent
always-run profile cleanup checks ownership and recorded digests, and refuses to
delete changed files. It still runs if certificate cleanup fails. Any cleanup
failure blocks upload and diagnostics name only basenames. The
artifact action is pinned to official v7.0.2 commit
`cf430e030ddbb5b0abf93d22962f4752f3646cd9`, verified through GitHub's official tag
and action metadata. No real local signing credential is deleted by source tests.

Any failure withholds the candidate. Download the retained artifact from the exact
successful run and review its manifest/run provenance before validation on an
authorized Mac. Expired artifacts must be rebuilt and revalidated. Do not announce
or update Homebrew until actual acceptance passes. Historical Studio Dev evidence
does not close these production gates.

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

1. Download the retained candidate DMG from its exact Actions run, not a local replacement.
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

1. Produce an older signed `0.0.x` validation build with an isolated staging feed.
2. Publish a staging appcast for the newer signed `0.0.x` candidate using the same
   EdDSA key and candidate DMG.
3. Install the older build, choose **Check for Updates…**, and complete the upgrade.
4. Verify the relaunched app is the exact signed candidate and Gatekeeper
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

## Controlled activation (manual and withheld)

No tag is permission to activate. There is no autonomous activation workflow
until backend/provider cutover can safely coordinate it. The owner reviews actual
evidence, not only green jobs or self-asserted JSON.

Before creating any tag, read `git ls-remote origin refs/heads/main` and compare
its exact 40-character SHA with the reviewed and fully tested candidate commit.
Inspect `git show <that-exact-sha>:.github/workflows/release.yml` and confirm the
candidate-only workflow, public-exposure admission and unsigned quality gate
exist in that commit. Recheck no matching local/remote tag exists immediately
before tagging. If the SHA differs, checks are stale, or the workflow is older,
stop: tagging a historical commit executes its historical publishing workflow,
even when the current default branch has been fixed. Never retag old source or
rewrite an immutable tag. A successful preflight is not authority to push a tag.

After real acceptance, save an owner receipt outside the candidate directory.
`candidate` is an exact copy of retained `candidate.json`; `operator` names the
observer; `observedAt` is the ISO observation timestamp. `gates` contains
`signedDevice`, `retainedDataRecovery`, `providerIdentity`, `backendCutover`,
`assistantReconnect`, `rollback` and `commercialScope`. Each has `outcome: "pass"`
and an `evidence` reference to actual observations. Never generate passing
evidence to satisfy the inspector. Commercial scope must retain disabled sales
while the production billing stop remains.

Run the read-only gate:

```bash
node scripts/release-candidate.mjs inspect <downloaded-candidate-directory> <owner-receipt.json>
```

It fails closed on changed bytes, signature, configuration, team, version or
missing/mismatched evidence. An eligible result permits owner review only; it
does not authenticate evidence, perform cutover or establish production success.

Production activation uses `.github/workflows/activate-production.yml` after
signed-device, account/provider, recovery, assistant and rollback acceptance.
Follow [the domain migration runbook](domain-migration.md) for the coordinated
service, website, provider and update-feed cutover. Publish only the exact
retained candidate and matching website bytes through the production Worker.
The activation workflow adds the signed feed to the verified static output and
uses native build/prebuilt deployment without provisioning or rebuilding Astro. Verify the live feed and
downloaded DMG hash against the candidate before announcing. If any gate is
missing, withhold activation; never use a receipt as production proof or enable
sales while the commercial stop remains.

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

For the first release there may be no prior feed or artifact. In that case
withdraw the new feed/download links and restore the reviewed unavailable state,
keep affected service access in maintenance, and issue a corrected newer signed
candidate after acceptance. Do not restore an invented older feed, redirect a
client into an obsolete authority, or revive revoked sessions. Withdrawing an
Actions artifact requires an explicit owner decision; retention approval does
not imply it is private. Never reinstall/restart a helper or overwrite its
state as rollback during active enforcement.

## Domain migration release

Use the shared endpoint artifact and the pinned cf build/deployment commands in `domain-migration.md`. Protocol 0.0.13 is the domain-independent contract. A signed native release, verified callback associations, provider registrations, account recovery audit and production acceptance remain required; local unsigned builds do not satisfy them.

The domain migration uses the shared endpoint artifact for native and backend configuration identity. The retained release snapshot additionally binds the resolved Sparkle public key and source digests; it does not substitute its own hash for the endpoint identity. See `domain-migration.md` for preparation, activation and rollback requirements.
