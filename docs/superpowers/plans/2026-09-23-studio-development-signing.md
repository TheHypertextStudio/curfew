# Hypertext Studio Development Signing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce an isolated, company-signed Curfew staging app that can complete real account enrollment and phone-to-Mac remote lock/unlock without changing the personal-team installation.

**Architecture:** Add one third build flavor whose local identities are disjoint from production and personal development. Give its Xcode configuration a distinct app wrapper and company entitlements. Gate the staging daemon against higher-priority ownership and disable root shutdown/cancellation in this test vehicle; then authorize its exact app identity in staging and verify the complete signed runtime chain.

**Tech Stack:** Swift 5, SwiftUI/AppKit, SwiftPM, Xcode project, macOS ServiceManagement/Keychain/Associated Domains, Cloudflare coordinator, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-23-studio-development-signing-design.md`

## Global Constraints

- Preserve production and personal Debug bundle IDs, local data, Keychain services, daemon labels, and signing teams byte-for-byte.
- Use `T95VDD3A4W`, `studio.hypertext.curfew.studio.dev`, `studio.hypertext.curfew.studio.dev.widget`, and `group.studio.hypertext.curfew.studio.dev` for StudioDev.
- Use only `curfew-*.hypertext.studio` staging hosts; never the retired Curfew apex domain.
- Keep app and protocol versions in `0.0.x`; avoid a protocol schema change unless a demonstrated wire-format need forces the three-repository release ceremony.
- Do not install an unsigned or colliding bundle, invoke production `scripts/uninstall.sh` for StudioDev, merge or squash commits, or clear another flavor's state.
- Keep one cohesive implementation commit with a high-level subject, explanatory body, and `Co-authored-by: Codex <noreply@openai.com>`; the user's instruction against many small versioned commits overrides the skill's default per-task commits.
- Update `Documentation/todos.md` and `Documentation/todo-test-matrix.md` with implementation, test, operational, risk, and rollback notes.

## Review Focus

- A bundle ID ending `.studio.dev` must resolve to StudioDev before the generic `.dev` fallback; Task 1 tests the app and widget IDs.
- A failed or copied environment propagation must not send a helper to production paths; Task 1 tests literal daemon/Claude/native-host identities and Task 3 inspects the built helper environment.
- An active personal owner plus a stale StudioDev heartbeat must not trigger a StudioDev shutdown; Task 2 tests this through the daemon decision/effects boundary.
- A StudioDev uninstall must not reveal or delete `/Applications/Curfew.app`; Task 3 tests target paths and checks the built wrapper.
- A valid passkey page and OAuth code are insufficient if the signed callback or remote command never reaches this Mac; Task 5 records each live transition through lock and unlock.

---

### Task 1: Closed-world StudioDev identities

**Files:** Modify `Sources/CurfewKit/Settings/CurfewFlavor.swift`, `Sources/CurfewKit/Sync/CurfewServiceEndpoints.swift`, `Sources/CurfewKit/Sync/DocketServiceEndpoints.swift`, `Curfew/Core/Features/DeviceAssertionSecretStore.swift`, `Curfew/Core/Features/DocketBrowserPolicyClient.swift`, `Curfew/Info.plist`, `Curfew/App/MCP/ClaudeDesktopRegistration.swift`, `Curfew/App/Infrastructure/BrowserNativeRuntime.swift`, `Sources/curfew-browser/main.swift`. Test `CurfewTests/Core/CurfewFlavorTests.swift`, `CurfewTests/Core/Sync/DocketBrowserPolicyClientTests.swift`, `CurfewTests/Core/Sync/AccountOAuthEnrollmentTests.swift`, and `Tests/BrowserNativeHostTests/BrowserNativeInstallationTests.swift`.

**Interfaces:** `CurfewFlavor.studioDevelopment`, `.identifierSuffix == ".studio.dev"`, `.displaySuffix == " (Studio Dev)"`, `.enforcementPriority == -100`; `DocketOAuthAuthorizationRequest.callbackScheme(for:)`; flavor-specific account and Docket Keychain services. Existing flavor values stay unchanged.

- [ ] Write table-driven failing tests resolving `studio.hypertext.curfew.studio.dev` and `.studio.dev.widget`, plus `CURFEW_FLAVOR=studioDevelopment`, and assert literal unique suffix, defaults/App Group, daemon label, browser host, Claude key, Docket scheme, and Keychain service values. Include a test that unknown flavor still follows the existing safe default.
- [ ] Run `xcodebuild test -project Curfew.xcodeproj -scheme Curfew -destination 'platform=macOS' -only-testing:CurfewTests/CurfewFlavorTests CODE_SIGNING_ALLOWED=NO` and confirm the new assertions fail for the missing third flavor.
- [ ] Add `case studioDevelopment` and resolve it before the `.dev` segment fallback. Make app-launched MCP, daemon plist, and browser-host environment use `studioDevelopment`; keep existing `production` and `development` raw values and paths unchanged. For example:

  ```swift
  if identifier == "studio.hypertext.curfew.studio.dev" ||
     identifier == "studio.hypertext.curfew.studio.dev.widget" {
      return .studioDevelopment
  }
  ```

- [ ] Give StudioDev distinct Curfew/Docket/legacy assertion Keychain services and a Docket callback scheme used consistently by `Info.plist`, authorization request, callback validator, and dynamic registration. Keep the existing two flavors' scheme `studio.hypertext.curfew`.
- [ ] Keep the StudioDev Chrome native runtime inactive and make its task-browser panel say that this staging build cannot test that integration, without disabling account enrollment/local MCP/remote-command features. Verify it never installs or claims the personal development extension host.
- [ ] Re-run the targeted Curfew flavor, Docket callback, account endpoint, and native-host suites; verify the identity matrix has no duplicate mutable path or service.

### Task 2: StudioDev daemon stand-down and non-destructive effects

**Files:** Modify `Curfew/App/Infrastructure/EnforcementOwnership.swift`, `Sources/CurfewKit/Settings/CurfewFlavor.swift`, `Sources/CurfewKit/Sync/DaemonRemoteCommandController.swift` or its backend injection point, `Sources/curfew-daemon/main.swift`, and daemon test files under `CurfewTests/App/Infrastructure/` and `Tests/CurfewKitTests/`. Add a focused pure owner-policy unit if moving the record from the app target into CurfewKit is necessary for the daemon.

**Interfaces:** One testable `StudioDevDaemonSafety` decision accepts flavor, decoded owner, verified owner liveness, and heartbeat age; it returns whether StudioDev may apply a new remote lock and whether shutdown effects may run. The remote backend uses the existing `.rejected`/`.ineligible` result when a live higher-priority owner denies enforcement. Other flavors retain current behavior.

- [ ] Add failing tests with literal owner records for production and personal development, a live owner, and a stale StudioDev heartbeat. Assert no StudioDev shutdown and no `.applied` result for a new lock while the higher-priority owner remains live. Add a dual-daemon effect test proving StudioDev neither invokes `/sbin/shutdown` nor calls global `pkill -x shutdown` on unlock/stand-down.
- [ ] Run the focused daemon suites and confirm those new tests fail against the current daemon loop, which does not consult the ownership record.
- [ ] Extract the owner record/policy into a shared testable boundary if needed. The daemon must verify the recorded process is live and has the recorded bundle identity before granting the higher-priority owner authority; an unreadable/unknown record cannot grant an attacker a lasting denial of enforcement.
- [ ] Inject the ownership check into the StudioDev remote-command backend before its `DaemonRemoteCommandController` decides eligibility. Use existing rejection code `.ineligible` when denied; do not add a new wire result shape. Re-check ownership in the loop before applying enforcement effects.
- [ ] Use a StudioDev-only effects implementation that cannot run or cancel root shutdown, even if another guard regresses. Keep local/remote deadline processing, signed command verification, results, and app lockout intact.
- [ ] Re-run focused daemon suites and all existing enforcement/remote-command tests; compare production and personal-development outcomes to their prior fixtures.

### Task 3: Distinct Xcode product and scoped uninstall

**Files:** Modify `Curfew.xcodeproj/project.pbxproj`, `Curfew/Info.plist`, `Curfew/App/Infrastructure/UninstallCoordinator.swift`, `Curfew/UI/SettingsView+UninstallPanel.swift`. Create `Curfew/Curfew-StudioDev.entitlements`, `CurfewWidget/CurfewWidget-StudioDev.entitlements`, and `Curfew/Resources/LaunchDaemons/studio.hypertext.curfew.studio.dev.daemon.plist`. Test `CurfewTests/App/Infrastructure/DaemonPlistTests.swift`, `CurfewTests/App/Infrastructure/UninstallCoordinatorTests.swift`, and app configuration tests.

**Interfaces:** Xcode configuration `StudioDev` produces `Curfew Studio Dev.app` with Swift module/executable still `Curfew`; `SettingsView` reveals exactly `/Applications/Curfew Studio Dev.app` after StudioDev uninstall. The build script accepts `StudioDev` with `CURFEW_STAGING` and the unique daemon plist.

- [ ] Add failing configuration and uninstall-target tests: assert the third daemon plist's label, environment and sentinel path; assert all cleanup targets are StudioDev-specific and the Finder reveal path is `/Applications/Curfew Studio Dev.app` for StudioDev versus `/Applications/Curfew.app` for existing flavors.
- [ ] Run those targeted suites and confirm failures before editing project/production code.
- [ ] Add a `StudioDev` configuration for project, app, unit tests, UI tests, and widget. Inherit Debug flags; set app/widget team `T95VDD3A4W`, staging entitlements, unique bundle IDs, staging-only Associated Domains, unique App Group, and a computed wrapper name `Curfew Studio Dev.app` without changing the `Curfew` executable/module. Point StudioDev test-host settings at that wrapper. Explicitly allow the new configuration and daemon plist in the helper build phase.
- [ ] Add a flavor-specific Docket callback scheme build setting and update `Info.plist` to expand it. Add the StudioDev daemon plist with `CURFEW_FLAVOR=studioDevelopment` and `Curfew (Studio Dev)` sentinel.
- [ ] Replace uninstall's hardcoded `/Applications/Curfew.app` reveal with a flavor-derived exact URL; scope all cleanup to StudioDev and keep the production script out of this flow. Run the uninstall test against a temporary home, inspecting every deletion/Keychain/manifest target and asserting personal paths remain untouched.
- [ ] Run `xcodebuild -showBuildSettings -project Curfew.xcodeproj -scheme Curfew -configuration StudioDev`, then an unsigned `xcodebuild build -project Curfew.xcodeproj -scheme Curfew -configuration StudioDev -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`. Inspect `FULL_PRODUCT_NAME`, app/widget `Info.plist`, entitlements, and bundled daemon/helper paths. Do not install at this stage.

### Task 4: Complete repository gates as one implementation change

**Files:** Update `Documentation/todos.md`, `Documentation/todo-test-matrix.md`, and the spec/plan only when a tested behavior changes. Commit code and docs together; do not bump a package or app version.

**Interfaces:** Existing Debug and Release build settings and outputs remain the same; StudioDev is additive.

- [ ] Run `swiftformat Curfew CurfewTests CurfewUITests Sources Tests`, then `swiftformat Curfew CurfewTests CurfewUITests Sources Tests --lint`, `swiftlint lint --strict`, all `CurfewTests`, and Debug plus StudioDev builds, with explicit exit codes and logs.
- [ ] Review `git diff --check`, `git diff --name-only -- Documentation/`, the exact docs diff, all build settings, and literal identity table. Ask the existing adversarial reviewer for a final code pass and address Critical/Important findings.
- [ ] Commit once using the repository's atomic index-reset, explicit-path staging, and `git commit -F` chain. Use an outcome-focused subject, explanatory body, and proper co-author trailer. Push fast-forward to PR #42; do not merge or squash.

### Task 5: Apple, coordinator, and physical runtime proof

**Files:** In `curfew-sync`, update the staging AASA/native-client allowlist for exact `T95VDD3A4W.studio.hypertext.curfew.studio.dev`, add a failing allowlist/AASA test, and update its docs. In Apple Developer, register company App ID, widget ID, and App Group with required capabilities and provisioning. In this repo, record the observed evidence and remaining gaps in PR #42.

**Interfaces:** Staging AASA and native-client admission agree on the exact company app ID; a signed StudioDev app carries the same team, bundle, group, and staging Associated Domains.

- [ ] Confirm the Apple account action when requested, then register the exact main/widget IDs and App Group under Hypertext Studio. Verify all three appear under team `T95VDD3A4W` and profiles include the required capabilities; leave personal-team IDs untouched.
- [ ] Add failing coordinator tests for the new exact identity, update the shared server/AASA predicate, run coordinator typecheck/lint/tests, deploy staging, and verify the live AASA response and native-client admission.
- [ ] Build StudioDev signed, inspect `codesign -dv` and `codesign -d --entitlements :-` for the app, widget and helpers, and compare provisioning/team IDs. Confirm the source wrapper and exact `/Applications/Curfew Studio Dev.app` destination before installing; snapshot personal app/settings/Keychain identities/daemon first and compare after.
- [ ] Use the Hypertext Studio browser profile to create or sign in to a fresh staging account, finish 2FA/recovery-code setup and Recovery Key acknowledgement, return through the claimed HTTPS callback, and verify Settings shows a connected enrolled device.
- [ ] With personal development stopped, issue scoped lock and unlock through Claude on the phone. Record MCP client authorization, scope, coordinator signed command, daemon receipt, Mac's visible lock/unlock, and unaffected personal state. Then start a higher-priority app and prove both StudioDev app and daemon stand down, including a stale StudioDev heartbeat.
- [ ] Update PR #42 with observed evidence and honest gaps, get adversarial code review, and leave the goal active until every original remote MCP requirement is proven beyond this staging slice.
