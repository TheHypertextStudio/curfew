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
  `studio.hypertext.apps.curfew`.

The bundle namespace and preserved storage identities are documented in
[Curfew app identity](app-identity.md). Older release evidence describes the
pre-migration identifiers and does not establish acceptance of the new build.

## Required credentials

Curfew CI uses a dedicated Developer ID Application certificate and Developer-role
notarization API key for Studio team `T95VDD3A4W`. The six Apple inputs below are
configured in repository Actions secrets. The protected local backup lives at
`~/.config/curfew/release-credentials`; keep its files private and transmit secret
values through stdin. Existing Studio credentials remain active. Successful
`notarytool history` authentication does not establish artifact notarization.

Use `scripts/release-checklist.md` for the full business/infrastructure setup
(Stripe, Cloudflare Worker, Sparkle, landing page, Homebrew), and
`Documentation/license-worker-bootstrap.md` for the artifact-based native `cf`
issuer path. The selected staging profile points the retained issuer at
`license-staging.thecurfew.app`, using its separate KV, signer, and Stripe Sandbox
credentials. Verify that path before
production activation; do not create replacement production resources or copy
staging credentials. The shared artifact binds native, website, backend, and
license endpoints. Follow [production promotion](production-domain-promotion.md)
for the held activation gates.

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
     Developer ID provisioning profiles for `studio.hypertext.apps.curfew` and
     `studio.hypertext.apps.curfew.widget`. Require those exact bundle IDs and the Studio
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
     - `com.apple.security.application-groups = group.studio.hypertext.apps.curfew`
     - the retained same-team `keychain-access-groups` value
     - account `applinks` and `webcredentials` Associated Domains
   - It deliberately omits iCloud and `aps-environment` while CloudKit and
     push-backed sync are disabled. Reintroduce and validate those entitlements
     only in the release that enables `cloudSyncEnabled`.
   - `CurfewWidget/CurfewWidget.entitlements` must continue to carry:
     - `com.apple.security.app-sandbox = true`
     - `com.apple.security.application-groups = group.studio.hypertext.apps.curfew`

4. **Helper packaging**
   - The app bundle must contain:
     - `Curfew.app/Contents/Resources/curfew-daemon`
     - `Curfew.app/Contents/Library/LaunchDaemons/studio.hypertext.curfew.daemon.plist`
   - The plist must keep `BundleProgram = Contents/Resources/curfew-daemon`.
   - The Xcode bundle phase must sign `curfew-ctl`, `curfew-mcp`,
     `studio.hypertext.curfew.browser`, and `curfew-daemon` with
     `EXPANDED_CODE_SIGN_IDENTITY`; copying SwiftPM's ad-hoc linker signature
     into `Contents/Resources` is not sufficient.
   - `scripts/bundle-cli-tools.sh` forwards every resolved Xcode `ARCHS` entry
     to SwiftPM with `--arch`, then uses the same arguments with
     `--show-bin-path` instead of assuming a host-default output directory.
     Debug builds retain their active architecture and staging service flags.
   - The signed Release app and all five tools must contain both `arm64` and
     `x86_64` slices. `verify-release-artifact.sh` invokes the shared packaging
     verifier before signature checks and rejects any missing slice. Verify the
     final exported app; a universal main executable alone is insufficient.
     This changes packaging only, with no settings migration, helper identity,
     permission, or signing changes. Rollback must retain this architecture gate
     and use a previously accepted universal artifact; do not publish a thin
     helper as a workaround.

Profile identity validation reads Apple’s `ApplicationIdentifierPrefix` field.
Apple may encode Associated Domains authorization as the literal `*` string or
an array of permitted domains. Profile validation accepts those Apple formats;
the signed app still requests only its configured account host.

## Build against Curfew Sync staging

The isolated Dev app's Debug configuration selects staging by default. It binds
the staging account portal, OAuth issuer/resource, sync API, MCP resource, and
daemon command JWKS together; the bundle phase forwards the same setting to
every embedded SwiftPM executable.
Staging also uses a separate account-encryption Keychain service, so acceptance
testing cannot read or overwrite production account keys. The Debug app installs
`studio.hypertext.apps.curfew.dev.daemon`, and its root-owned state lives under
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
./scripts/swiftformat.sh Curfew CurfewTests CurfewUITests
./scripts/swiftformat.sh Curfew CurfewTests CurfewUITests --lint
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
The browser host uses `@main` in `CurfewBrowserMain.swift`; do not rename it to
reserved `main.swift`. SwiftPM must select library parsing for this entrypoint
on both architectures without a bundle-script compiler exception. Keep universal
linking and final signed-artifact verification as separate checks when changing
entrypoint packaging.

The CI `browser-bridge` manual scope isolates the universal browser product on
the hosted macOS/Xcode release toolchain. Normal full CI also packages unsigned
universal tools using the app's resolved `ARCHS`. Use the focused hosted result
to verify an entrypoint repair before tagging another candidate. A newer local
compiler's success is supporting evidence; it does not establish that the
release toolchain or signed archive passed.

The verifier checks Sparkle, the existing production feed, public key, Widget, all
five embedded executables, nested signatures, Developer ID Application authority, Studio team,
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

## Explicit local-build publication

An owner-authorized local build can use the same signed-device and operational
acceptance gates when the signed candidate workflow is unavailable. This is a
separate provenance path: it never assigns a GitHub run ID to a local archive or
treats a failed workflow as successful. The hosted candidate path is unchanged.

Keep the exact DMG, feed, `release-configuration.json`, and
`environment-artifact.json` together in the publication directory's `candidate/`
folder. Keep execution evidence in a private `local-evidence/` folder:

- `quality.json` records schema version 1, a locally assigned UUID v4
  `executionID`, the actual `observedAt`, `sourceCommit`,
  `configurationSHA256`, and `hostedRunClaimed: false`. Its `fullAppTests`
  records positive passed tests and zero failed or skipped tests. Its `checks`
  contain the actual zero exit codes for `just check`,
  `swift test --package-path CurfewKit`, and `just build-release`, with each
  command's retained log filename and SHA-256 digest. Preserve the execution
  time when recording existing evidence; a new record does not refresh a test.
  An operator must review the original test results and timestamps: hashes
  protect retained records from substitution, not independently attest that
  a command ran or passed.
- Each log must be a nonempty regular file in that directory. Logs and signing
  evidence remain private; do not place them in the public release assets.
- `signing.json` retains the actual local signing receipt: `verifiedAt`,
  `sourceCommit`, `deploymentSHA256`, `releaseConfigurationSHA256`, `version`,
  `developerIDTeam`, `dmgSHA256`, `appcastSHA256`, `hostedRunClaimed: false`,
  `notarizationAccepted: true`, `ticketStapled: true`, and
  `gatekeeperAndSourceArtifactVerifierPassed: true`.

On the clean reviewed publication commit, record the candidate without changing
its retained release bytes:

```sh
node scripts/local-release.mjs record /private/publication/candidate /private/publication/local-evidence /private/frozen-native-source
```

This verifies the log digests, source/configuration identities and evidence
age, rechecks the DMG's stapled ticket, mounts the exact image read-only, and
runs the existing full app verifier on its embedded app from the exact clean
native-source checkout. That checkout must still be at the signed app's source
commit; this also fixes every transitive verifier input to its reviewed version.
The temporary mount
is removed even when app verification fails. Schema version 2 `candidate.json`
contains explicit local provenance and evidence digests, with no hosted run ID.
Seven days is the maximum evidence age, not permission to reuse evidence after
relevant behavior or provider changes.

Retain the existing verified website, `website-build/website-build.json`,
`identity/environment-artifact.json`, and successful matching `website-run.json`.
Add `local-authority.json` with the reviewed `publicationCommit` and the absolute
`nativeRepository` path to the frozen native-source checkout. That commit
must be the clean current checkout and a descendant of the signed app's source;
native source, dependencies, deployment manifest and native verification inputs
must be identical. The public release tag continues to name the original signed
app commit. A later publication, website or issuer change does not relabel the
app's source or rebuild its bytes.

Use the existing `publication.mjs prepare`, `ready`, `publish`, and `verify`
commands with this directory. In addition to every existing owner gate, the
private acceptance receipt needs a `stagingAcceptance` gate with outcome `pass`
and a reference to actual staging acceptance. The owner receipt must still be
less than one hour old. Candidate/log substitutions, missing or failed tests,
source drift, stale evidence, missing staging acceptance, and failed OS trust
checks stop admission before publication output is written. The local route
does not enable sales, waive recovery or device checks, or establish production
behavior from staging results. Revert the publication-source change to remove
this route; retain published release bytes and the hosted route's guarantees.

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

1. Confirm `studio.hypertext.apps.curfew.widget` appears in `pluginkit -m -A -D`.
2. Add each supported Curfew widget from the gallery.
3. Change the schedule and verify the widget refreshes from the App Group.
4. Verify both signed production targets and profiles authorize
   `group.studio.hypertext.apps.curfew`. Curfew Dev retains the
   `group.studio.hypertext.curfew.studio.dev` group from former Studio Dev installs;
   Studio Dev is not a separate supported build.
5. Verify existing settings regenerate widget snapshots in the new group while
   canonical databases stay in Application Support. An older activity database
   still migrates from the legacy `group.studio.hypertext.curfew` path; do not
   move that historical source to the new snapshot container.

### Authenticated helper

1. Install and approve the helper in Settings; verify the UI reports a ready
   authenticated channel. Check its registration with
   `launchctl print system/studio.hypertext.curfew.daemon`.
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

For a subscription, also observe the actual signed expiry with unchanged system
time. Plus status and activation success must update on the next display-clock
cycle, including while enforcement is off or windows are closed. App-return and
wake entrypoints also reevaluate when invoked; the existing wake observers run
while enforcement is armed. A disarmed app resumes reevaluation on its display
clock or app activation. Keep the verified key and free schedule
available. Confirm a replacement lifetime/new subscription ignores the former
deadline, while restore progress, its result and errors survive expiry. Only
explicitly enabled Plus modules should stop; retained key/signature fixtures do
not establish this final signed-app behavior.

### Sparkle staging upgrade

1. Produce an older signed `0.0.x` validation build with an isolated staging feed.
2. Publish a staging appcast for the newer signed `0.0.x` candidate using the same
   EdDSA key and candidate DMG.
3. Install the older build, choose **Check for Updates…**, and complete the upgrade.
4. Verify the relaunched app is the exact signed candidate and Gatekeeper
   accepts it.

The existing **Signed installer acceptance** workflow has an opt-in
`staging-upgrade` mode for this gate. It uses the retained signed `0.0.8`
artifact as its older validation build and requires an explicit newer `0.0.N`
version (strictly greater than `0.0.8`), release run, source commit, and DMG
SHA-256. Dispatch it from that same frozen source after both packaging and
acceptance tooling are integrated:

```bash
gh workflow run signed-installer-acceptance.yml --repo TheHypertextStudio/curfew \
  --ref "$CANDIDATE_SOURCE_COMMIT" \
  -f mode=staging-upgrade \
  -f candidate_version="$CANDIDATE_VERSION" \
  -f candidate_run_id="$CANDIDATE_RUN_ID" \
  -f candidate_source_commit="$CANDIDATE_SOURCE_COMMIT" \
  -f candidate_dmg_sha256="$CANDIDATE_DMG_SHA256"
```

The baseline's original verifier checks its retained bytes; the new candidate
uses the final source's artifact verifier, including universal executable
checks. Origin, hashes, configuration, and the unchanged EdDSA key are verified
before either artifact is used. The mode never substitutes a newer candidate.

On the disposable hosted Mac only, the driver applies Sparkle's documented
testing `SUFeedURL` defaults override. It serves a derived appcast and the exact
candidate DMG from `http://localhost:<ephemeral-port>/`, bound only to loopback.
Sparkle's pinned downloader supports HTTP/HTTPS and rejects `file:` URLs. Its
local-network testing warning is distinct from a browser security interstitial;
never bypass a browser warning. No ATS exception, TLS setting, signature gate,
public feed, Access policy, or installed owner preference changes are needed.

The actual UI must offer the selected version and complete **Install Update →
Install and Relaunch**. A changed process ID establishes relaunch; the final
verifier compares every installed bundle file and symlink against the mounted
candidate. Retain both subjects, the derived feed, transfer log, screenshots,
UI results, and installed verification. Always remove only the disposable
user's owned feed override and stop its loopback server, including on failure.
The updated bundle retains the canonical feed; cleanup verifies the override
is absent. Withholding or failing this test is not a successful upgrade.

This fresh older-build upgrade establishes Sparkle trust and installation only.
It does not establish the owner's populated `0.0.9` upgrade, saved credentials,
licenses, schedules, permissions, helper approval, or active enforcement
continuity. Keep those installed-device journeys separate. The original
fresh-installer workflow mode also remains available.

Fresh-installer acceptance likewise checks each retained candidate using the
verifier from its own immutable source. Only after validating the tagged run,
artifact origin, configuration, DMG hash, and EdDSA signature does preparation
export the candidate's full source SHA for a separate checkout. Historical
signed builds therefore retain their original checks; a new candidate uses its
own newer checks, including universal executables. It also runs that immutable
producer's own `testFreshSignedInstallerOpensRealSetup` against the installed
signed app. A producer without this walkthrough fails clearly; the retained
`0.0.8` build is an upgrade baseline only. Do not substitute current UI tests or
a historical verifier for another candidate.

Pull requests run fast harness boundary tests; normal native CI compiles the
current UI tests. Actual signed installation runs only after a candidate exists,
by dispatching `fresh-install` with the same four explicit candidate inputs as
above. Both fresh installation and the real older-to-newer Sparkle upgrade must
pass against the same exact release subject. A passing PR check establishes
neither installed outcome. Missing or failed receipts keep release acceptance
open; these changes do not waive any installer or updater gate.

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
node scripts/release-candidate.mjs inspect /private/downloaded-candidate /private/owner-receipt.json
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

The Sparkle seed remains in GitHub Actions. `scripts/sparkle-public-key.mjs`
accepts the base64-encoded 32-byte seed used by the provisioning script and
prints only its public key. Missing or malformed material stops the job before
archiving. Release receives that key as an Xcode build setting; do not copy the
Debug key or generate a replacement to resolve a placeholder. The published
RFC 8032 test vector and a signature from the pinned Sparkle binary verify the
derivation independently of the retained production secret.

Before preparing publication, review the version-specific notes in
`landing/releases/<version>.html`. The publisher requires notes for the candidate
version and wraps them in the retained website’s existing page shell. The derived
site includes `/releases/<version>.html`, matching the signed updater feed, and
GitHub release notes link to that page. The retained website, DMG and appcast stay
unchanged. Inspect the prepared page on desktop and mobile; live publication
verification also requires the notes page to respond with the correct version.
The retained hosting configuration redirects the signed `.html` notes address to
its clean URL; verification follows only that exact same-origin redirect and
rejects unexpected destinations or further redirects. The page’s canonical link
and GitHub release notes use the clean URL.
Missing notes do not waive any owner-acceptance or source-identity gate. When
using an operator worktree to run publication tooling, review its exact diff and
keep remote main pinned to the candidate until the hosted publication completes.

Production publication requires the Cloudflare deployment credential and the
accepted production marketing Worker. Publish its matching retained static output
with the pinned native `cf` build/prebuilt deployment path and provisioning
disabled. Preserve Mintlify bindings and service route ownership; Pages is not a
publication or rollback dependency. Independent website fixes do not authorize
installer, appcast, account-service or purchase activation.

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


## Background supervisor release gate

The release maintainer must validate a signed staging candidate before shipping background recovery. Merging the source does not close this gate. The October 23 integration retains current main's Studio signing identities, development App Group, explicit schedule consent, authenticated helper maintenance, and isolated demo services.

Build Debug with `CURFEW_SERVICE_SWIFT_FLAG=CURFEW_STAGING` under company team `T95VDD3A4W`. The Xcode phase passes that flag to both the app and supervisor. Use the development app and `studio.hypertext.apps.curfew.dev.supervisor`; production uses `studio.hypertext.apps.curfew.supervisor`. Ordinary Debug launches and test hosts never register recovery automatically. The signed acceptance fixture additionally requires `CurfewAcceptanceFixture=true` in its bundle and the `--supervisor-acceptance` argument. Its stores are temporary, its service collaborators are inert, and shutdown stays disabled.

1. Register through `SMAppService.agent`. Record its status and `launchctl print gui/$(id -u)/studio.hypertext.apps.curfew.dev.supervisor`. Verify approval-required and failed-registration states in Protection settings.
2. Start before the fixture deadline with `--background`. Capture zero ordinary windows and then the lockout overlay. Quit before curfew and Force Quit during lockout. Record replacement PIDs, recovery delay, overlay restoration, and quiet startup. Concurrent opens must reuse one process; a deliberate foreground open must present the workspace.
3. After explicit staging Accessibility approval, opt in with the bundle Boolean `CurfewAcceptanceKeyboardShield` and re-sign. Verify a blocked Quit shortcut and an enabled tap after process recovery. Ordinary captures and unit hosts cannot install the tap. Inspect actual Accessibility trust and `enforcementHealth` in the local report instead of trusting a Settings checkbox.
4. Log in during lockout and physically sleep/wake across curfew on an isolated host. Verify quiet login and immediate wake evaluation. Timer or process-list mocks do not prove either event.
5. Use isolated durable stores to verify extension, snooze, override, and spent weekly-budget restoration. The temporary capture fixture does not prove persistence across native processes. Revoke Accessibility and background-service approval to verify each degraded state and recovery. Confirm the legacy agent is removed only after supervisor registration succeeds.
6. Unregister before removing state. Stop the app, wait at least 10 seconds, and verify neither app nor supervisor returns. Confirm production state and service identities remain intact. Homebrew uninstall and upgrade must unregister before quitting; refusal must abort removal.

Retain signatures, service status, state reports, PIDs, CI results, and screenshots with the candidate. The October 4 branch recorded native quiet Quit/Force Quit recovery and concurrent-launch reuse under the older development identity. That evidence does not validate the current signed identity or replace the checks above. Local unsigned UI execution on October 23 failed before runner bootstrap; isolated CI provides graphical regression evidence for the integrated source.

Roll back by unregistering the supervisor before installing the prior app. Preserve user settings and runtime JSON. A brief recovery gap remains after process termination. Deliberate service disabling and repeated process killing remain outside this version's guarantee. The optional root helper retains its existing signed deadline and release rules.
