# Todo Test Matrix

## Studio app namespace

`AppNamespaceTests` covers signed-client identity, inherited flavor isolation,
stable preferences, development widget groups, the new production widget snapshot
group, the historical activity migration source, and old/new ownership records
with cross-flavor rejection. `DaemonIdentityIntegrationTests` verifies exact
team and client-role requirements. The native `PrivilegedDaemonProtocolTests`
contract pins the Studio team and the new production app ID. Existing release
candidate, configuration and
profile tests bind the new production app/widget IDs, require both profiles to
authorize the new production snapshot group, retain legacy Keychain access, and
preserve updater trust. Full native CI and an actual signed installation
must still prove platform permissions, Keychain access, helper replacement,
widget access, saved data and update behavior.

## Update retry and first-run instructions

`CurfewUpdaterTests` covers initial unavailability, availability changes,
in-flight duplicate denial, and retry after Sparkle releases the check.
`scripts/user-docs.test.mjs` checks seven-day review, the explicit schedule and
remote-only choices, and current settings destinations. Signed Mac acceptance
must still exercise the actual Sparkle error, cancellation, retry, and update
installation with the release feed; injected availability is not feed proof.
`landing/tests/unit/design.test.mjs` checks the homepage download destination
and pre-release availability; the browser suite checks its keyboard access.
Both suites also cover the app's Plus anchor and visible purchase availability.

## Purchase restoration entry

`CurfewUITests/testPurchaseRestoreAndManualActivationAreReachable` rejects a
manual key, opens a fresh restoration sheet, and checks that the activation error
is absent before any restore request. It also checks empty-field validation and
cancellation without sending mail. `scripts/user-docs.test.mjs` covers the app
activation and inbox restore paths, manual fallback, offline boundaries, and
product support contact. Real email delivery and signed-app handoff remain
separate provider acceptance checks.

## Native wake-failure regression timing

`NativeAccountSyncTransportTests.testPollClearsAnOverrideWhenWakeStatusFails`
waits for the override-cleared and offline callbacks with a deadlock guard,
then checks the inverted healthy-state expectation. That expectation stays
active throughout the positive wait. Pending operations finish before the
network fixture is removed; installed sync behavior is unchanged.

## Native reconnect regression timing

`NativeAccountSyncTransportTests.testReconnectIgnoresFailureFromThePreviousPollingSession`
waits for the new-session health callback with a deadlock guard, then checks the
inverted old-session failure expectation. That expectation remains active
throughout reconnection. The test no longer imposes a 200 ms positive-health
deadline on loaded runners; production generation checks are unchanged.

## Production publication

Website publication uses the ordinary Astro/browser checks and native `cf`
build/prebuilt dry-run described under website hosting configuration. Existing
Worker regressions cover docs proxy behavior, credential isolation, account
handoff and public domain routing. Production provider, canonical URL, account
entry and real signed-feed acceptance remain required after cutover; local
fixtures do not establish those outcomes.

`scripts/release-profiles.test.mjs` covers exact production profile identity,
expiry/distribution/capability rejection, target-specific archive/export mapping,
private installation, existing-file preservation, and digest-checked cleanup.
Issued-profile acceptance requires the actual signed/notarized candidate.

`scripts/website-artifact.test.mjs` verifies retained static identity, alternate
configuration, changed assets and rejection of obsolete Pages runtime files.
`scripts/publication.test.mjs` covers signed candidate/site identity, owner
acceptance freshness, successful source workflows, changed main/tag protection,
release asset reuse/conflicts, website TLS/maintenance admission, live feed and
redirect verification, private receipt permissions/hash binding, draft asset
readback, and native build/prebuilt publication using the exact prepared assets.
These checks do not replace actual signed Mac, provider, assistant, billing,
licensing, mail, update, or production browser acceptance.

## Website domain preparation

Frontend Worker identity, assets and bindings use shared configuration and native
deployment; managed Custom Domains use separately approved native API administration.
Recovery uses native versions and recorded domain/route/DNS reversal, as described
in `website-domain-preparation.md`, without a Pages dependency or fixed delay.
`scripts/deployment-config.test.mjs` covers the configuration contract and refuses
production credentials in PR website validation. Provider status, public DNS
and live TLS must establish activation; unit tests do not prove infrastructure
or production cutover. Existing account/service hosts remain independently owned.

## License deployment configuration

`scripts/deployment-config.test.mjs` covers approved artifact loading, mismatched
hash/commit, missing artifact/environment, production/staging origin isolation,
immutable resolved endpoints, and CI
coverage. `web/worker/test/deployment.node.mjs` evaluates the real cf config with
an alternate domain, preserving Worker/account/KV identity while rejecting
unapproved or tampered builds. `web/worker/test/domain.test.ts` covers health
provenance headers with the unchanged health payload and legacy retirement.
CI runs Worker tests/typecheck and cf build followed by a prebuilt dry-run.
Actual license issuance, refresh, webhook delivery, and retained signing-key
behavior require live acceptance at cutover.

`web/worker/test/discovery.node.mjs` creates an enclosing test configuration
that refuses to load, then runs the actual license test discovery. The license
project must select its own behavior tests and ignore the parent configuration.

## Public legal policies

`landing/tests/unit/legal.test.mjs` checks official contact, notice dates,
consumer and adult purchase requirements, renewal refunds, local MCP data
categories including activity/device attribution, product contact roles, deletion
disclosures with deployment-independent sweep cadence, and native
history routes. Website acceptance tests exercise current and prior routes,
compatibility aliases, refund/contact links, and notices at desktop and mobile
sizes. Existing site checks cover Astro, lint, format, and built output. Native
behavior is unchanged. Local checks do not prove deployed policies, mailbox
operation, account notice delivery, or production retention sweeps. Rollback
restores the prior publication while retaining the archive and accrued rights.

## Cross-browser account callback

`AccountOAuthHandoffTests` exercises the native custom-scheme continuation's
exact scheme, host, path, state, parameter cardinality, and canonical HTTPS
mapping without launching an app. `AccountOAuthHandoffRouterTests` exercises
pending-state consumption and Docket isolation in the app-host router. A
signed Studio Dev app and real browser remain the acceptance check for URL
delivery; neither suite substitutes for that live handoff.

## Safe release candidate policy

`scripts/release-candidate.test.mjs` checks candidate-only tag permissions,
public-retention approval, unsigned quality checks versus signed archive, Studio
identity, browser-host packaging, real Ed25519 update signatures, and evidence
substitution. `scripts/release-configuration.test.mjs` binds existing source inputs,
resolved production feed, public key and commit; a new domain is rejected.
`release-entitlements.test.mjs` requires matching exact published 0.0.13 consumers.
Actual signed/provider/device and production acceptance remain separate gates.
The credential-cleanup workflow regression executes the actual cleanup script on
synthetic files, with only the external Keychain command replaced. Successful
cleanup removes all three fixtures; Keychain failure stops before upload and
retains the fixtures. It also requires immutable upload action pinning and
success-only ordering. This does not simulate signing or notarization success.
The workflow-order regression requires the Developer ID import and temporary
keychain to occur after unsigned quality checks and before the signed archive;
those checks cannot receive certificate material through step environment.

## Local observed enforcement status

`CurfewObservedStatusTests` covers owned lock state, disarmed and cross-flavor
standby state, a real atomic-file round trip, stale expiry, and coalesced
publication. Reviewer-driven tests also cover a live owner's priority over a
standby process, degraded lock health, and hours-based countdown mode.
`StatusCommandTests` checks that the CLI JSON formatter cannot turn a disarmed
schedule prediction into a reported lock. `CurfewMCPAccessTests` invokes the
actual local status and countdown handlers against a persisted disarmed
observation; neither may report an unlock deadline or minutes. The MCP handler
also preserves an observed hours trigger/mode. Each new package test
was run red before the corresponding production change. `DisplayClockTests`
uses an injected temporary store to check that the disarmed native model
publishes `unknown` and that maintenance pause replaces an armed snapshot with
unavailable status; other hosted tests cannot write the live status file.
The native regression built headlessly but must run in hosted CI, not on the
user's active desktop. Signed installed CLI/MCP read-only verification remains.

This is advisory status, not lockout authority. A stale app expires after 60
seconds; a stopped writer is rejected immediately. The app logs mirror write
failures and marks degraded protection unavailable instead of claiming a healthy
lock. No coordinator payload or daemon command
schema changes. Removing the mirror/readers restores prior local-only status
behavior; the separate remote device report and durable enforcement remain.

## Daybreak test-window lifecycle

`DaybreakOverlayReconciliationTests` checks that the borderless morning window
accepts keyboard focus and a tick preserves the form view. The first two
hosted parallel runs crashed before finishing all tests. The diagnostic serial
run completed 1,004 tests and isolated the two SIGSEGV failures to this suite;
its crash report faults in `objc_release`. Test windows now leave the screen
with `orderOut(nil)`, matching `OverlayCoordinator.hideDaybreakWindows`, rather
than calling `close()`. The next full hosted suite must pass with the normal
parallel setting; a build-only result is not enough. The separate CI UI-capture
job and the installed app are not used as unit-test hosts.

`NativeAccountSyncOverrideCadenceTests.testOverridePollingContinuesWhileWakeStatusHangs`
now proves event order: a wake-status request is observed and its response held
pending, then two subsequent override polls are observed. Hosted CI
38469181460 is the failing-first evidence for the old 150 ms wall-clock wait;
1,005 other native tests passed. The new expectation deadline is a bounded
deadlock guard, not an override-poll performance assertion. A passing hosted
full suite is still required.

## Renewed account connection handoff

`AccountStatusSyncTests.testTerminalRejectionCannotPublishOrRestartUntilReauthorized`
checks that rejected credentials stop status publication and cannot be
reactivated by an ordinary start; only the explicit successful same-account
reauthorization restarts the transport. The pending-encryption recovery test
requires the rejection to remain visible until that reconnect. No account
secret or wire format changes. The installed Mac must still demonstrate a
fresh online report; an isolated test pass alone is not acceptance.

`AccountStatusSyncTests.testAccessDeniedRequiresManualReviewBeforeRetryingSavedEnrollment`
checks that ordinary startup cannot resume a coordinator-denied device, while
an explicit retry can recheck the existing enrollment and retain encrypted
pending changes. `testAccessReviewCannotBypassRequiredSameAccountSignIn`
keeps that retry from clearing a missing-credential rejection. The account
status copy directs the owner to restore access first. Hosted app tests and
the signed installed Mac still need to confirm the visible recovery action;
these tests do not grant device access or exercise remote locks.

`AccountLifecycleWiringTests.invalidWakeUpdateKeepsAccountTransportActive` and
`remoteReleaseWriteFailureKeepsAccountTransportActive` cover non-authentication
rejections at their actual app-model call sites. Invalid or stale wake data and
a failed local release write must fail closed for those updates without
discarding still-valid account credentials, status publication, or inbound
remote-command delivery. A credential rejection remains a separate terminal
condition requiring same-account sign-in.

`PrivilegedDaemonWiringTests.displayTickRetriesUnavailableHelper` checks one
read-only helper status retry from the disarmed display clock and no repeated
RPC on the next tick. The retry is single-flight, limited to an enabled helper,
and skipped during installation, maintenance, and repair. No new privilege or
authorization prompt is required. If a signed update regresses helper health,
roll back the app without replacing or clearing the daemon's durable state.

`AccountLifecycleWiringTests.disarmedEnrollmentPublishesStatusHeartbeat` checks
that an enrolled, disarmed Mac's display tick uses the existing bounded account
publication path, sends an `unknown` enforcement phase rather than its schedule
forecast, and does not arm enforcement or publish again on the next tick. The
`disarmedEnrollmentSuppressesHeartbeatDuringMaintenance` companion protects
the helper-repair pause from a misleading online report. The
coordinator's two-minute online window and signed installed-app behavior remain
separate runtime acceptance checks; no lock command is part of this test.

`NativeAccountSyncTransportTests.testLocalEligibilityWriteFailureDoesNotRequireAccountSignIn`
reproduces a failed local eligibility-snapshot write after valid enrollment. It
requires a retryable offline signal, not a credential-rejection callback; the
coordinator POST remains blocked until the local snapshot can be saved.
`testStatusPublicationRetriesAfterLocalStorageRecovers` verifies the next
attempt persists that snapshot before POST. A missing enrollment stays terminal
and a malformed, oversized, or unsafe entry produces a distinct invalid-identity
error rather than an endless offline retry. The headless CurfewKit
`RemoteCommandEnrollmentStoreTests` checks these permanent read boundaries,
while a temporarily unreadable regular record keeps the open error and retries
after permissions recover. The native
`testMissingLocalEnrollmentDoesNotOfferImpossibleSignInRetry`,
`testCorruptLocalEnrollmentNeedsDeviceRepairInsteadOfOfflineRetry`, and
`AccountStatusPresentationTests.missingLocalEnrollment` forbid the unusable
sign-in CTA and require distinct device-repair copy. Settings links directly to
Curfew support; native accessibility of that link remains a rendered UI check.
This is an isolated filesystem and transport test, not a live lock or
recovery-code flow.

`NativeAccountSyncTransportTests.testRejectedRefreshTokenRequiresSignInInsteadOfReportingOffline`
exercises the real transport's rejected refresh response. It requires a
sign-in-required callback and excludes a later offline callback; the terminal
event drives the assertion, with timeout only guarding a hung test.

`AccountStatusSyncTests.testRenewedCredentialsReconnectRejectedTransportWithoutLosingPendingChanges`
reproduces the rejected-but-active engine and checks a fresh connection plus
preserved pending encryption. The maintenance-paused regression prohibits
resuming during repair. Both run against the production engine in the existing
hostless harness, with an injected transport; only its production default
initializer lives with the native adapter. `ReadyAccountReauthorizationSafetyTests`
checks explicit success and cancellation outcomes; these app integration tests
run in isolated CI, not by launching a test app on the user's desktop.
Installed success requires fresh Codex device status, not merely passing tests.

CI 38355685931 passed 998 native cases and failed the existing root-key health
test because its offline callback did not arrive within 200ms on the loaded
runner. That test now awaits the actual native reconciliation operation and
asserts offline, no healthy callback, and an unhealthy peer-key channel. It does
not increase a timeout or replace the transport with a simulated result.

## CI action version assertions

`scripts/release-entitlements.test.mjs` checks that failed CI checks preserve
`build/CurfewTests.xcresult` as `curfew-unit-test-results`. Its action reference
accepts numeric major, minor, and patch tags so pinning `v7.0.2` does not reject
the unchanged diagnostics contract. Run `node --test scripts/*.test.mjs` for
this test-only correction; hosted native CI remains separate acceptance.

## Background protection reconnect and disarmed reporting

`HelperRepairIntegrationTests.installationChecksConnection` reproduces an
installation returning while the connection stays unavailable. It failed before
the installation action was made to await connection verification. General and
Connections now invoke that same asynchronous installation action. The hostless
suite now passes 76 tests. Live installed helper connection was verified through
both the app and launchd after the user's repair on October 12 at 22:53 Pacific.

`HelperRepairIntegrationTests` reproduces admission refusal pausing enforcement
and a new arm RPC racing asynchronous admission. Both failed before correction.
`DaemonRegistrationRepairTests` covers ordered replacement, failures,
cancellation, and concurrent attempts. `DaemonMaintenanceAdmissionTests` checks
independent deadlines, binding, malformed data, and mixed control formats.
`AccountStatusPublicationLedgerTests.disarmedScheduleIsNotAnEnforcedLock` failed
on phase and both deadline fields before the publisher correction.

The existing hostless app harness passes 75 tests without UI, and the shared
package suites pass. Strict lint, formatting, and signed StudioDev build pass.
The repository's old format command names absent Sources/Tests directories;
validation uses the actual CurfewKit/Sources and CurfewKit/Tests paths instead.
Full hosted app tests remain assigned to isolated CI. Actual administrator
prompt and installed helper registration acceptance remain separate: the first
installed attempt exposed duplicate authopen prompts and registration error 1.
The authorization update uses one exact-file read-only context per repair with
fresh reads on both inspections; it never persists authorization or file state.

## In-progress event-driven account sync

CI 38309791533 failed `testPollPublishesDaemonResultBeforeFetchingMoreCommands()`
with two result POSTs instead of one, and both cadence regressions with requests
outliving fixture teardown. Connection-local successful-result suppression,
challenge-boundary cancellation checks and awaited fixture session invalidation
address these failures. The same assertions remain intact; hosted GREEN is pending.
CI 38310819506 reproduced the new same-test receipt-removal case: commands were
fetched without re-uploading the result or obtaining a fresh candidate. Receipt-
aware suppression now invalidates when the exact candidate disappears/changes.
The cadence missing-handler failure also requires construction-time handler
snapshots, not merely waiting for session invalidation. Final hosted GREEN is open.
CI 38311757940 passed receipt retry and cadence tests; its sole failure was
`testSharedResultRetryUsesAlreadyRotatedCredentials()` reading a cleared general
transport handler. The general fixture now also snapshots at construction,
retaining the same missing-handler assertion and rotated-token event expectations.
CI 38312352269 still failed missing cadence and transport handlers. The new
`testFixtureShutdownWaitsForCanceledOwnedOperationToUnwind` exercises explicit
joining of a canceled owned refresh rather than equating cancellation with
completion. Async fixtures join currently registered operation handles before
releasing dependencies; the mid-test reconnect race remains immediate.
CI 38313551603 retained failing cadence assertions and traced their requests to
the previous invalidated session. Per-session fixture binding now preserves that
ownership and cancels late requests; missing setup remains an assertion. Both
existing cadence regressions must pass on the final head, without timeout changes.
All cadence regressions passed on CI 38314500184. Its sole general-fixture
missing-handler failure extends session binding to that fixture as well, with
XCTest teardown cancellation and an explicit session-local behavior replacement
for the reconnect race. Full hosted GREEN remains required.
Request/session lifecycle tracing retains missing-handler assertions and supplies
the missing caller attribution. This does not prove driver socket quiescence.

`CurfewKitTests/AccountStatusPublicationLedgerTests` covers acknowledged unchanged
heartbeats, a fresh publication attempt after the 60-second heartbeat interval,
in-flight coalescing, failed-send retry, failed intermediate states,
late success/failure fencing and every existing enforcement-report field. The
new due-heartbeat regression failed before the ledger fix and passes after it.
The headless package suite passes; this is publication policy evidence, not installed
socket or remote-command acceptance. The app-hosted
`NativeAccountSyncTransportTests/testUnchangedInFlightHeartbeatKeepsEligibleStatusVersion()`
failed on CI run 38301226012 with actual eligible version18 instead of17 before
the ledger was connected and passed on CI 38302226143. That run exposed the
late-response fixture using two semantically identical frames; it now changes
phase while preserving the ordering assertions.

`AccountSyncReconciliationScheduleTests` executes 86,400 monotonic seconds and
checks the 2,304 protected-read idle budget, independent hung channels, coalesced
dirty follow-ups and failure backoff that hints cannot bypass.
`AccountSyncSocketLifecycleTests` covers handshake/half-open deadlines, healthy
pong backoff reset and terminal revocation. `AccountSyncSocketTests` runs the
actual asynchronous connection consumer through an injected network boundary:
first-pong handshake deadline (observed RED, then GREEN), hint/pong distinction,
terminal closure and late-open cleanup. These do not simulate installed acceptance.
`NativeAccountSyncOverrideCadenceTests/testOldSocketRefreshRejectionCannotStopAReplacementConnection()`
failed on CI 38304524293 with generation2 instead of1 before the reviewed fence
was restored. The existing rejection fixture now expects one terminal callback,
since all channels stop instead of repeatedly reporting the same failure.
Socket consumer deallocation and explicit reconnect, plus scheduler restoration,
have observed headless RED/GREEN coverage. Native wake/path notifications are
connected without foreground behavior.
`NativeAccountSyncTransportTests/testStatusPublicationRefreshesExpiredCredentialsInsteadOfStoppingSync()`
failed on CI 38305592933 before status retry integration. That run passed the stale
socket-refresh generation regression. The fixes now use shared refresh retry,
owned-task cancellation and cancellation checks before HTTP/credential writes.
Socket restoration preserves failure backoff with observed headless RED/GREEN
coverage. Final native CI must verify the status retry and refresh ownership.
Full native consumer CI, native lifecycle adapter runtime proof,
installed acceptance and actual indexed-write counts remain open.
No local app-hosted test execution.

`NativeAccountSyncTransportTests/testScheduledCommandsWaitWhileResultPublicationFails()`
exercises the production scheduler with a real local pending result and a failed
HTTP result response. It requires no command GET while the result is unreported;
CI 38307577571 observed multiple forbidden command GETs, but the inverted
expectation crashed on over-fulfillment. Its failure reporting now runs on the
main actor without over-fulfillment exceptions; CI 38308503697 then reproduced
the forbidden fetch as a clean assertion failure before shared publication wiring.
`testScheduledCommandFetchWaitsForSharedResultReceipt()` checks one shared POST
and receipt recording before command fetching. `testSharedResultRetryUsesAlreadyRotatedCredentials()`
checks concurrent result/command retry after another channel has rotated tokens.
The retry test gives each simulated network callback a three-second hosted-CI
window; a missing callback or wrong event order still fails. This changes test
tolerance, not transport behavior, and can be rolled back if it masks a measured
runtime delay. Both success cases and the full native suite require hosted GREEN
before shipping.

`NativeAccountSyncTransportTests/testStalePollCannotStartAnOperationAfterDisconnect()`
requires stale reconciliation to return before invoking its operation, independent
of network fixtures. CI 38308319780/38308503697 observed one operation instead of
zero before the entry fence. CI 38307160113 exposed nil URLProtocol
handlers after teardown; its status-refresh and cadence tests did not pass.
The shared HTTP fixture now cancels queued delayed responses in `stopLoading()`;
missing-handler failures remain assertions, reported on the main thread with
the request path. Already-running callbacks may finish during cancellation.
No timeout budgets were increased. Full hosted verification remains pending.

This file maps completed todo items (`[x]`) in `Documentation/todos.md` to automated behavior tests.

Signed-build/manual validation for shutdown, WidgetKit, the privileged helper,
Sparkle, notarization, and related Apple-provisioned release surfaces lives in
`Documentation/RELEASE.md`; this matrix intentionally tracks automated coverage
only. CloudKit and Calendar are dormant in v0.1. Model behavior fixtures use
`makeTestAppModel()` or `LockoutDeadlineStore.ephemeralForTesting()` so unit
tests cannot read or mutate a user's App Group lockout record.

## 0. Foundation and Project Structure

- `Adopt the Studio website and Mintlify standard` (in progress).
  - `landing/tests/unit/site-worker.test.mjs` covers docs/asset/search delegation,
    path/query/forwarded origin, cookie/Authorization/Cloudflare Access header
    isolation, redirects/errors and HTML-guide mode behavior.
  - `landing/tests/acceptance/site.spec.mjs` covers clean/HTML aliases, direct
    URL/reload, Back/Forward, keyboard/reduced motion, the unconfigured license
    error and 404 behavior. Its local server explicitly selects HTML-guide mode
    through the native `--var` option to retain deterministic fallback coverage.
  - `scripts/landing-contract.test.mjs` covers public account, download and legal
    content. Shared docs generation and pinned native Mintlify validation cover
    the generated configuration and documentation source.
  - Ordinary website CI uses the frozen registry lock, Astro build and existing
    three-browser checks. Manual staging selects exact successful main output,
    checks main before deployment and uses the separate staging credential.
  - Protected staging must separately accept the real Mintlify HTML, navigation,
    assets, anchors, search, discovery and `/docs/mcp` alias. Unit fixtures and
    fallback browser checks do not establish hosted proxy acceptance.
  - `scripts/user-docs.test.mjs` retains reader metadata and page-link checks,
    including the existing public MCP guide canonical URL.

- `Bundle the pinned Chrome native messaging host.`
  - `BrowserNativeProtocolTests` checks versioning, strict fields, correlation, and framing limits.
  - `BrowserNativeStoreTests` checks signed state, tampering, expiry, permissions, scrubbing, and pruning.
  - `BrowserNativeHostTests` checks offline snapshot reads, signed heartbeat state, bounded review waits, and bounded signed-policy revision waits.
  - `BrowserNativeInstallationTests` checks the public-key-derived development ID, origin validation, and manifest ownership.
  - `BrowserNativeLifecycleTests` checks app queue processing, restart exact-task resolution, fail-closed migration behavior, and uninstall cleanup.
  - `DocketBrowserPolicyClientTests/queuedReviewRejectsStaleResponse()` and `queuedReviewRejectsAnotherSession()` check rejection before applying a grant.
- `Isolate native host flavors and revoke live hosts before uninstall.`
  - `BrowserNativeInstallationTests/developmentAndProductionInstallAndUninstallIndependently()` and `installationRejectsUnsafeExecutable(kind:)` check manifest isolation and executable validation.
  - `BrowserNativeStoreTests/oversizedDestinationCannotPoisonAnExistingQueue()`, `oversizedSignedResponseLeavesPriorQueueUnchanged()`, `requestByteBoundaryAndMaximumQueueStayReadable(unicodeAnswers:)`, and `completeSignedRecordAcceptsItsLastFittingSize()` check request and record size boundaries.
  - `BrowserNativeHostTests/liveHostCannotRecreateStateAfterUninstall()` and `revokedMarkerBlocksEveryMutationWithoutCreatingFiles()` check marker revocation.
  - `BrowserNativeLifecycleTests/uninstallRevokesAWaitingHostAndPreservesOtherFlavor()` checks the app uninstall path with a waiting host. Browser lifecycle fixtures inject an isolated Keychain eraser so unsigned CI validates browser state rather than depending on the runner's Keychain entitlements.
- `Build the task-scoped Chrome MV3 extension.`
  - `destination.test.ts` checks removal of credentials, query strings, fragments, default ports, and unsupported schemes before review.
  - `rules.test.ts` checks one low-priority top-level block, higher-priority exact-origin and case-sensitive path-prefix allows, subresource exclusion, and current-clock grant and break expiry.
  - `controller.test.ts` checks first-activation block-first installation, one-update restoration, startup recovery after cached DNR restoration fails, revision long-poll revocation without an alarm, refresh, grant, and expiry when the base block persists, block-only fallback after unsupported or rejected regex validation, the 1,000-regex quota, 30-second heartbeat, task-switch response rejection without queue starvation, opaque blocker routing, first-activation foreign-blocker exclusion, grant-before-reopen ordering, one-challenge justification retention and clearing, the 1,000-character contract, the 8,192-byte UTF-8 limit, host failure, and private request expiry.
  - `policy-watch.test.ts` checks restart after native-host recovery and rejects duplicate long polls.
  - `blocker-state.test.ts` checks targeted-question restoration, original-justification preservation, one-field challenge submission, and character and byte limits without Chrome.
  - `manifest.test.ts` checks the MV3 permissions, minimum Chrome 120, HTTP and HTTPS host access, service-worker declaration, icons, homepage, a keyless first-upload draft, the public-key-derived development identity, valid RSA production keys, and rejection of malformed or reused development identities.
  - `build.test.ts` checks development, keyless draft, and production flavors, production identity failure, native-host isolation, packaged icon dimensions, and the extension-local blocker prompt.
  - `icon.test.ts` compiles the shipping Curfew app icon, checks that every Chrome export retains transparency, and rejects committed extension icons that drift from that source.
  - `package.test.ts` checks that the keyless draft can create the first Web Store item and that the production upload ZIP refuses a missing identity, contains only files from a fresh production build, and repeats byte for byte from the same inputs.
  - `DocketBrowserPolicyClientTests/acceptedDestinationReviewsAreAuditedWithoutPrivateInput()` checks the stable event name, one event for each accepted challenge, grant, and denial, and the three-field redacted detail.
  - `DocketBrowserPolicyClientTests/taskSwitchInvalidatesReviewResult(kind:)` checks that stale-session Athena results do not write browser audit records.

- `Convert app shell to a standard macOS app window (LSUIElement = false) with menu bar quick access.`
  - `AppConfigurationTests/hostAppIsWindowed()`
- `Default debug/Xcode launch starts with enforcement disarmed unless explicitly enabled.`
  - `LaunchBehaviorTests/debugLaunchDefaultsToSafeMode()`
  - `LaunchBehaviorTests/releaseLaunchStartsByDefault()`
- `Add a dedicated app launch coordinator so app startup orchestration is isolated from scene composition.`
  - `AppCoordinatorTests/startsEnforcement()`
  - `AppCoordinatorTests/doesNotStartWhenDisallowed()`
- `Add feature flags for deferred modules (widget/cloud/MCP/privileged helper) with safe defaults off.`
  - `FeatureFlagTests/defaultsAreOff()`
  - `FeatureFlagTests/shippingV1ExcludesPreviewIntegrations()`
- `Keep Release capabilities limited to the v0.1 entitlement contract.`
  - `scripts/verify-release-artifact.sh` compares signed entitlements exactly.

## 1. Schedule + Enforcement Core

- `Propose 22:00–06:00 on fresh installs without rewriting saved schedules.`
  - `NewInstallScheduleTests/freshInstallProposesTenToSix()`
  - `NewInstallScheduleTests/freshInstallOvernightBoundary(corruptSettings:)`
  - `NewInstallScheduleTests/existingSettingsRetainCustomSchedule()`
- `First-run schedule edits apply immediately but opening the editor does not arm it.`
  - `FirstRunSafetyFlowTests/openingScheduleDoesNotConfirmIt()`
  - `FirstRunSafetyFlowTests/remoteOnlyChoiceAdvancesWithoutScheduleReview()`
  - `FirstRunScheduleEditTests/firstRunScheduleEditIsImmediate()`
  - `FirstRunSafetyModelTests/remoteOnlyScheduleEditIsImmediate()`
  - `WeeklyScheduleReviewTests/allSevenRulesAreVisible()`
  - `FirstRunSafetyModelTests/immediateLockNeedsSeparateAcknowledgement()`
  - `FirstRunSafetyModelTests/enableNeedsSeparateImmediateLockAcknowledgement()`
  - `FirstRunSafetyModelTests/boundaryIsCheckedAtActivation()`
  - `CurfewUITests/testSetupUsesOneInstructionAndPreservesScheduleGate()`
  - `MarketingCaptureTests/testCaptureAStateConsistencySetupReview()`
  - `MarketingCaptureTests/testCaptureAStateConsistencySetupPermission()`
  - `MarketingCaptureTests/testCaptureWorkspaceMatrix()` follows seven-day review before advancing.
- `Curfew Dev migration requires local schedule consent while retaining remote deadlines.`
  - `AutomaticScheduleConsentPolicyTests/developmentInstallDefaultsToRemoteOnly()` covers the signed development bundle and an explicit opt-in.
  - `AutomaticScheduleConsentPolicyTests/developmentIdentityOverridesProductionEnvironment()` prevents inherited flavor variables from rearming the signed development app.
  - `CurfewFlavorTests/developmentAppOverridesEnvironment()` pins the app-target identity boundary.
  - `DevelopmentScheduleMigrationTests/completedDevelopmentDefaultsToRemoteOnly(flavor:)` covers the retained development store, durable persistence of the protective off value, and the UI distinction from an explicit choice; `FirstRunSafetyModelTests/completedProductionInstallKeepsSchedule()` keeps production's missing-consent behavior unchanged.
  - `AutomaticScheduleConsentPolicyTests/studioDevMigrationStaysOff()`
  - `ScheduleConsentReadSurfaceTests/intentDoesNotPredictAnInactiveLock()`
  - `CurfewMCPAccessTests/inactiveScheduleIsLabeled()`
  - `ScheduleConsentReadSurfaceTests/intentReportsObservedRemoteLock()`
  - `FirstRunSafetyModelTests/completedStudioDevDefaultsToRemoteOnly()`
  - `FirstRunSafetyModelTests/completedProductionInstallKeepsSchedule()`
  - `FirstRunSafetyModelTests/remoteOnlyPreservesDurableDeadline(kind:)`
  - `FirstRunSafetyModelTests/activeScheduleWeakeningStillQueues()`
  - `AccountLifecycleWiringTests/authenticatedRemoteResultPresentsLockout()`
- `After setup, weaker edits still obey the anti-bypass cooldown.`
  - `AuditWiringTests/weakerScheduleChangeIsRecorded()`
  - `SchedulePolicyEngineTests/weakeningChangeHas24HourCooldown()`

- `Implement weekly schedule model (per-day end time, unlock time, day-off support).`
  - `ScheduleResolutionTests/scheduleWindowResolvesSpringForwardGap()`
  - `CurfewEnforcementEngineTests/dayOffState()`
- `Implement schedule presets: 9-to-5, Startup Hours, Half Day.`
  - `SchedulePresetTests/presetDefaults()`
- `Enforce anti-bypass policy:`
  - `SchedulePolicyEngineTests/classifyLaterLockAsWeaker()`
  - `SchedulePolicyEngineTests/classifyEarlierLockAsStricter()`
- `Stricter schedule changes can apply next day.`
  - `SchedulePolicyEngineTests/stricterChangeAppliesNextDay()`
- `Weaker schedule changes require 24-hour cooldown.`
  - `SchedulePolicyEngineTests/weakeningChangeHas24HourCooldown()`
- `Add DST-safe local timezone handling and schedule resolution tests.`
  - `ScheduleResolutionTests/scheduleWindowResolvesSpringForwardGap()`
- `Add schedule summary sentence generation for Settings.`
  - `ScheduleResolutionTests/scheduleSummarySentenceForTomorrow()`
- `Add a single EnforcementSnapshot read model for UI surfaces.`
  - `EnforcementSnapshotTests/warningSnapshot()`
  - `EnforcementSnapshotTests/dayOffSnapshot()`

## 2. Warning Escalation

- `Implement warning stage engine for T-30, T-15, T-5, T-2, T-1, T-0.`
  - `WarningStageTests/stageBoundaries()`
- `Deliver warnings via UNUserNotificationCenter with categories/actions.`
  - `WarningNotificationManagerTests/earlyWarningPayload()`
  - `WarningNotificationManagerTests/finalWarningPayload()`
  - `WarningNotificationManagerTests/categoryDefinitions()`
- `Add snooze (1 minute) action only for T-30 and T-15.`
  - `WarningBehaviorTests/snoozeActionAvailability()`
  - `WarningNotificationManagerTests/earlyWarningPayload()`
- `Build click-through dim overlay windows with stage-specific opacity.`
  - `OverlayWindowConfigurationTests/warningWindowConfiguration()`
  - `WarningStageTests/overlayOpacityLevels()`
- `Add always-on-top floating timer for last 5 minutes.`
  - `OverlayWindowConfigurationTests/timerWindowConfiguration()`
  - `WarningBehaviorTests/floatingTimerStageAvailability()`
- `Add advanced settings to customize warning intervals.`
  - `CurfewEnforcementEngineTests/customWarningIntervals()`
  - `CurfewEnforcementEngineTests/extensionAvailabilityForCustomIntervals()`
  - `WarningIntervalsPersistenceTests/warningIntervalsPersistNormalized()`

## 3. Lockout Experience

- `Build full-screen lockout windows on all displays and spaces.`
  - `OverlayWindowConfigurationTests/lockoutWindowConfiguration()`
- `Add .screenSaver-level window behavior and input capture.`
  - `OverlayWindowConfigurationTests/lockoutWindowConfiguration()`
- `Add keyboard shortcut interception strategy for lockout.`
  - `LockoutShortcutPolicyTests/blocksTargetedShortcuts()`
  - `LockoutShortcutPolicyTests/allowsUnrelatedShortcuts()`
- `Implement rotating encouragement messages.`
  - `EncouragementMessageRotationTests/messageRotationWraps()`
- `Implement lockout visual design (time, unlock time, optional stats card).`
  - `MenuBarPresentationModelTests/symbolAndStatusForPhase()`
  - `MenuBarPresentationModelTests/timeRemainingTextFormatting()`
- `Respect accessibility settings: VoiceOver, reduce motion, reduce transparency.`
  - `AccessibilityConfigurationTests/reduceMotionConfiguration()`
  - `AccessibilityConfigurationTests/reduceTransparencyConfiguration()`
  - `AccessibilityConfigurationTests/voiceOverSummaryIncludesUnlockCopy()`
  - `CurfewUITests/testWarningAndLockoutPresentation()`
  - `CurfewUITests/testOverrideRequiresCooldownReasonAndHold()`

## 4. Shutdown Manager

- `Implement optional auto-shutdown delay setting (1-60 min, default 10).`
  - `AutoShutdownConfigurationTests/defaultAutoShutdownDelay()`
  - `AutoShutdownConfigurationTests/shutdownDelayMinimumClamp()`
- `Show lockout countdown UI for shutdown.`
  - `AutoShutdownConfigurationTests/shutdownCountdownStatusLine()`
- `Request graceful app termination before shutdown.`
  - `ShutdownWorkflowTests/gracefulBeforeShutdown()`
- `Implement shutdown retry once after 60 seconds on failure.`
  - `ShutdownWorkflowTests/retriesOnceAfterFailure()`
- `Keep lockout active if shutdown ultimately fails.`
  - `ShutdownWorkflowTests/failureAfterRetryKeepsLockoutState()`
- `Graceful termination skips the protected-work allowlist.`
  - `ProtectedWorkPolicyTests/defaultsProtectAgentHosts()`
  - `ProtectedWorkPolicyTests/unlistedApplicationsAreTerminated()`
  - `ProtectedWorkPolicyTests/matchingIsExactAndCaseInsensitive()`
  - `ProtectedWorkShutdownTests/policyReachesTheController()`
- `Shutdown defers while protected work is live, bounded.`
  - `ProtectedWorkShutdownTests/activeWorkDefersTheShutdown()`
  - `ProtectedWorkShutdownTests/deferralIsBounded()`
  - `ProtectedWorkShutdownTests/finishingWorkResumesTheShutdown()`
  - `ProtectedWorkShutdownTests/leavingLockoutResetsTheDeferral()`
  - `ProtectedWorkDeferralTests/deferralIsBounded()`
  - `ProtectedWorkDeferralTests/renewalCannotReopenTheWindow()`
  - `ProtectedWorkDeferralTests/restartResumesTheWindow()`
- `Background agents survive lockout without having to declare themselves.`
  - `LiveProtectedWorkTests/liveAgentProcessCounts()`
  - `LiveProtectedWorkTests/unlistedProcessIsNotProtected()`
  - `LiveProtectedWorkTests/matchingIsExactAndCaseInsensitive()`
  - `LiveProtectedWorkTests/sparedProcessesDoNotAutomaticallyDefer()`
  - `LiveProtectedWorkTests/emptyListDisablesLivenessDeferral()`
  - `LiveProtectedWorkTests/sysctlReaderSeesASpawnedProcess()`
  - `LiveProtectedWorkTests/terminatedProcessStopsCounting()`
  - `ProtectedWorkLivenessTests/realAgentProcessDefersAutoShutdown()`
  - `ProtectedWorkLivenessTests/realAgentProcessDefersDaemonShutdown()`
  - `ProtectedWorkLivenessTests/bothPathsHoldThenResume()`
  - `ProtectedWorkLivenessTests/livenessHoldIsBounded()`
  - `ProtectedWorkShutdownTests/observedWorkDefersTheShutdown()`
  - `DaemonEnforcementDecisionTests/observedWorkHoldsTheDaemon()`
- `A session held over the network survives lockout.`
  - `LiveProtectedWorkTests/remoteSessionCounts()`
  - `LiveProtectedWorkTests/consoleSessionDoesNotCount()`
  - `LiveProtectedWorkTests/remoteSessionsCanBeDisabled()`
  - `LiveProtectedWorkTests/utmpxReaderReturnsWellFormedSessions()`
  - `ProtectedWorkLivenessTests/sshSessionDefersAutoShutdown()`
  - `ProtectedWorkLivenessTests/sshSessionDefersDaemonShutdown()`
  - `ProtectedWorkLivenessTests/consoleSessionDefersNothing()`
- `The carve-out never becomes a general escape hatch.`
  - `ProtectedWorkLivenessTests/nonAllowlistedProcessIsStillTerminated()`
  - `DaemonEnforcementDecisionTests/observingNothingStillShutsDown()`
  - `ProtectedWorkPolicyTests/alwaysOnHostsDoNotDefer()`
  - `ProtectedWorkPolicyTests/decodingTolerateAMissingLivenessConfiguration()`
- `The daemon's persisted deferral window closes when the app heartbeat recovers.`
  - `DaemonEnforcementDecisionTests/recoveryClosesTheWindowWithinOneLockout()`
  - `DaemonEnforcementDecisionTests/freshHeartbeatWaits()`
  - `DaemonEnforcementDecisionTests/staleMarkerFromAPreviousWindowIsIgnored()`
  - `DaemonEnforcementDecisionTests/futureDatedMarkerIsIgnored()`
  - `DaemonEnforcementDecisionTests/continuousIncidentIsBounded()`
  - `DaemonEnforcementDecisionTests/restartResumesTheSameWindow()`
  - `DaemonEnforcementDecisionTests/noProtectedWorkShutsDown()`
  - `DaemonEnforcementDecisionTests/shutdownIsNotReissued()`
  - `DaemonEnforcementDecisionTests/breakGlassStandsDownAndClearsTheMarker()`
  - `DaemonEnforcementDecisionTests/exitPathsClearTheMarker()`
- `The deferral bound cannot be configured or hand-edited away.`
  - `ProtectedWorkPolicyTests/deferralIsClampedOnConstruction()`
  - `ProtectedWorkPolicyTests/decodingClampsDeferral()`
- `Only surface auto-shutdown when the current build carries the Apple Events automation entitlement.`
  - `ShutdownSupportTests/shutdownAvailabilityMatchesEntitlements()`
  - `ShutdownPanelStateTests/unavailableStateCarriesReleaseGuidance()`
  - `ShutdownPanelStateTests/availableStateExplainsAutomationPrompt()`
- `If the user denies Automation permission for System Events shutdown, stop retrying and show a recovery path to Automation settings.`
  - `ShutdownWorkflowTests/permissionDeniedStopsRetrying()`
  - `AutoShutdownConfigurationTests/shutdownPermissionDeniedStatusLine()`

## 5. Bypass Protection + Privileged Layer

- `Release enforcement ownership only for the seeded PID and bundle identity.`
  - `EnforcementOwnershipTests/releaseRespectsOwnership()`
  - `EnforcementOwnershipTests/releaseRejectsWrongBundleIdentifier()`
- `Migrate legacy deadline records to UUID-bearing records.`
  - `PrivilegedDaemonProtocolTests/legacyDeadlineMigration()`
  - `PrivilegedDaemonProtocolTests/legacyDeadlineStorePersistsMigration()`
- `Persist daemon-owned state atomically with root-safe permissions.`
  - `PrivilegedDaemonProtocolTests/daemonStateStorageContract()`
- `Arm, heartbeat, complete, and recover lockouts deterministically.`
  - `PrivilegedDaemonProtocolTests/armRejectsExpiredDeadline()`
  - `PrivilegedDaemonProtocolTests/heartbeatKeepsLockoutAlive()`
  - `PrivilegedDaemonWiringTests/activeLockoutHeartbeatIsThrottled()`
  - `PrivilegedDaemonProtocolTests/naturalCompletionCannotBypassDeadline()`
  - `PrivilegedDaemonProtocolTests/approvedOverrideCompletesLockout()`
  - `PrivilegedDaemonProtocolTests/restartRecovery()`
- `Issue stale-heartbeat shutdown once and reject uninstall while active.`
  - `PrivilegedDaemonProtocolTests/staleHeartbeatRequestsOneShutdown()`
  - `PrivilegedDaemonProtocolTests/uninstallRejectedDuringLockout()`
- `Authenticate every XPC message by audit-token signing identity, accepting only the exact Team ID and app bundle ID.`
  - `PrivilegedDaemonProtocolTests/clientIdentityPolicy()`
  - `PrivilegedDaemonProtocolTests/daemonSigningRequirement()`
- `Encode XPC requests and time out unresponsive channels.`
  - `PrivilegedDaemonProtocolTests/protocolPayloadRoundTrip()`
  - `PrivilegedDaemonProtocolTests/daemonRPCDeadlineTimesOut()`
  - `PrivilegedDaemonProtocolTests/daemonRPCDeadlineReturnsResponse()`
- `Package the embedded LaunchDaemon plist using SMAppService's BundleProgram layout.`
  - `DaemonPlistTests/plistUsesEmbeddedBundleProgram()`
- `Break-glass emergency release stands root-level enforcement down without the display.`
  - `BreakGlassStoreTests/issuedReleaseIsActive()`
  - `BreakGlassStoreTests/shortReasonIsRefused()`
  - `BreakGlassStoreTests/tamperedRecordIsRejected()`
  - `BreakGlassStoreTests/unsignedRecordIsIgnored()`
  - `BreakGlassStoreTests/releaseIsScopedToItsWindow()`
  - `BreakGlassStoreTests/releaseAgesOut()`
  - `BreakGlassStoreTests/futureDatedRecordIsIgnored()`
  - `BreakGlassStoreTests/clearRemovesTheRelease()`
  - `BreakGlassStoreTests/signedTimestampsSurvivePersistence(fraction:)`
  - `ProtectedWorkShutdownTests/breakGlassReleasesTheWorkflow()`
  - `ProtectedWorkShutdownTests/breakGlassOutranksDeferral()`
- `Revoking a break-glass release re-arms both the app and the daemon.`
  - `ProtectedWorkShutdownTests/breakGlassRevokeReArmsTheWorkflow()`
  - `ProtectedWorkShutdownTests/revokeRestoresTheFullDeferralBudget()`
  - `DaemonEnforcementDecisionTests/revokeReArmsTheDaemon()`
  - `DaemonEnforcementDecisionTests/revokeRestoresTheFullDeferralBudget()`
- `A shutdown already in flight is cancelled when protected work arrives.`
  - `DaemonEnforcementRuntimeTests/holdCancelsAShutdownAlreadyInFlight()`
  - `DaemonEnforcementRuntimeTests/cancellationDoesNotDisarmEnforcement()`
  - `DaemonEnforcementRuntimeTests/standDownCancels()`
  - `DaemonEnforcementRuntimeTests/exitCancels()`
  - `DaemonEnforcementRuntimeTests/recoveryDoesNotCancel()`
  - `DaemonEnforcementRuntimeTests/markerIsAlwaysWritten()`
  - `DaemonEnforcementRuntimeTests/standDownLogsOnTheTransition()`
  - `DaemonEnforcementRuntimeTests/exitClearsTheShadow()`
  - `DaemonEnforcementRuntimeTests/shutdownIsNotReissued()`
- `The app model actually feeds the shutdown workflow the carve-out's inputs.`
  - `ProtectedWorkWiringTests/policyReachesTheContext()`
  - `ProtectedWorkWiringTests/liveClaimReachesTheContext()`
  - `ProtectedWorkWiringTests/breakGlassReachesTheContext()`
  - `ProtectedWorkWiringTests/staleReleaseIsScopedOut()`
  - `ProtectedWorkWiringTests/naturalUnlockClearsCarveOutState()`
- `The app and the privileged daemon reach the same verdict on every tick.`
  - `EnforcementParityTests/revokeParity()`
  - `EnforcementParityTests/revokeWithLiveWorkParity()`
  - `EnforcementParityTests/releaseAfterDeferralParity()`
  - `EnforcementParityTests/boundedDeferralParity()`
  - `EnforcementParityTests/unblockedParity()`
- `The privileged daemon resolves the console user's home rather than /var/root.`
  - `SharedPathsTests/nonRootIsUnchanged()`
  - `SharedPathsTests/rootRedirectsToTheConsoleUser()`
  - `SharedPathsTests/rootWithoutConsoleUserFallsBack()`
  - `SharedPathsTests/newPathsLiveWithTheOtherSharedState()`
- `Protected-work claims are leases that expire on their own.`
  - `ProtectedWorkStoreTests/claimMakesWorkActive()`
  - `ProtectedWorkStoreTests/claimExpires()`
  - `ProtectedWorkStoreTests/renewalExtendsWithoutDuplicating()`
  - `ProtectedWorkStoreTests/leaseIsClamped()`
  - `ProtectedWorkStoreTests/releaseDropsTheClaim()`
  - `ProtectedWorkStoreTests/expiredClaimsArePruned()`
  - `ProtectedWorkStoreTests/unreadableFileFailsClosed()`
- `Mirror SMAppService daemon/login-item status into the Settings helper panel through testable service wrappers.`
  - `PrivilegedHelperManagerTests/refreshStatusMirrorsServices()`
  - `PrivilegedHelperManagerTests/installDaemonRegisters()`
  - `PrivilegedHelperManagerTests/installDaemonStoresError()`
  - `PrivilegedHelperManagerTests/loginItemRegistrationFlows()`
  - `PrivilegedHelperStatusCopyTests/helperStatusDescriptions()`
- `Expose the shipping MCP and privileged-helper controls in the isolated staging build so signed-device acceptance can install the daemon.`
  - `FeatureFlagTests/resolveWithStagingFeatures()`
  - `FeatureFlagTests/resolvedMatchesBuild()`
  - `scripts/release-entitlements.test.mjs` (`a staging build compiles the app and every embedded tool for the same service boundary`; checks Debug and StudioDev staging flags and excludes Release)

## 6. Extension and Override Systems

- `Implement weekly extension budget (default 3/week) and duration (default 15 min).`
  - `ExtensionBudgetTrackerTests/extensionBudgetDecrements()`
  - `OverrideRequestPolicyTests/overrideDefaults()`
- `Restrict extension requests to warning phase only.`
  - `CurfewEnforcementEngineTests/workingStateBeforeWarning()`
  - `CurfewEnforcementEngineTests/warningAtThirty()`
  - `CurfewEnforcementEngineTests/lockoutAtCurfew()`
- `Implement deliberate extension activation interaction (hold-to-confirm).`
  - `ExtensionActivationInteractionTests/tapDoesNotConsumeBudget()`
  - `ExtensionActivationInteractionTests/holdConfirmConsumesBudget()`
- `Implement extension reset day configuration (default Monday at unlock).`
  - `ExtensionResetConfigurationTests/defaultResetWeekdayIsMonday()`
  - `ExtensionResetConfigurationTests/extensionBudgetResetsOnBoundary()`
- `Enforce override limit (default 2/week) shared with lockout UI flow.`
  - `OverrideRequestPolicyTests/overrideDefaults()`

## 7. “Convince Me” Unlock Flow

- `Add subtle lockout entry point: Need to get back in?`
  - `OverrideRequestPolicyTests/overridePolicyValidation()`
- `Enforce 5-minute cooldown before unlock request form.`
  - `OverrideRequestPolicyTests/overridePolicyValidation()`
- `Require minimum 50-character justification.`
  - `OverrideRequestPolicyTests/overridePolicyValidation()`
- `Add consequence confirmation with 3-second hold-to-confirm.`
  - `OverrideRequestPolicyTests/overridePolicyValidation()`
- `Grant time-limited unlock (default 30 min), then re-lock automatically.`
  - `OverrideRequestPolicyTests/overrideDefaults()`
  - `OverrideWindowBehaviorTests/relocksAfterOverrideEnds()`
- `Log timestamp/device/reason/granted duration for each override event.`
  - `OverrideEventStoreTests/overrideEventsPersist()`
  - `OverrideEventLoggingTests/confirmOverrideLogsEvent()`

## 8. Menu Bar UI + Core Screens

- `Build menu bar icon state system (green/amber/red/gray/lock).`
  - `MenuBarPresentationModelTests/symbolAndStatusForPhase()`
- `Implement popover content: countdown, schedule, extension action, quick links.`
  - `MenuBarPresentationModelTests/symbolAndStatusForPhase()`
  - `MenuBarPresentationModelTests/timeRemainingTextFormatting()`
- `Build primary app window UX with overview, configuration, and getting started sections.`
  - `MainWorkspaceSectionTests/sectionSet()`
- `Build Settings app sections: schedule, enforcement, integrations, devices, advanced.`
  - `SettingsSectionTests/sectionSet()`

## 11.5 Audit log

- `JSON Lines records with schema version, ISO-8601 timestamp with offset, per-stream sequence, writing stream, actor, event type, and before→after state.`
  - `AuditLineEncoderTests/singleLine()`
  - `AuditLineEncoderTests/envelopeFields()`
  - `AuditLineEncoderTests/timestampKeepsOffset()`
  - `AuditLineEncoderTests/omitsEmptyFields()`
  - `AuditLineEncoderTests/detailIsDeterministic()`
  - `AuditLineEncoderTests/escapesControlCharacters()`
  - `AuditLineEncoderTests/actorTokenIsSanitised()`
  - `AuditLogWriterTests/sequenceIsMonotonic()`
  - `AuditLogWriterTests/appendIsAppendOnly()`
- `Separate file per writer so the app and the root daemon never interleave.`
  - `AuditLogRotationTests/streamsAreSeparateFiles()`
  - `AuditLogRotationTests/concurrentStreamsDoNotInterleave()`
  - `AuditLogWriterTests/writerOwnsStreamField()`
  - `AuditLogRotationTests/appStreamIsUserOnly()`
- `SHA-256 hash chain per stream, spanning rotations, recovered from the file on restart.`
  - `AuditLineEncoderTests/lineVerifies()`
  - `AuditLineEncoderTests/tamperingBreaksVerification()`
  - `AuditLineEncoderTests/truncatedLineFailsVerification()`
  - `AuditLineEncoderTests/chainLinks()`
  - `AuditLineEncoderTests/chainCoversPrev()`
  - `AuditLogWriterTests/chainIsIntactAcrossAppends()`
  - `AuditLogWriterTests/chainSurvivesProcessRestart()`
  - `AuditLogRotationTests/chainSpansRotation()`
  - `AuditLogWriterTests/streamOpenedReportsChainRecovery()`
- `Size + age rotation with a 25 MiB per-stream ceiling and 90-day retention on rotated segments.`
  - `AuditLogRotationTests/rotatesAtSizeCap()`
  - `AuditLogRotationTests/rotationEnforcesSegmentCap()`
  - `AuditLogRotationTests/rotationIsRecorded()`
  - `AuditLogRotationTests/retentionPrunesOldSegments()`
- `Redaction: reflection prose and override justifications are never written; MCP arguments are digested.`
  - `AuditRedactionTests/redactionKeepsNoProse()`
  - `AuditRedactionTests/digestIsStable()`
  - `AuditRedactionTests/digestDiscriminates()`
  - `AuditRedactionTests/encodedOverrideLineIsClean()`
  - `AuditRedactionTests/mcpArgumentsAreRedacted()`
  - `AuditOverrideRedactionTests/overrideGrantRedactsProse()`
- `Wired to enforcement, schedule, grant, MCP consent, and lifecycle paths.`
  - `AuditGrantWiringTests/phaseTransitionRecordsLockoutStart()`
  - `AuditGrantWiringTests/lockoutEndAttributesOverride()`
  - `AuditGrantWiringTests/steadyTicksAreSilent()`
  - `AuditGrantWiringTests/accessibilityLossIsRecorded()`
  - `AuditWiringTests/weakerScheduleChangeIsRecorded()`
  - `AuditWiringTests/mcpScheduleChangeIsAttributed()`
  - `AuditWiringTests/appliedScheduleChangeIsRecorded()`
  - `AuditWiringTests/deferralIsRecordedOnce()`
  - `AuditGrantWiringTests/extensionGrantIsRecorded()`
  - `AuditGrantWiringTests/extensionDenialIsRecorded()`
  - `AuditGrantWiringTests/overrideOutsideLockoutIsDenied()`
  - `AuditGrantWiringTests/mcpDenialIsRecorded()`
  - `AuditGrantWiringTests/mcpQueuedIsRecorded()`
  - `AuditGrantWiringTests/disabledLogDropsRecords()`
- `MCP consent verdicts name who actually decided, and an auto-approval writes one record.`
  - `AuditGrantWiringTests/overrideGuardDenialIsAttributedToApp()`
  - `AuditGrantWiringTests/policyDenialIsAttributedToApp()`
  - `AuditGrantWiringTests/consentSheetDenialIsAttributedToUser()`
  - `AuditGrantWiringTests/consentSheetApprovalIsAttributedToUser()`
  - `AuditGrantWiringTests/autoApprovalWritesOneAppRecord()`
- `Daemon observations are recorded in both directions, including a break-glass release lifting.`
  - `DaemonAuditObserverTests/breakGlassArrivalIsRecorded()`
  - `DaemonAuditObserverTests/breakGlassEndingIsRecorded()`
  - `DaemonAuditObserverTests/breakGlassKeyResetsAfterClearing()`
  - `DaemonAuditObserverTests/breakGlassIsNotRepeated()`
  - `DaemonAuditObserverTests/protectedWorkIsRecordedBothWays()`
  - `DaemonAuditObserverTests/heartbeatIsRecordedBothWays()`
  - `DaemonAuditObserverTests/missingHeartbeatRecordsSentinelAge()`
  - `DaemonAuditObserverTests/shadowSourcedDeadlineIsRecorded()`
  - `DaemonAuditObserverTests/deadlineIsNotRepeated()`
- `A shutdown that fails to launch is never recorded as issued.`
  - `DaemonAuditWiringTests/failedShutdownLaunchIsRecordedAsFailure()`
- `Rotation writes its marker as the first line of the new segment, chained to the old one.`
  - `AuditLogRotationTests/rotationIsRecorded()`
  - `AuditLogRotationTests/chainSpansRotation()`
- `Daemon actions are recorded where the decision becomes a machine action.`
  - `DaemonAuditWiringTests/shutdownIssueIsRecorded()`
  - `DaemonAuditWiringTests/protectedWorkCancellationIsRecorded()`
  - `DaemonAuditWiringTests/breakGlassCancellationIsRecorded()`
  - `DaemonAuditWiringTests/lockoutEndCancellationIsRecorded()`
  - `DaemonAuditWiringTests/recoveredHeartbeatRecordsNoCancellation()`
  - `DaemonAuditWiringTests/standDownIsRecordedOnce()`
  - `DaemonAuditWiringTests/holdIsRecordedOncePerWindow()`
  - `DaemonAuditWiringTests/deferralWindowOpenAndCloseAreRecorded()`
  - `DaemonAuditWiringTests/noSpuriousDeferralCloseOnStart()`
- `The respawn deterrent's arm, disarm, and arm-failure outcomes are recorded.`
  - `AuditRespawnGuardTests/respawnGuardArmIsRecorded()`
  - `AuditRespawnGuardTests/respawnGuardDisarmIsRecorded()`
  - `AuditRespawnGuardTests/respawnGuardArmFailureIsRecorded()`

## 12. WidgetKit

- `Mirror widget settings + activity data into shared storage before wiring the WidgetKit target.`
  - `WidgetSharedStateStoreTests/settingsSnapshotRoundTrips()`
  - `WidgetSharedStateStoreTests/migratesLegacyActivityDatabase()`
- `Wire the Xcode Widget Extension target into the app bundle.`
  - Build verification: `xcodebuild -list -project Curfew.xcodeproj`
  - Build verification: `xcodebuild build -project Curfew.xcodeproj -scheme CurfewWidget -destination 'platform=macOS'`
- `Use the widget extension kind identifier when reloading host-app timelines.`
  - `WidgetIdentityTests/kindMatchesWidgetExtension()`

## 15. Onboarding

- `Show a first-launch getting-started window so users can configure Curfew immediately.`
  - `CurfewTests/initialSetupPromptShownOnlyOnce()`
- `Persist one-time first-launch setup state so Settings only auto-opens once.`
  - `CurfewTests/enforcementArmsOnlyAfterSetupCompletion()` uses an ephemeral
    deadline store so the unit suite never reads a real App Group lockout record.
  - `CurfewTests/initialSetupPromptShownOnlyOnce()`
- `Build first-run flow: welcome, schedule, extension budget, permissions, confirmation.`
  - `FirstRunFlowTests/requiredSteps()`
  - `FirstRunFlowTests/navigationBounds()`
  - `FirstRunSafetyFlowTests/reviewedWeeklyChoiceAdvances()` verifies the
    seven-rule acknowledgement and weekly choice are one state transition.
  - `MarketingCaptureTests/testCaptureWorkspaceMatrix()` checks the selected
    confirmation appears before Next advances to the next setup step, and both
    choices remain hittable after opening the live schedule editor.
  - `CurfewUITests/testSetupUsesOneInstructionAndPreservesScheduleGate()` checks
    all seven rules and both choices are hittable at minimum window size;
    rule and feedback text may be exposed as either an accessibility label or value.
  - `SetupUXTests/completeOnboardingFlowUpdatesState()`
- `Onboarding completion requires acknowledging all seven effective weekly rules
  or choosing remote-only mode, plus the existing permissions gate before finish.`
  - `FirstRunFlowTests/scheduleStepRequiresReview()`
  - `FirstRunFlowTests/permissionsStepRequiresAcknowledgement()`
  - `OnboardingConfirmationRequirementTests/confirmationRequirementsTrackOutstandingSteps()`
- `Allow onboarding relaunch from Settings.`
  - `SetupUXTests/gettingStartedActionRoutesThroughPresenter()`
- `Add warm explanatory copy for commitment model and enforcement behavior.`
  - `GettingStartedCopyTests/warmCommitmentCopy()`
  - `GettingStartedCopyTests/scheduleCopyUsesWorkWindowLanguage()`
- `Schedule editor and summary copy should make the editable times read as work-window boundaries, not ambiguous lock/unlock jargon.`
  - `ScheduleSurfaceCopyTests/scheduleLabelsExplainWorkWindow()`
  - `SchedulePolicyEngineTests/scheduleSummarySentenceForTomorrow()`

## 16. Reflection and AI Access

- `Present user-confirmed morning and evening reflection gates at the work-day boundaries.`
  - `ReflectionGatingTests/morningGateOnSession()`
  - `ReflectionGatingTests/eveningGateOnLockout()`
  - `ReflectionGatingTests/saveResolvesGate()`
  - `ReflectionGatingTests/skipResolvesGate()`
- `Keep the morning reflection form mounted across one-second enforcement ticks.`
  - `DaybreakOverlayReconciliationTests/existingWindowKeepsContent()`
- `Allow keyboard focus in the borderless morning reflection window.`
  - `DaybreakOverlayReconciliationTests/daybreakWindowAcceptsKeyboardFocus()`
- `Persist user-authored reflection answers without losing their prompt snapshots or value types.`
  - `ReflectionModelTests/answersRoundTrip()`
  - `ReflectionStoreTests/roundTrip()`

## 17. Build Gating and Distribution Accuracy

- `The company-signed Studio development vehicle is identity-isolated from
  personal Debug and Release, resolves bundled helpers without trusting a
  conflicting environment, cannot perform machine-wide shutdown effects or
  accept a remote lock while a live higher-priority app owns enforcement,
  and uninstalls only its own state. Artifact and live signed-device proof
  remain separate release gates.`
  - `CurfewFlavorTests/studioDevelopmentResolution()`
  - `CurfewFlavorTests/bundledHelperUsesContainingAppIdentity()`
  - `CurfewFlavorTests/studioMutableIdentitiesAreDisjoint()`
  - `StudioDevDaemonSafetyTests/liveOwnerDeniesRemoteLock()`
  - `StudioDevDaemonSafetyTests/staleHeartbeatCannotShutdown()`
  - `StudioDevDaemonSafetyTests/rootShutdownEffectsAreInert()`
  - `DaemonPlistTests/helperPlistsAreFlavorSpecific()`
  - `UninstallCoordinatorTests/studioDevelopmentUninstallTouchesOnlyItsOwnState()`
  - `UninstallCoordinatorTests/failedStudioRegistrationCleanupKeepsStateAndAppRunning()`
  - `PrivilegedHelperManagerTests/studioUninstallRegistrationCleanup()`
  - `BrowserNativeStartupTests/studioDevelopmentNeverClaimsChromeNativeHost()`
  - `TaskBrowserEnforcementPanelTests/studioDevelopmentExplainsChromeIsUnavailableOnlyHere()`
- `macOS account enrollment binds PKCE to the Curfew sync resource, stores
  private material in Keychain, sends privacy-minimal generated enrollment,
  preserves the user's normal browser session for existing passkeys, and
  owns a claimed HTTPS OAuth callback through Associated Domains so the
  authorization session can return without trusting a forgeable custom scheme,
  and cannot mark sync ready before Recovery
  Key acknowledgement or restore. First-device setup displays the Recovery Key
  before uploading its envelope and resumes the exact acknowledged step after
  a failure or relaunch.`
  - `AccountOAuthEnrollmentTests`
  - `AccountOAuthEnrollmentTests/browserSessionPreservesPasskeys()`
  - `AccountOAuthEnrollmentTests/settingsReportsAttachedWindow()`
  - `AccountOAuthEnrollmentTests/presentationUsesTriggeringSettingsWindow()`
  - `AccountOAuthEnrollmentTests/presentationRequiresSettingsWindow()`
  - `AccountOAuthEnrollmentTests/enrollmentSignInIsSingleFlight()`
  - `AccountEnrollmentRecoveryTests/deviceEnrollmentFailurePreservesSignInTruth()`
  - `AccountEnrollmentRecoveryTests/initialDeviceConnectionCanResumeAfterRelaunch()`
  - `AccountEnrollmentRecoveryTests/rejectedInitialConnectionCanReauthorize()`
  - `AccountEnrollmentRecoveryTests/missingInitialConnectionCredentialCanReauthorize()`
  - `AccountOAuthUserInfoTests/testWrongAccountCannotReplaceSavedOAuthCredentials()`
  - `AccountOAuthUserInfoTests/testSameAccountCanReplaceCredentialsAfterServerIdentityCheck()`
  - `AccountOAuthUserInfoTests/testFailedCredentialWriteDoesNotReplaceExistingAccountTokens()`
  - `AccountEnrollmentReauthorizationTests/sameAccountResumesSavedRegistration()`
  - `AccountEnrollmentReauthorizationTests/readyMacRenewsSameAccount()`
  - `AccountEnrollmentReauthorizationTests/browserCompletionFailureExplainsConnectionStage()`
  - `AccountEnrollmentReauthorizationTests/readyMacWithoutMatchingOwnerFailsClosed()`
  - `AccountEnrollmentReauthorizationTests/savedSettingsWithoutReadyMarkerRenewSafely()`
  - `AccountEnrollmentReauthorizationTests/duplicateReadyReconnectIsSingleFlight()`
  - `AccountEnrollmentReauthorizationTests/differentAccountCannotTakeOverSavedRegistration()`
  - `AccountEnrollmentReauthorizationTests/legacyCheckpointFailsClosed()`
  - `AccountEnrollmentReauthorizationTests/registeredMacResumesRecoveryWithSameAccount()`
  - `AccountEnrollmentReauthorizationTests/confirmationCanReauthorize()`
  - `AccountEnrollmentReauthorizationTests/existingKeyRestorationCanReauthorize()`
  - `NativeAccountCredentialRecoveryTests/testMissingAccessCredentialRequestsReauthorization()`
  - `AccountCheckpointIdentityTests/testPendingRegistrationKeepsTheOriginalAccountForSafeReauthorization()`
  - `AccountCheckpointIdentityTests/testLegacyRegisteredCheckpointUsesTheCoordinatorReceiptForReauthorization()`
  - `AccountCheckpointIdentityTests/testDisplayingRecoveryKeyKeepsTheRegisteredDeviceReceipt()`
  - `AccountCheckpointIdentityTests/testExistingKeyRecoveryKeepsAccountIdentityWithoutTheGeneratedKey()`
  - `AccountEnrollmentCompletionTests/testBrowserGrantToSavedRecoveryKeyToReadyKeepsTheReceipt()`
  - `AccountEnrollmentCompletionTests/testExistingEnvelopeKeepsAccountBindingForLaterKeyRestoration()`
  - `AccountEnrollmentRecoveryTests/wrongRecoveryKeyDoesNotRestartSignIn()`
  - `AccountEnrollmentRecoveryTests/postBrowserFailurePreservesBrowserSignInTruth()`
  - `AccountEnrollmentRecoveryTests/browserSignInLinkCanMoveToThePasskeyProfile()`
  - `AccountEnrollmentCancellationTests/missedBrowserCallbackCanBeRetriedWithoutRelaunch()`
  - `AccountEnrollmentCancellationTests/stalledTokenExchangeCanBeCancelled()`
  - `AccountEnrollmentCancellationTests/cancelAfterOAuthCompletionPreventsDeviceEnrollment()`
  - `AccountEnrollmentReauthorizationTests/cancelledReauthorizationRestoresSavedCredentials()`
  - `AccountEnrollmentReauthorizationTests/missingSavedTokenRequiresReauthorization(account:)`
  - `AccountLifecycleWiringTests/accountConnectionReportsStatusBeforeInitialSetup()`
  - `AccountOAuthUserInfoTests/testPartialCredentialWriteRestoresExistingAccountTokens()`
  - `AccountOAuthUserInfoTests/testFailedRollbackReportsUnavailableStorageAndClearsAccess()`
  - `AccountEnrollmentRecoveryTests/browserSignInLinkCleanupPreservesNewClipboardContents()`
  - `AccountEnrollmentRecoveryTests/browserSignInLinkClearsBeforeDeviceEnrollment()`
  - `AccountEnrollmentCopyTests/recoveryKeyCanBeCopied()`
  - `AccountEnrollmentCopyTests/recoveryKeyExportUsesOwnerOnlyFilePermissions()`
  - `AccountOAuthEnrollmentTests/callbackStateIsExact()`
  - `AccountOAuthEnrollmentTests/callbackIsClaimedHTTPS()`
  - `AccountOAuthExternalCallbackTests/externalBrowserCallbackRoutesByExactState()`
  - `AccountOAuthExternalCallbackTests/externalBrowserCallbackIsConsumedOnce()`
  - `AccountOAuthExternalCallbackTests/appDelegateForwardsExternalOAuthCallback()`
  - `AccountOAuthUniversalLinkActivityTests/appDelegateRoutesUniversalLinkActivity()`
  - `AccountOAuthUniversalLinkActivityTests/alternatePortIsNotTheClaimedOrigin()`
  - `AccountEnrollmentRecoveryTests/registeredMacResumesWithoutSigningInAgain()`
  - `AccountEnrollmentRecoveryTests/recoveryRetryFailureStaysAtTheRecoveryStep()`
  - `AccountEnrollmentRecoveryTests/recoveryRetryIsSingleFlight()`
  - `AccountEnrollmentStorageRecoveryTests/unreadableEnrollmentFailsClosed()`
  - `AccountEnrollmentStorageRecoveryTests/malformedEnrollmentFailsClosed(account:)`
  - `AccountEnrollmentStorageRecoveryTests/storageRetryRestoresPendingStep()`
  - `AccountEnrollmentStorageRecoveryTests/storageRetryWithNoCheckpointReturnsAccountFree()`
  - `AccountOAuthEnrollmentTests/authenticationSessionIsSingleFlight()`
  - `AccountEncryptionTests/testRegisteredDeviceRecoverySetupSurvivesRelaunchAsResumable()`
  - `NativeAccountSyncTransportTests/testDeviceRegistrationShowsRecoveryKeyBeforeRecoveryUpload()`
  - `NativeAccountSyncTransportTests/testAmbiguousRegistrationResponseResumesTheExactDeviceWithoutOAuth()`
  - `NativeAccountSyncTransportTests/testInitialDeviceConnectionRefreshesExpiredGrantBeforeRegistration()`
  - `NativeAccountSyncTransportTests/testOpaqueAccessTokenKeepsFailedRegistrationReauthorizable()`
  - `AccountEncryptionTests/testPendingDeviceRegistrationSurvivesBeforeCoordinatorResponse()`
  - `AccountEncryptionTests/testCompletedEnrollmentSurvivesRelaunchUntilSettingsPersist()`
  - `UninstallCoordinatorTests/productionUninstallIncludesLegacyCoordinatorCredential()`
  - `UninstallCoordinatorTests/developmentUninstallPreservesLegacyProductionCredential()`
  - `UninstallCoordinatorTests/uninstallErasesFlavorScopedAccountKeychainState()`
  - `UninstallCoordinatorTests/completedUninstallTerminatesAfterPresentingTheOutcome()`
  - `AppConfigurationTests/hostAppOwnsOAuthCallbackScheme()`
  - `NativeAccountSyncTransportTests`
  - `AccountEncryptionTests`
- `Settings presents phone-based account enrollment before local desktop AI
  setup, and local AI copy describes its real read/write and reflection-sharing
  boundary without promising remote unlock or bypass authority.`
  - `GettingStartedCopyTests/localAISetupCopyIsTruthfulAndPlain()`
  - `AIConsentPolicyTests/policyCopyMatchesLocalToolAuthority()`
  - `MCPGatingTests/standaloneServerUsesPersistedAccessSetting()`
  - `CurfewMCPAccessTests/disabledAccessClosesBothDispatcherPaths()`
- `An enrolled Mac reports the live remote connection state without claiming
  that enrollment alone means remote control is working or enabled. A rejected
  account connection offers same-account sign-in without replacing the enrolled
  device, and a missing privileged helper is shown as a remote-lock blocker.`
  - `AccountConnectionPresentationTests/statesStayPlainAndAccurate()`
  - `AccountConnectionPresentationTests/rejectedAccountStatusOffersRepair()`
  - `PrivilegedHelperManagerTests/daemonReadinessRequiresFreshHeartbeat()`
  - `PrivilegedHelperManagerTests/studioRemoteReadinessRespectsHigherPriorityOwner()`
  - `AccountStatusSyncTests/testSuccessfulAuthenticatedPollMarksTheAccountConnectionSynchronized()`
  - `AccountStatusSyncTests/testReadOnlyPollDoesNotClaimPendingEncryptedChangesWereSaved()`
  - `AccountStatusSyncTests/testPendingEncryptedChangesSurviveOfflineRecovery()`
  - `AccountStatusSyncTests/testPendingEncryptedChangesSurviveRejectedRecovery()`
  - `AccountStatusSyncTests/testNetworkFailureMarksTheAccountConnectionOffline()`
  - `NativeAccountSyncTransportTests/testPollClearsAnOverrideAndReportsAHealthyConnectionWithoutAWakeCampaign()`
  - `NativeAccountSyncTransportTests/testOverrideFailureCannotBeOverwrittenByAHealthyAccountPoll()`
    Both positive callbacks must complete; the inverted healthy callback remains
    absent through the full bounded wait. The bound tolerates parallel test-host
    scheduling and does not assert product polling latency.
  - `NativeAccountSyncTransportTests/testRootKeyDistributionFailureCannotBeOverwrittenByAHealthyAccountPoll()`
  - `NativeAccountSyncTransportTests/testFailedStatusPublicationRemainsUnhealthyAfterSuccessfulPolls()`
  - `NativeAccountSyncTransportTests/testOlderStatusSuccessCannotOverwriteTheLatestStatusFailure()`
    Both wait for actual fixture callbacks with a hosted-runner scheduling
    allowance; the assertions still require initial health followed by the
    correct failed-publication state, not a particular network latency.
  - `NativeAccountSyncTransportTests/testReconnectIgnoresFailureFromThePreviousPollingSession()`
  - `NativeAccountSyncTransportTests/testRejectedRefreshTokenRequiresSignInInsteadOfReportingOffline()`
- `Returning from System Settings refreshes live Accessibility trust even when
  Curfew's enforcement timer is off.`
  - `EnforcementHealthWiringTests/appActivationRefreshesAccessibilityTrustWithoutEnforcementTimer()`
- `The Dev app's Debug configuration selects one closed-world staging endpoint
  set for account UI, OAuth, sync, MCP, daemon command-key trust, and account-key
  Keychain storage without a manual build override; Release selects production,
  and account copy explains that phone locking is a per-device opt-in.`
  - `AccountOAuthEnrollmentTests/stagingEndpointsStayIsolated()`
  - `AccountOAuthEnrollmentTests/currentEndpointsFollowBuildFlag()`
  - `AccountEnrollmentCopyTests/remoteControlIsPlainAndOptIn()`
  - `CurfewFlavorTests/derivedValues()`
  - `SharedPathsTests/privilegedStateIsFlavorSpecific()`
  - `DaemonPlistTests/helperPlistsAreFlavorSpecific()`
  - `scripts/release-entitlements.test.mjs` (`a staging build compiles the app and every embedded tool for the same service boundary`)
- `Both the app project and command-line package consume the same immutable
  pre-1.0 Curfew protocol release.`
  - `swift package resolve`
  - `xcodebuild -resolvePackageDependencies -project Curfew.xcodeproj -scheme Curfew`
  - `CurfewProtocolBridgeTests/testReleasedUnlockTargetScopesRemainDistinct()`
  - `curfew-sync/tests/mcp.test.ts` (published pending-unlock discovery is caller-isolated and paginated)
  - `scripts/release-entitlements.test.mjs` (`app and command-line tools pin the same exact 0.0.x protocol release`)
- `Every user-facing Curfew release surface uses the same version in the 0.0.x line.`
  - `scripts/release-entitlements.test.mjs` (`every user-facing release version is the same 0.0.x version`)
- `Signed app builds sign every embedded CLI/helper with the host identity,
  while explicitly unsigned CI builds remain buildable.`
  - `AppConfigurationBehaviorTests/bundledDaemonUsesHostSigningIdentity()`
  - `scripts/release-entitlements.test.mjs` (`unsigned CI builds skip embedded tool signing`)
  - `scripts/release-entitlements.test.mjs` (`interactive builds reject an unresolved signing identity before TCC can mislead`)
- `An unlocked enrolled Mac periodically wakes its privileged daemon, accepts
  only a coordinator-signed command for the enrolled account/device, and makes
  the authenticated remote deadline visible to the existing enforcement loop.`
  - `DaemonPlistTests`
  - `RemoteCommandVerifierTests`
  - `RemoteCommandInboxStoreTests`
  - `RemoteCommandInboxStoreTests/embeddedCursorMustMatchEnumeratedFilename()`
  - `RemoteCommandInboxStoreTests/poisonPrefixCannotPermanentlyStarveCommands()`
  - `RemoteCommandInboxStoreTests/directoryPoisonCannotPermanentlyStarveCommands()`
  - `DaemonRemoteCommandControllerTests`
  - `DaemonCommandBackendTests/localBackendShadowsDeadline()`
  - `DaemonCommandBackendTests/remoteBackendOwnsTransportAndDeadline()`
  - `DaemonCommandBackendTests/backendSetIsolatesFailures()`
  - `DaemonCommandBackendTests/synchronizationFailurePreservesDurableDeadline()`
  - `DaemonCommandBackendReadTests/releasedLocalDeadlinePreservesRemote()` (headless package test; read-only composition never synchronizes transports)
  - `DaemonLockoutDeadlineResolverTests`
  - `AccountLifecycleWiringTests/authenticatedRemoteResultPresentsLockout()`
  - `swift build --product curfew-daemon`
  - `AppConfigurationTests/bundledDaemonUsesHostSigningIdentity()`
- `A coordinator-authorized remote override temporarily releases scheduled and
  daemon-issued Curfew lockouts for its exact enrolled device, preserves both
  ordinary and wake-campaign durable deadlines for re-lock, and clears locally
  when the authenticated coordinator reports that no override remains active.`
  - `AccountLifecycleWiringTests/authenticatedAccountOverrideReleasesRemoteDeadline()`
  - `AccountLifecycleWiringTests/authenticatedAccountOverrideMirrorsDaemonRelease()`
  - `AccountLifecycleWiringTests/directOverrideExpiryPreservesRemoteCommandDeadline()`
  - `AccountLifecycleWiringTests/revokedAccountOverrideRestoresWakeDeadline()`
  - `BreakGlassStoreTests/boundedReleaseExpiresAtGrantDeadline()`
  - `BreakGlassStoreTests/boundedReleasePredatingLockoutRemainsActive()`
  - `BreakGlassStoreTests/coordinatorReleaseRequiresBoundedRemoteGrant()`
  - `NativeAccountSyncTransportTests/testPollClearsAnOverrideThatIsNoLongerActive()`
  - `NativeAccountSyncTransportTests/testPollClearsAnOverrideWhenWakeStatusFails()`
  - `NativeAccountSyncTransportTests/testPollDeliversCoordinatorOverrideWithFractionalTimestamp()`
  - `NativeAccountSyncMappingTests/testRemoteOverrideMappingAcceptsProtocolUTCPrecisionRange()`
  - `NativeAccountSyncOverrideCadenceTests/testOverridePollingContinuesWhileWakeStatusHangs()`
  - `NativeAccountSyncOverrideCadenceTests/testStaggeredStaleTokenResponsesShareOneRefreshGeneration()`
  - `AccountWakeReleaseTests/testOnlyCurrentAuthorizedOverrideCanReleaseThisDevice()`
- `A remote command must use the released lock-device wire kind and exactly
  match the status version and schedule digest most recently published by this
  Mac; missing or stale eligibility cannot create a deadline.`
  - `RemoteCommandVerifierTests/acceptsValidES256Command()`
  - `DaemonRemoteCommandControllerTests/rejectsCommandWithoutEligibilitySnapshot()`
  - `DaemonRemoteCommandControllerTests/rejectsStaleStatusVersion()`
  - `DaemonRemoteCommandControllerTests/rejectsStaleScheduleDigest()`
  - `NativeAccountSyncTransportTests/testStatusPublicationRecordsTheExactLocalEligibilitySnapshot()`
- `A daemon terminal result maps exactly to the released 0.0.9 result shape,
  is acknowledged and published before another command fetch, and stays in the
  durable outbox until the daemon consumes an exact publication acknowledgement.`
  - `NativeAccountSyncMappingTests/testDaemonResultMapsExactlyToReleasedProtocol()`
  - `NativeAccountSyncTransportTests/testPollPublishesDaemonResultBeforeFetchingMoreCommands()`
  - `RemoteCommandInboxStoreTests/resultExchangeRoundTripsDurably()`
  - `RemoteCommandInboxStoreTests/malformedAcknowledgementIsQuarantined()`
  - `DaemonRemoteCommandControllerTests/backendReconcilesResultExchange()`
  - `DaemonRemoteCommandControllerTests/rejectsMismatchedResultAcknowledgement()`
- `The root daemon never follows a user-replaceable inbox/result/acknowledgement
  symlink and rejects exchange directories not owned by root in production.`
  - `RemoteCommandInboxStoreTests`
  - `RemoteCommandInboxStoreTests/rejectsNonRootOwnedResultExchangeDirectory()`
  - `SharedPathsTests`
- `Durable deadlines are replaced atomically with private permissions, and
  model tests never write synthetic lockouts into the developer's protected
  Application Support directory.`
  - `LockoutDeadlineStoreTests/saveReplacesTheRecordWithPrivatePermissions()`
  - `AuditGrantWiringTests`
  - `AuditWiringTests`
  - `CurfewTests/enforcementArmsOnlyAfterSetupCompletion()`
  - `SetupUXTests/completeOnboardingFlowUpdatesState()`
- `The public static MCP guide and the repository-owned Mintlify source give
  the same correct Claude Desktop configuration and permissions boundary until
  Mintlify is intentionally published.`
  - Manual review of `landing/src/pages/docs.astro` and `web/docs/mcp-guide.mdx`
  - Browser review of the deployed static MCP guide (external launch proof)
  - Verify the static guide retains its documentation navigation and readable
    article layout at desktop and mobile widths
- `Marketing capture targets only the fixture process and never captures the
  desktop as a fallback.`
  - Review `scripts/capture-marketing.sh` and `scripts/window-id.swift` before
    running a local marketing capture
- `Hide deferred integration panels in default builds until their feature flags are enabled.`
  - `FeatureFlagTests/deferredPanelsAreHiddenByDefault()`
  - `DeferredIntegrationVisibilityTests/visiblePanelsFollowEnabledFlags()`
- `v0.1 enables WidgetKit, MCP, and the authenticated helper while CloudKit and Calendar remain dormant.`
  - `FeatureFlagTests/shippingV1ExcludesPreviewIntegrations()`
- `The signed v0.1 Release omits CloudKit and APNs entitlements.`
  - `scripts/release-entitlements.test.mjs`
- `Sparkle is required and its update command is available in the shipping app.`
  - `CurfewUpdaterTests/updateAvailabilityMatchesLinkedFramework()`
- `A conservative v0.1 tag release uploads only its notarized DMG; it cannot
  reference an appcast that Sparkle intentionally did not generate.`
  - `scripts/release-entitlements.test.mjs`
- `The forward-looking PRD and release checklist distinguish the core-only
  v0.1 scope from deferred CloudKit, WidgetKit, Calendar, privileged-helper,
  and Sparkle work.`
  - `scripts/release-entitlements.test.mjs`
- `CI screenshot capture uses unsigned Xcode settings so hosted macOS runners
  produce and upload the MarketingCapture PNG artifacts, and a failed UI test
  fails the job instead of silently exporting misleading images. On a Settings
  scene failure, the test logs the demo app accessibility tree and CI retains
  the result bundle for diagnosis; only synthetic fixture account state is
  present.`
  - `scripts/release-entitlements.test.mjs`
  - `scripts/extract-screenshots.test.mjs`
  - `AppSettingsRoutingTests/settingsRouteUsesSceneAction()`
  - `AppSettingsRoutingTests/earlySettingsRequestWaitsForScene()`
  - `MarketingCaptureTests/testCaptureSettings()`
  - `scripts/extract-screenshots.sh` (local and hosted runtime coverage)
- `Stripe test-mode staging uses an isolated curfew-prefixed Hypertext Studio
  hostname and rejects alternate Worker hostname conventions.`
  - `scripts/license-worker.test.mjs`
- `A Stripe Sandbox checkout can exercise the isolated issuer without a real
  card or production endpoint; webhook delivery and subsequent session-license
  retrieval are recorded as an operator-run staging proof.`
  - `Documentation/license-worker-bootstrap.md` (operator procedure)
  - Stripe Sandbox + isolated staging Worker runtime evidence (external)
- `Operator documentation names only the envelope-v2 Worker bootstrap and
  cannot reintroduce a legacy deployment path.`
  - `scripts/license-worker-documentation.test.mjs`
- `Initial-release app surfaces do not offer a hosted checkout until a release
  explicitly provides one.`
  - `PurchaseAvailabilityTests/checkoutIsUnavailable()`
- `Every public Curfew page exposes the same optional account entry point and
  the macOS download surface describes Android as coming soon.`
  - `scripts/landing-contract.test.mjs`
- `Published legal copy distinguishes local data, end-to-end encrypted account
  content, unavoidable metadata, sign-in backup codes, the Curfew Recovery Key,
  Stripe payment processing, retention, export/deletion, and audited remote unlocks.`
  - `scripts/landing-contract.test.mjs`
- `Curfew source, configuration, and documentation cannot reintroduce the
  retired apex or a service hostname outside the curfew-*.hypertext.studio convention.`
  - `scripts/landing-contract.test.mjs`

## 18. License issuer envelope v2

- `Embed the provisioned Ed25519 public key for the external Worker signing
  seed, including a recovery rotation whenever no retained signer can be
  matched or a signer is exposed and must be discarded before deployment.`
  - `LicenseEnvelopeContractTests/embedsProvisionedPublicKey()`
- `Decode and enforce Curfew Plus subscription claims while retaining legacy lifetime continuity.`
  - `LicenseEnvelopeContractTests/decodesCurfewPlusSubscriptionEnvelope()`
- `Sign the decoded JSON payload for the Worker envelope rather than the base64url text.`
  - `web/worker/test/crypto.test.ts`
- `Generate private signing material only into a caller-selected mode-600 path.`
  - `scripts/license-worker.test.mjs`
- `Render a caller-owned Worker config whose entry point still resolves from
  the fresh clone.`
  - `scripts/license-worker.test.mjs`

## 19. On-device presence detection

- `Cross HID idleness with a camera person signal into working / present-but-idle
  / absent, and an honest unknown when there is no camera signal.`
  - `PresenceFusionTests/hidActivityWinsOutright()`
  - `PresenceFusionTests/idleWithPersonIsPresentButIdle()`
  - `PresenceFusionTests/idleWithoutPersonIsAbsent()`
  - `PresenceFusionTests/idleWithoutCameraIsUnknown()`
  - `PresenceFusionTests/knownPresenceIsNarrow()`
  - `PresenceMonitorTests/presentButIdleIsReported()`
  - `PresenceMonitorTests/absentIsReported()`
  - `PresenceMonitorTests/inputBeatsAnEmptyFrame()`
- `A stale camera reading decays to "no signal" rather than pinning a verdict,
  and a future-dated reading is never treated as fresh.`
  - `PresenceFusionTests/staleObservationDecaysToUnavailable()`
  - `PresenceFusionTests/neverObservedIsNeverFresh()`
  - `PresenceFusionTests/futureObservationIsNotFresh()`
  - `PresenceMonitorTests/staleReadingFallsBackToUnknown()`
- `The camera runs only when the user's setting is on and macOS reports access
  granted, and stops immediately when either stops being true.`
  - `PresenceMonitorTests/disabledCameraNeverStarts()`
  - `PresenceMonitorTests/unauthorizedCameraNeverStarts()`
  - `PresenceMonitorTests/enabledCameraStartsOnce()`
  - `PresenceMonitorTests/disablingStopsTheCamera()`
  - `PresenceMonitorTests/revokedAuthorizationStopsTheCamera()`
  - `PresenceMonitorTests/shutDownStopsTheCamera()`
  - `PresenceAuditWiringTests/defaultModelNeverStartsTheCamera()`
  - `PresenceAuditWiringTests/settingDrivesTheCamera()`
  - `PresenceAuditWiringTests/disablingIsImmediate()`
- `Presence detection ships off and cannot be turned on by an upgrade, a partial
  settings payload, or a refused camera prompt.`
  - `PresenceDetectionPolicyTests/cameraIsOffByDefault()`
  - `PresenceDetectionPolicyTests/legacySettingsDecodeWithCameraOff()`
  - `PresenceDetectionPolicyTests/partialPayloadDecodesWithCameraOff()`
  - `PresenceDetectionPolicyTests/presenceRoundTrips()`
  - `PresenceAuditWiringTests/refusedAccessDoesNotPersistIntent()`
  - `PresenceAuditWiringTests/grantedAccessPersistsIntent()`
- `A camera that will not open is reported as stalled rather than as running.`
  - `PresenceMonitorTests/failedOpenIsReportedHonestly()`
- `Warn a sustained present-but-idle user during working hours only — never at
  an empty chair, never during lockout or a day off, and never more than once
  per repeat window.`
  - `DistractionWarningPolicyTests/sustainedDistractionWarns()`
  - `DistractionWarningPolicyTests/otherStatesHold()`
  - `DistractionWarningPolicyTests/ineligiblePhasesHold()`
  - `DistractionWarningPolicyTests/warningPhaseIsEligible()`
  - `DistractionWarningPolicyTests/briefPauseHolds()`
  - `DistractionWarningPolicyTests/repeatWindowHolds()`
  - `DistractionWarningPolicyTests/disabledHolds()`
  - `DistractionWarningPolicyTests/disabledOutranksEverything()`
  - `DistractionWarningPolicyTests/windowsAreClamped()`
  - `PresenceDetectionPolicyTests/derivedPolicyIsClamped()`
  - `PresenceAuditWiringTests/sustainedDistractionIsNudgedOnce()`
  - `PresenceAuditWiringTests/briefPauseStaysSilent()`
  - `PresenceAuditWiringTests/noNudgeDuringLockout()`
  - `PresenceAuditWiringTests/nudgeSwitchIsIndependent()`
  - `PresenceAuditWiringTests/noNudgeWithoutTheCamera()`
- `Record presence transitions, camera windows, and consent changes in the audit
  log — and never an image.`
  - `PresenceAuditWiringTests/fusedPresenceIsRecorded()`
  - `PresenceAuditWiringTests/legacyPresenceRecordSurvives()`
  - `PresenceAuditWiringTests/authorizationChangesAreRecorded()`
  - `PresenceAuditWiringTests/presenceRecordsCarryNoImagery()`
  - `PresenceMonitorTests/transitionsAreDeduplicated()`
  - `PresenceMonitorTests/secondsInStateTracksTheTransition()`

## 20. Task-scoped browser policy and Docket client

- `URL review never receives credentials, queries, fragments, default ports,
  unsupported schemes, or unresolved dot segments.`
  - `BrowserWorkPolicyTests/destinationNormalizationRemovesPrivateParts()`
  - `BrowserWorkPolicyTests/destinationNormalizationResolvesDotSegments()`
  - `BrowserWorkPolicyTests/destinationNormalizationRejectsOtherSchemes()`
  - `BrowserWorkPolicyTests/pathScopeRejectsUnnormalizedValues(value:)`
  - `BrowserWorkPolicyTests/originScopeRejectsUnnormalizedValues(value:)`
  - `BrowserWorkPolicyTests/rootPathPrefixHasOriginWideSemantics()`
  - `BrowserWorkPolicyTests/crossOriginGrantIsRejected()`
- `A session allowlist is the union of the Docket origin, task references, and
  exact task, project, or label mappings.`
  - `BrowserWorkPolicyTests/initialPolicyUsesEveryTaskOwnedSource()`
- `Idle timer state retains enforcement, while a task switch or terminal task
  state revokes the old session and its grants.`
  - `BrowserWorkPolicyTests/idleTrackingRetainsTask()`
  - `BrowserWorkPolicyTests/switchingTaskRevokesGrants()`
  - `BrowserWorkPolicyTests/terminalTaskEndsSession(stateType:)`
  - `BrowserWorkPolicyTests/differentTerminalTaskEndsSession()`
  - `BrowserWorkPolicyTests/archiveTimestampEndsSession()`
- `A grant expires after 30 minutes, including after a cached policy is restored.
  A denial blocks review for five minutes.`
  - `BrowserWorkPolicyTests/grantExpiresAfterThirtyMinutes()`
  - `BrowserWorkPolicyTests/cachedPolicyExpiresTemporaryAccess()`
  - `BrowserWorkPolicyTests/denialCreatesFiveMinuteCooldown()`
- `One 15-minute break is available for each paused or idle transition. It
  cannot renew until tracking resumes, and resume cancels an active break.`
  - `BrowserWorkPolicyTests/breakEligibilityAndExpiry()`
  - `BrowserWorkPolicyTests/breakCannotRenewWithoutResuming()`
  - `BrowserWorkPolicyTests/resumeCancelsBreak()`
  - `BrowserWorkPolicyTests/pausedToIdleCreatesOneBreakEligibility()`
  - `BrowserWorkPolicyTests/idleToPausedCreatesOneBreakEligibility()`
- `Unknown destinations fail closed during Docket or Athena failure, and stale
  Docket observations cannot restore old work.`
  - `BrowserWorkPolicyTests/unavailableDocketFailsClosed()`
  - `BrowserWorkPolicyTests/staleResponseIsIgnored()`
  - `DocketBrowserPolicyClientTests/reviewFailureFailsClosed()`
  - `DocketBrowserPolicyClientTests/coordinatorRejectsStaleResponse()`
  - `DocketBrowserPolicyClientTests/exactTaskReadDoesNotAdvanceActiveWorkWatermark()`
  - `DocketBrowserPolicyClientTests/taskSwitchInvalidatesReviewResult(kind:)`
  - `DocketBrowserPolicyClientTests/missingTaskResourceFailsClosed()`
  - `DocketBrowserPolicyClientTests/unauthorizedTaskResourceFailsClosed()`
- `Curfew registers and reuses a Docket OAuth client, stores tokens separately,
  refreshes rotating credentials, and can recover from a stored refresh token
  when the access-token record is incomplete. AuthenticationServices matches
  the exact flavor-specific custom callback scheme.`
  - `DocketCredentialStoreTests/loadsRefreshTokenIndependently()`
  - `DocketBrowserPolicyClientTests/oauthRequestUsesSeparateDocketScopes()`
  - `DocketBrowserPolicyClientTests/oauthRegistrationIsPersistedAndReused()`
  - `DocketBrowserPolicyClientTests/oauthRefreshRotatesCredentials()`
  - `DocketBrowserPolicyClientTests/oauthCallbackRejectsDuplicateParameters(value:)`
  - `DocketBrowserPolicyClientTests/coordinatorRefreshesAfterUnauthorized()`
  - `DocketBrowserPolicyClientTests/coordinatorDoesNotLoopOnSecondUnauthorized()`
- `The production transport sends MCP initialize, initialized notification,
  resource-read, and destination-review JSON-RPC messages.`
  - `DocketBrowserPolicyClientTests/httpTransportUsesDocketMCPShapes()`
  - `DocketBrowserPolicyClientTests/activeWorkDecodingUsesPublicContract()`
  - `DocketBrowserPolicyClientTests/mcpRejectsInvalidSSEDataCardinality(frame:)`
  - `DocketBrowserPolicyClientTests/mcpRejectsMismatchedResponseID()`
  - `DocketBrowserPolicyClientTests/mcpRequiresJSONRPCVersionOnEveryResponse()`
  - `DocketBrowserPolicyClientTests/mcpRequiresNegotiatedProtocolVersion(protocolVersion:)`
  - `DocketBrowserPolicyClientTests/reviewRejectsNonDisjointOrEmptyDecision(value:)`
  - `DocketBrowserPolicyClientTests/concurrentFirstCallsCoalesceInitialization()`
  - `DocketBrowserPolicyClientTests/concurrentCallsUseCapturedRequestIDs()`
  - `DocketBrowserPolicyClientTests/taskResourceDecodesArchivedAt()`
  - `DocketBrowserPolicyClientTests/mcpReinitializesAfterOneDeadSession()`
  - `DocketBrowserPolicyClientTests/mcpDoesNotLoopOnSecondDeadSession()`
  - `DocketBrowserPolicyClientTests/oauthRegistrationRejectsOversizedResponse()`
  - `DocketBrowserPolicyClientTests/oauthTokenExchangeRejectsOversizedResponse()`
  - `DocketBrowserPolicyClientTests/mcpRejectsOversizedResponse()`
- `The coordinator polls at 30 seconds while idle and five seconds while it
  retains work. It reads the retained task after Docket reports idle.`
  - `DocketBrowserPolicyClientTests/pollCadenceTracksRetainedSession()`
  - `DocketBrowserPolicyClientTests/idleObservationChecksTerminalTask()`
  - `DocketBrowserPolicyClientTests/idleObservationChecksArchivedTask()`
  - `DocketBrowserPolicyClientTests/nullTaskObservationChecksArchivedTask(tracking:)`
  - `DocketBrowserPolicyClientTests/failedNullTaskReadRetainsEnforcement(tracking:)`
  - `BrowserNativeLifecycleTests/restartIdlePollClearsACompletedOrCanceledRetainedTask(stateType:)`
  - `BrowserNativeLifecycleTests/restartIdlePollClearsAnArchivedRetainedTask()`
  - `BrowserNativeLifecycleTests/restartIdlePollKeepsANonterminalRetainedTaskFailClosed()`
  - `BrowserNativeLifecycleTests/restartTaskReadFailureKeepsTheRetainedPolicy(error:)`
  - `BrowserNativeLifecycleTests/oldSignedPolicyWithoutSessionIdentityRemainsFailClosed()`
  - `DocketBrowserPolicyClientTests/destinationReviewUsesNormalizedPayload()`
- `Settings records setup once, reports current health, and gates enforcement
  until both Docket and Chrome have connected.`
  - `BrowserIntegrationSettingsStoreTests/setupFactsAndMappingsPersist()`
  - `BrowserIntegrationSettingsStoreTests/setupGateRequiresBothConnections()`
  - `TaskBrowserEnforcementViewModelTests/freshSetupIsReady()`
  - `TaskBrowserEnforcementViewModelTests/staleHeartbeatIsUnhealthy()`
  - `TaskBrowserEnforcementViewModelTests/missingHeartbeatIsNever()`
  - `TaskBrowserEnforcementViewModelTests/missingSetupDisablesToggle()`
  - `DocketBrowserPolicyClientTests/authenticatedIdlePollRecordsSetupSuccess()`
- `The panel drives policy disable and restore, local mapping changes, one
  paused-session break, and Docket connect and disconnect.`
  - `BrowserNativeLifecycleTests/disablingEnforcementClearsAndReenablingRestoresTheRetainedPolicy()`
  - `TaskBrowserEnforcementControllerTests/controllerDrivesPanelActions()`
  - `TaskBrowserEnforcementPanelTests/panelCopyStaysTaskScoped()`
  - `CurfewUITests/testTaskBrowserEnforcementPanelActions()`
- `Development capture fixtures never enter the production blocker output.`
  - `DemoFixtureTests/browserDemoState()`
  - `blocker-state.test.ts` checks the explicit development fixture state.
  - `build.test.ts` checks that production output omits the fixture task.
- `Browser policy snapshots expose only the current task ID and title. They keep
  expiring grants separate from base scopes and evaluate temporary access at the
  caller's current time.`
  - `BrowserWorkPolicyTests/snapshotSerializationOmitsDocketTaskContext()`
  - `BrowserWorkPolicyTests/cachedPolicyExpiresTemporaryAccess()`
## 19. UI simplification and visual acceptance

- Task-based Settings and compatible identifiers:
  - `SettingsSectionTests/sectionSet()`
  - `CurfewUITests/testSettingsUsesSidebarAndShowsOnlyRelevantControls`
  - `CurfewUITests/testMinimumSettingsWindowRetainsAllConsentChoices`
- Plain-language consent, readiness, and shutdown:
  - `AIConsentPolicyTests/consentLabelsArePlainLanguage()`
  - `EnforcementHealthTests` and `SystemSurfaceBehaviorTests`
  - `AutoShutdownConfigurationTests/shutdownCountdownStatusLine()`
  - `CurfewUITests/testOffStateDoesNotPromiseAnActiveLock`
  - `CurfewUITests/testReadyFixtureDoesNotImplyCurfewIsOn`
- Setup gating, conditional schedule controls, assistant feedback:
  - `CurfewUITests/testSetupUsesOneInstructionAndPreservesScheduleGate`
  - `CurfewUITests/testScheduleHidesTimeControlsForDaysOff`
  - `CurfewUITests/testAssistantSetupShowsCopyFeedback`
  - `CurfewUITests/testPromptEditorDoesNotAdvertiseFutureFeatures`
- Capture safety and visual evidence:
  - `DemoFixtureTests/demoModelCannotArmEnforcement()`
  - `DemoFixtureTests/demoScheduleEditsCannotEnterEnforcementCycle()`
  - `DemoFixtureTests/menuBarOffCopyIsHonest()`
  - `CurfewUITests/testReviewOpensPendingRequestAndDenyDismissesIt`
  - `CurfewUITests/testExhaustedOverridesExplainWhyEntryIsUnavailable`
  - `MarketingCaptureTests` asserts fixture window/overlay identity before capture.
  - Existing policy, MCP signing/consent, schedule, budget, override, and license
    tests remain the behavior regression gate; screenshots do not replace them.

- Settings polish and sentence-case labels:
  - `SettingsTypographyTests/noAllCapsOverlines()` protects the presentation sources
    from forced casing and letterspaced overlines.
  - `CurfewUITests/testGeneralKeepsNavigationAndSetupInView`
  - `CurfewUITests/testGeneralPermissionFailureFitsMinimumWindow`

- Shared disabled and Reduce Motion button feedback:
  - `ButtonFeedbackTests/disabledFeedback()`
  - `ButtonFeedbackTests/reducedMotionFeedback()`
  - `ButtonFeedbackTests/enabledFeedback()`

- Native Settings navigation and reliable lower-position captures:
  - `CurfewUITests/testSettingsSidebarSupportsArrowKeys`
  - `CurfewUITests/testManageAIAccessAlwaysOpensConnections`
  - `MarketingCaptureTests/scrollToBottom` targets the detail pane, asserts its
    vertical position is at the bottom, or proves lower content fits without a bar.

- Keep degraded General controls visible without repeating the helper error:
  - `CurfewUITests/testGeneralHelperFailureFitsMinimumWindow`
- Explain assistant read access before its toggle is enabled:
  - `CurfewUITests/testAssistantReadAccessIsExplainedBeforeEnabling`

- Capture the actual warning timer instead of the desktop:
  - `MarketingCaptureTests/testCaptureOverlays` asserts `warning-timer` and
    `warning-countdown` before capturing the borderless container.
  - `CurfewUITests/testWarningAndLockoutPresentation` retains countdown semantics.

- Capture state assertions use a frozen accessibility tree; native disclosure
  expansion and destructive-dialog cancellation are asserted before capture.
  Final critical-state and overlay suites pass in
  `build/ui-capture-snapshot-final.xcresult`; the gallery retains 160 current images.
  Outstanding state and assistive-technology coverage is listed in
  `Documentation/ui-state-review.md`.

- Unified app theme:
  - `ThemeConsistencyTests/textContrast`: body, secondary, and link text meet
    4.5:1 on shared canvas/card/muted surfaces in Aqua and Dark Aqua.
  - `ThemeConsistencyTests/sharedPalette`: Settings and sky controls consume
    shared palette roles; no separate gray sidebar tint.
  - All capture suites are rerun for global palette changes; visual acceptance
    remains separate from numerical contrast checks.

- Background-only theme verification (`scripts/test-theme-background.sh`):
  - `ThemeConsistencyTests/filledActionContrast`: white labels meet 4.5:1 in
    both appearances.
  - `ThemeConsistencyTests/atmosphericContrast`: night gradient stops preserve
    4.5:1 text and 3:1 icon contrast.
  - `ThemeConsistencyTests/nativeAccentConsistency`: asset RGB values remain
    aligned with resolved filled-control tokens in Aqua and Dark Aqua.
  - `ThemeConsistencyTests/noViewColorLiterals`: flags view-level RGB constructors
    outside the two palette definitions; failing-first proof catches the warning
    and static lockout's former independent colors.
  - Existing contrast coverage now includes sidebar canvas and warning text.
  - The generated package compiles actual symlinked source files; it excludes
    the app entry point, UI test bundle, and permission/enforcement model startup.
    It is targeted verification, not the full application unit suite.

- `ThemeConsistencyTests/reflectionInputContrast`: normal/reduced-transparency
  input backings keep primary and supporting text above 4.5:1 even over white.
- `ThemeConsistencyTests/progressContrast`: the hold progress wash retains
  filled-control label contrast in both appearances. These checks composite
  alpha before computing luminance; they do not ignore supporting-text opacity.
- Architecture guards also reject generic secondary overrides and one-off
  white-opacity reflection text, so those screens consume the tested roles.

## Current-main integration coverage

- `ModuleBoundaryTests`: app-facing credential and browser interfaces remain
  accessible across the shared-library boundary; background Keychain query
  contexts forbid interaction. No real credentials are read or changed.
- `DaemonIdentityIntegrationTests`: stable lockout/campaign identity through
  resolution and coding; replayed remote result identity; flavor-specific signing
  requirements and unsigned/invalid team rejection.
- `AuthenticatedDaemonControlTests`: strengthening-only local arms, authenticated
  heartbeat identity, override rejection, independent remote authority, bounded
  local release tombstones, restart/replay safety, legacy-shadow wake completion,
  idempotent acknowledgement retry, and uninstall refusal with remote authority.
- `DaemonServiceIntegrationTests`: corrupt local archive retains independent remote
  authority and reports degraded transport without overwriting evidence; failed
  persistence never acknowledges or applies a new arm. Uses temporary files and
  injected effects, never a daemon process or machine shutdown.
- `PrivilegedHelperManagerTests/failedWakeCompletionRequiresRetry`: failed RPC
  returns an explicit negative acknowledgement and preserves visible failure state.
- `ThemeConsistencyTests/settingsSectionsDoNotNestDecorativeCards`: newer main
  panels share native Settings forms. The existing literal-color guard now also
  rejects view-level named hue overrides; numerical contrast checks cover their
  shared roles in both appearances.
- `scripts/xcode-package-layout.test.mjs`: single Xcode package graph, isolated
  helper Mach services, existing format paths, and remote package/UI/Release gates.
- `MarketingCaptureTests/testCaptureSettingsMatrix`: Connections capture also
  asserts account panel presence. Interaction tests route to Connections and open
  destination details before operating browser controls.
- Existing enforcement, protected-work, emergency-release, remote-command,
  account/recovery, schedule, budget and persistence suites remain required.
  Local `build-for-testing` compiles their targets without executing the app host;
  remote CI runs actual hosted suites and captures. Numerical/source checks and
  successful compilation alone do not establish visual or system acceptance.

Authenticated liveness integration: after authenticated arming or a matching heartbeat, legacy heartbeat files cannot keep that window alive. Unmigrated legacy windows retain file fallback. `AuthenticatedDaemonControlTests` covers persistence and binding to the current window; signed transport verification remains a remote/system acceptance gate.

Remote CI follow-up: screenshot extraction preserves the original failed UI-test exit status before attempting export. Authenticated liveness accepts a still-active local source during delayed stronger remote-deadline delivery, without changing effective authority or accepting unknown IDs. Regression checks cover both cases.

Landing integration: restored the account navigation and Android coming-soon notice after the directory migration; removed stale claims that Plus sync is currently available. All 30 script/landing/release-policy tests pass and run in CI.

Fixture safety review: demo Settings uses an ephemeral account secret store and inert enrollment services; synthetic camera authorization cannot prompt TCC or open Camera Settings. Real account checkpoints, recovery keys, network enrollment, and camera access stay outside captures. ThemeConsistencyTests includes a fixture-wiring regression (14 theme/UI-source tests total). Assistant disclosure includes activity access.

Remote full-suite follow-up: package endpoints now derive app/widget service isolation from their bundle identity when app-only compilation flags cannot propagate into SwiftPM; standalone tools retain their explicit service flag. Setup tests inject Accessibility trust, consent-copy expectations use the approved shorter labels, and the browser uninstall test waits for actual enqueue under loaded CI.

Remote capture correction: fully fitting native forms may expose a scrollbar with zero range. Bottom captures now verify the lowest text/control bounds as well as scrollbar position, and accommodate native wheel direction; long clipped panes still fail. The initial remote General capture was visually inspected and shared inline; it is interim evidence until final-head recapture.

The independent `landing/` package owns Astro source and native Workers hosting. Root commands and `just landing` use that package directly; backend workspace setup does not publish the frontend.

Visual inspection found the isolated runner Dock overlapping Today’s primary action. Screenshot CI now hides and delays only its own Dock before capture; no local desktop preferences change. A workflow regression check protects this capture setup, and unobstructed recaptures are required.

Remote interaction follow-up: assistant-access checks include the disclosed activity scope. Browser mapping checks scroll the disclosure into view and assert its expanded state before editing. CI preserves interaction result bundles separately from capture results, so failed control queries include their accessibility tree and screenshots. No local UI execution is required.

Capture review also found that Connections state screenshots showed only the top account/browser sections while their asserted AI/calendar/sync content was below the viewport. Each affected state now includes a second bottom capture; top captures remain for context. Native disclosure interaction targets the leading arrow, consistent with the existing helper-details capture.

Remote visual review found black override-reason text on a dark input in light appearance. The override editor now binds the shared atmospheric foreground and contrast-tested input surface, matching reflection inputs. `ThemeConsistencyTests/overrideInputPalette` was observed failing first; existing input contrast tests cover both appearances and transparency modes. Override rules, cooldown, hold, and persistence stay unchanged. Recapture the affected override states before merge.

Remote interaction checks run before the longer capture matrix. Disclosure navigation measures its actual position and scrolls within the pane until visible, accommodating native wheel direction rather than assuming a fixed offset.

Full-resolution Today review found washed-out schedule labels over the bright sky/page fade. The hero now uses the shared atmospheric text scrim and supporting-text role, backed by the same contrast-tested surface as reflection/override inputs. `todayHeroPalette` was observed failing first; the existing white-backdrop checks establish at least 4.5:1 for both text roles. Recapture Today in both appearances and window sizes.

The shared sky text scrim also protects lockout status and recovery controls. Faint per-view text-opacity variants were replaced with the shared supporting-text role, including shutdown failure, cooldown, validation, and exhausted-budget messages. `lockoutAtmosphericPalette` was observed failing before implementation. This changes presentation only, with no enforcement or exception-policy change.

Remote browser interaction recording showed the destination disclosure inheriting its section identifier and not opening under automation. It now has a unique accessibility target and explicit transient expansion binding. `browserDisclosureAccessibility` was observed failing first; the interaction test verifies the actual mapping removal control appears and exercises removal. No stored setting or browser enforcement rule changes.

The browser disclosure uses the same labeled button pattern as Manual setup: the entire row opens it, it participates in keyboard navigation, and VoiceOver receives Expanded/Collapsed. This avoids native Form chevron-only hit areas. The source regression was observed failing for the button action and accessibility value before implementation.

The remote AX lookup demonstrated section-level identifier propagation overriding browser child identifiers. The retained panel identifier now belongs to its heading, leaving the disclosure, enforcement switch, and break action individually addressable. The regression checks require this header scope; remote interaction remains the acceptance gate.

### Contradictory UI state review

- `PresentationStateTests`: Today off/locked wiring, setup action routing,
  completed-setup dismissal, shared helper failure copy. Four source-wiring
  regressions were observed failing before implementation.
- `ConsentPresentationTests`: configured extension duration, unavailable extension,
  schedule times and overnight unlock, weakening delay, day off, malformed JSON
  and times, and unavailable legacy override. Tests preceded the new pure preview
  type; the first run failed because that type did not yet exist.
- `EnforcementHealthTests`: health resolution remains covered; updated copy and
  remediation expectations were observed failing before the changes. Warnings
  describe readiness failures without implying Curfew is currently locking.
- `scripts/test-theme-background.sh` includes these pure checks without an app
  host, windows, permission requests, or enforcement effects.
- Remote capture assertions use the revised helper and keyboard failure copy.
  Visual acceptance and real signed-helper verification remain separate gates.
- `TaskBrowserEnforcementViewModelTests`: existing freshness/setup regressions now
  run hostlessly; added stale-extension repair and off-preference summary checks.
  `PresentationStateTests/browserCopy` failed before the panel changes. A missing
  summary API failed before its implementation. The view model moved intact to a
  separate pure file so background tests do not instantiate browser services.
- `ConsentPresentationTests/pendingReplacement`: same-schedule cancellation and
  changed-schedule replacement disclose pending edits lost on another weekday.
- `PresentationStateTests/canonicalSync`: enrolled account hides inactive legacy
  service rows; observed failing before the visibility correction.
- `CalendarPresentationTests`: injected denied/restricted/not-determined/write-only
  access replaces stale full-access status without constructing an event store;
  extension advice matches eligibility. Tests preceded the new injection/copy APIs.
- Consent content scrolls independently of decision buttons so long assistant
  reasons cannot push Deny/Approve offscreen; unavailable requests say so directly.
- `MarketingCaptureTests/testCaptureAStateConsistency`: actual-window assertions for
  off/locked Today, completed setup with and without Accessibility, and malformed
  consent with disabled Approve. Runs only on the isolated runner, in light/dark
  at both sizes. `PresentationStateTests/stateFixtures` failed before fixture wiring.
- `PresentationStateTests/shutdownCopy` failed before removing shutdown build jargon;
  `ShutdownPanelStateTests` retains availability and essential Automation consent checks.
- `configure-ci-display.test.mjs`: select an advertised mode fitting default windows,
  reject insufficient display modes, and refuse execution outside isolated CI.
  The first run failed before the script existed. No local display changes occur.
- `PresentationStateTests/uncroppedCapture`: observed failing before comparing actual
  screenshot dimensions to the asserted window frame. Previously clipped default
  images do not prove layout acceptance, even if their screenshot suite passed.

### Account readiness consistency after main integration

`DaemonRegistrationRepairTests` exercises the actual replacement workflow with
isolated OS-operation boundaries: `orderedRepair`, `admissionFailure`,
`registrationFailure`, and `authenticationFailure`. All four failed before the
workflow was implemented and passed afterward. These do not register a real
helper, inspect protected state, sign in, or control the desktop; signed-app
wiring and live acceptance remain required.

Review regressions: `cancellationDuringRemoval` and
`cancellationDuringVerification` failed before adding cancellation fences;
`concurrentRepairIsRejected` covers overlapping entry. Final producer activation
is a synchronous, nonthrowing MainActor commit. `DaemonMaintenanceAdmissionTests`
validates expired remote state, both local deadline files, malformed control
state, device mismatch, and active authenticated/legacy control formats.
`mixedControlFormatBlocks` observed the malformed authenticated-to-legacy
downgrade before shape discrimination fixed it. These tests use isolated data;
file ownership, authorized bounded reads, producer quiescence, and installed
SMAppService replacement still require their app-boundary implementation.

Installed-runtime acceptance on 2026-10-12 remains incomplete despite passing
native CI `38315375674`: the signed StudioDev update is installed, but launchd
retains a legacy helper registration without the authenticated XPC endpoint.
The current Codex OAuth reconnect failed in Chrome and the hidden in-app browser;
staging logs identify D1 write-quota errors in authorization and token refresh.
Ordinary sign-in loads, so browser extension attribution remains unproven.
Existing fixture/hostless coverage does not exercise that migration
or prove real connector authentication. See `remote-mcp-acceptance.md`; no
additional lock/unlock or local UI test was run for this documentation correction.

Remote locks require both a fresh daemon heartbeat and an authenticated ready connection, while Studio Dev still yields to a live higher-priority Curfew owner. Settings refreshes signed status on opening, activation, and the existing heartbeat interval. Pending approval opens the macOS approval pane; installed connection failures route to General; installation is offered only when needed. Account messages describe an unchanged schedule instead of claiming protection is active.

Signed Studio Dev launch policy: `StudioDevLaunchBehaviorTests` checks that its
Debug-compiled app arms without an opt-in variable, ignores spoofed test-host
environment markers, and rejects the demo fixture; personal Debug cannot spoof
Studio Dev through `CURFEW_FLAVOR`. The existing Debug and Release tests retain
their respective policies. The assertions failed at compile time before the
bundle-bound policy parameter existed. `CurfewApp` passes its actual bundle ID,
and `RuntimeEnvironment.testHostDecision` requires a loaded XCTest runtime for
both signed Studio Dev and Release even when test environment markers are
present. The installed signed launch audit records `enforcementArmed: true`
and active health. A separately authorized Codex Staging lock subsequently
produced an applied receipt, a live locked report, the installed app's
`lockout.started` event, and a full-screen enforcement window; the report,
audit stream, and window all returned to working/absent at the deadline. This
is manual installed-runtime acceptance, separate from automated coverage and
from the still-unverified Claude-phone and remote-unlock journeys. See
`remote-mcp-acceptance.md`; no further control command is authorized.

Local status truthfulness remains open: the verified remote lock exposed that
`curfew-ctl status` and local MCP's `curfew_status` / `curfew_get_time_remaining`
derive a schedule prediction instead of observing the app/daemon. A future
regression must exercise the actual CLI and MCP outputs with controlled fresh,
stale, remote-lock, release, disarmed, and cross-flavor observations. The
current native and MCP suites do not cover that claim; do not count the
coordinator's correct status report as coverage of these local readers.

Hostless coverage: `PrivilegedHelperManagerTests.remoteReadinessRequiresAuthenticatedConnection` rejects unavailable, unauthorized, stale, and failed registration despite a fresh heartbeat file. `PresentationStateTests` checks recovery routing and copy. The new assertions failed before the fix; CI retains full app behavior and screenshot checks. No local UI execution or app launch. This changes readiness presentation and recovery routing, not enforcement rules, persisted identifiers, or the wire format. Rollback is the readiness/copy change; signed helper and real macOS approval verification remain separate.

Account consistency captures add `account-offline`, `account-sign-in-required`, and `account-helper-unavailable` in both appearances and sizes. They use an explicitly injected no-op account transport; the helper rejection is synthetic. Assertions require the matching status and repair action before window capture. No account sign-in, Keychain, network enrollment, or helper registration occurs.

Account rejection copy now distinguishes expired sign-in, explicit server access denial, and local remote-update failures. A version without background protection explains availability without directing to a hidden General section. `AccountStatusPresentationTests` exercises actual status-to-copy resolution in the hostless suite; both regressions failed before correction. The existing sync status enum is extracted unchanged for hostless coverage, with no identifier or wire changes.

Final recovery-copy review: Today’s off state describes following the local schedule without promising that independent remote controls cannot lock the Mac. Uninstall failure uses the product action as its heading, with specific diagnostics retained. Unavailable remote locks offer Get Curfew using the shared production website origin rather than a duplicated URL. `PresentationStateTests.offAndRecoveryCopy` failed first; the unavailable-feature screenshot asserts its website action. Enforcement, uninstall order, and account behavior are unchanged.

| Menu-bar contrast and setup state | `ThemeConsistencyTests.menuBarContrastAndAccess`, `CurfewUITests.testMenuBarPopoverOpensActualView` | Hostless regression fails first; remote interaction opens the real status item. |
| Menu-bar visual state coverage | `MarketingCaptureTests.testCaptureMenuBar` | Ready, permission missing, keyboard interrupted, verification failure; both appearances; fixed-width popover and complete screenshot geometry asserted. |

| Off plus scheduled warning | `PresentationStateTests.menuOffExtension`, `CurfewUITests.testOffMenuDoesNotOfferAnExtensionDuringScheduledWarning`, `MarketingCaptureTests.testCaptureMenuBar` | Menu hides the grant action while disarmed, even when the schedule offers it; both appearances captured remotely. |

Remote capture regression: locked evaluations retain a zero-minute display value.
Today now checks the phase explicitly before showing a countdown, so an off Mac
with a past scheduled lock shows “Curfew is off. Review your schedule.” instead
of “0:00.” The state-consistency capture runs first to expose fixture failures
early. `PresentationStateTests.lockedCountdown` and the remote capture both cover
this presentation-only correction; enforcement and stored schedules are unchanged.


Returning setup review now derives its content from the saved setup state instead
of the walkthrough cursor. A revoked Accessibility grant immediately shows its
repair action; completed review hides the first-run checklist and never arms
protection. The remote missing-permission capture exposed a real blank-panel
regression. `PresentationStateTests.setupReviewContent` and the setup-review
capture states cover the correction. CI runs the new state matrix in a separate
preflight before the full capture sweep, preserving failure diagnostics early.
No permission, persistence, enforcement, or onboarding completion rules changed.
Rollback is limited to presentation and CI ordering.

The preflight uses nine independent XCTest methods, one per state family. A failure
in one state does not prevent the other families from being exercised; each still
asserts its own screen and state before attaching an image.

AI weekly allowance: `AuditGrantWiringTests.exhaustedAIExtensionIsNotGranted`
exercises actual manual and automatic model approval with an exhausted tracker.
Both regression cases failed before implementation on remote run 38114876113.
`availableAIExtensionConsumesAllowance` covers the successful path. The pure
`ConsentPresentationTests.exhaustedExtension` and source binding/fixture check
cover the disabled action and reason. Ten preflight families include an actual
exhausted consent sheet in four appearance/size combinations. No local app launch.

Website identity: `landing/tests/unit/design.test.mjs` verifies the shared
design source, user-facing product proposition, real navigation pages, and
absence of the standalone MCP fixture. `scripts/landing-contract.test.mjs`
preserves account navigation and legal policy assertions. The Astro build and
`landing/tests/acceptance/site.spec.mjs` cover rendered routes, keyboard
navigation, and imagery in Chromium, Firefox, and WebKit. Manual phone/desktop
light/dark captures cover layout and overflow. No native app or account
backend behavior changes; rollback by restoring the previous website commit.

Guide routing: `landing/tests/unit/design.test.mjs` maps prominent guide
links to navigation entries in `web/docs/docs.json`; its new assertion failed
before the link correction. `landing/tests/acceptance/site.spec.mjs` checks
the published Guides destination and the retained HTML guide's anchors.
`pnpm --dir landing docs:check` validates the Mintlify source. Hosted checks
must confirm each published destination and the live landing links after the
Mintlify and Workers deployments. No account, native app, or wire behavior
changes; rollback restores the prior landing release and docs commit.

- Website hosting configuration: native `cf build --mode staging` and
  `cf build --mode production` must emit `DOCS_MODE=mintlify` with the reviewed
  upstream and static assets. Validate the selected production bindings through
  native `cf deploy --prebuilt --mode production --dry-run --provision=false`
  before requesting cutover approval. Existing
  `landing/tests/unit/site-worker.test.mjs` covers proxy routing and credential
  isolation; `landing/tests/acceptance/site.spec.mjs` uses the explicit local HTML
  guide mode through the same native hosting configuration.
- Workers asset safety: static artifact sealing rejects `_worker.js` and
  `_routes.json`; `.assetsignore` also excludes them from Static Assets.
  Validate ordinary native staging/production build and prebuilt dry-run output.
  Signed native activation selects the verified prepared directory through the
  existing production `assetsDirectory` setting rather than rebuilding Astro.
- Account navigation: hosted marketing `/account` must return a noncached 302
  to the existing staging portal. Account subpaths, query-bearing callbacks,
  POST bodies and Authorization-bearing requests must not use this handoff.
  `landing/tests/unit/site-worker.test.mjs` verifies that overlapping site and
  portal host configuration returns a noncached 503 without a redirect loop.
  Accept the destination's actual sign-in delivery separately; the marketing
  Worker does not own account sessions or API behavior.

## 19. User-facing documentation and launch acceptance

- `Public help covers setup, daily use, Plus, integrations, and recovery while retaining existing routes.`
  - `scripts/user-docs.test.mjs` — navigation journeys, unique routes, front matter,
    local page links, and removal of issuer API references.
- `Activation and purchase recovery describe the actual About panel and confirmation-page delivery.`
  - `scripts/user-docs.test.mjs` — activation route, receipt distinction, and no
    unsupported payment-success claims after failed key delivery.
- `Assistant help explains provider processing; upcoming Plus guides do not imply current availability.`
  - `scripts/user-docs.test.mjs` — provider disclosure and launch availability notes.
- `Help accurately explains local-read disconnection, legacy override rejection, saved-schedule countdowns, and older-entry export before uninstall.`
  - `scripts/user-docs.test.mjs` — four reviewer-found regressions, each observed
    failing before correcting the guide; documentation tests also run in CI.
- `Public help avoids self-narrating editorial phrases and unnecessary contrast.`
  - `scripts/user-docs.test.mjs` — observed failure for the old guide prose and
    purchase-confirmation narration before the copy audit. Existing factual
    checks retain availability, disconnection, export, and enforcement limits.
- `Mintlify renders the help with working navigation, anchors, and external links.`
  - `mint validate` and `mint broken-links --check-anchors --check-external`
  - Desktop/narrow, light/dark, and keyboard inspection of `mint dev` (manual).
- `Launch instructions match signed app, purchase/provider, and actual hosted behavior.`
  - `Documentation/user-docs-launch.md` — exact-artifact/operator acceptance;
    intentionally pending until observed, not inferred from documentation tests.

## Legal page readability

- `Current legal pages group title, introduction, dates, and update navigation.`
  - `landing/tests/unit/legal.test.mjs` checks one publication date and grouped metadata.
  - `landing/tests/acceptance/site.spec.mjs` checks metadata and history navigation in the rendered pages.
- `Archived privacy tables retain column context in their stacked narrow layout.`
  - `landing/tests/unit/legal.test.mjs` verifies labels are derived from retained table headings.
  - `landing/tests/acceptance/site.spec.mjs` checks visible mobile labels and overflow.
- These changes affect website presentation only. Policy source archives, native app,
  enforcement, billing, and providers are unchanged. Rollback restores the prior
  landing build; publication requires the normal website release checks.

## Domain migration

- Owner-only maintenance: backend policy/owner/auth/admission/recovery/passkey/billing/socket suites cover strict deployment binding, normal Apple/authenticator/recovery/Google onboarding, credential isolation, single-use DPoP, bounded bodies, private commit deadlines and actual Durable Object hibernation/alarms. Backend operator tests cover exclusive private input files, phase/environment mismatch, checkpoint/fence ordering, no repeated revocation, audit isolation, staging credential retention and cf database identity/schema/migration checks. Actual provider, signed native and physical-device journeys remain live gates.

| Behavior | Automated coverage | Live acceptance |
| --- | --- | --- |
| Derived URLs, invalid origin rejection, immutable artifact identity | `scripts/deployment-config.test.mjs` | Same artifact/hash in native and backend release |
| New native endpoints and authorization-only migration | `DeploymentEndpointTests`; `AccountOAuthEnrollmentTests` | Same Mac reconnects and reads retained encrypted data |
| Safe public redirect and API retirement | `landing/tests/unit/domain-routing.test.mjs`; license domain tests | DNS/TLS and old/new host requests |
| Recovery gate, transactional revocation and idempotency | curfew-sync `domain-migration.test.ts`, `service-config.test.ts` | Provider-ready maintenance cutover and drained fences |

- Release endpoint provenance: `scripts/release-configuration.test.mjs` covers configured and alternate domains, changed manifests, source revisions, and signing keys; `scripts/release-candidate.test.mjs` binds native configuration and candidate signatures to the shared deployment identity.
- Provider administration: use approved native CLI access outside PR validation. `scripts/deployment-config.test.mjs` prevents the website workflow from receiving production Cloudflare deployment credentials; provider inventory remains access evidence, not release acceptance.

- Domain migration operator sequence: backend `scripts/production-audit.test.mjs` verifies readiness before production mutations; `scripts/cutover-readiness.test.mjs` covers receipt completeness, identity and freshness. Email sender activation additionally requires Cloudflare DNS verification and live delivery acceptance.

- Public policy announcement: browser acceptance covers separate header, notice, and hero bounds at 1920, 390, and 320px; current-policy checks preserve rights and exclude internal implementation inventories. The home regression also checks that the stylesheet URL matches the current CSS content.

## Private web build cache

- `scripts/turbo-cache.test.mjs` verifies the Studio endpoint, Curfew namespace,
  signed artifacts, uncached deploy/development tasks, native Turbo invocation,
  pinned shared authentication action and trusted-main credential boundary.
- `pnpm --dir web typecheck` checks both web packages; CI runs the same task after
  short-lived workload-identity authentication. An authenticated two-run Turbo
  HIT remains the live acceptance check; source assertions alone do not prove it.
- This affects development checks only. The native app, release signing, license
  behavior, Astro frontend and Mintlify publishing remain independently managed.
  Removing remote authentication returns CI to its existing local-only cache.

## 20. Plus activation and purchase restoration

- `A paid checkout opens Curfew in one click and persists a verified license.`
  - `web/worker/test/purchase-flow.test.ts`: paid/unpaid webhook boundary,
    activation ticket exchange/redemption, expiration, no-store responses.
  - `LicenseActivationTests`: real Ed25519 verification, offline reload,
    rejection of forged/expired keys, strict build-specific URL parsing, and
    repeated-callback race (observed failing before the fix).
  - `landing/tests/acceptance/site.spec.mjs`: primary activation link, manual
    fallback, delayed delivery, unavailable service, and retry entry point.
- `Restoration proves purchase-inbox ownership without requiring an account.`
  - Issuer tests: identical unknown/known inbox responses, delivery link without
    a license, latest subscription refresh, rate-limit/invalid-email failures,
    missing email setup, and signed legacy-event index repair.
    Review regressions cover unrelated-product rejection, actual signed renewal
    followed by cancellation, and old `curfew-pro` lifetime keys without `plan`.
    Additional failing-first cases cover metadata-free checkout backfill, prior
    cancellation repair, Unicode inboxes, and a deliberately delayed older
    invoice completing after a newer one. All 16 issuer tests pass.
  - Browser tests: email form, sent state, activation link from fragment,
    fragment removal and same-document navigation.
  - `LicenseActivationTests/requestsRestoration`: sending a link does not grant Plus.
  - `LicenseActivationTests`: failed silent refresh, stale refresh after a newer
    activation (including the same subscription), and canceled restore completion
    while a subsequent request remains suspended.
    `cancelsQueuedActivation` verifies cancellation before task execution sends
    no redemption request and leaves no progress/error state.
    `isolatesIssuerEnvironments` checks production/development URL selection and
    that activation and renewal use the same build-specific issuer.
    `isolatesIssuerSigningKeys` checks fixed production/development signer pins.
    `productionLicenseTrustIgnoresEnvironmentOverrides` checks production bundle
    selection despite the generic flavor resolver accepting a development
    override, plus the isolated development/Studio Dev bundle identities.
  - `scripts/license-worker.test.mjs`: opt-in recovery configuration fails closed
    with missing settings and renders a sender allowlist plus two rate limits.
  - `CurfewUITests/testPurchaseRestoreAndManualActivationAreReachable`: native
    restore sheet, empty-field validation, cancellation, and manual-key fallback.
    CI at `3f12cda` failed to expand the disclosure; the replacement test uses
    the accessible manual-entry button and checks that its field appears.
    The later recording shows Expanded with an unnamed field; the fix adds an
    explicit label/identifier and checks both expansion and identified input.
    The hosted interaction passed at `8399b8a4` in 12.392 seconds.
- `The purchase preview has its own host without changing coordinator routes.`
  - `landing/tests/unit/site-worker.test.mjs`: observed the absent staging route
    first, then verifies the dedicated hostname, disabled workers.dev/previews,
    and unchanged production routes.
- `The issuer exposes its public verification identity without secret material.`
  - `web/worker/test/purchase-flow.test.ts`: exact public-only health response,
    issued-envelope verification against that key, and generic 503 for a bad
    signer. Both assertions failed first; all 18 issuer tests pass.
- `Actual provider and installed-app behavior matches the new path.`
  - `Documentation/plus-activation.md`: provider/signer pairing, test checkout,
    actual sandbox checkout, matching public signer and authenticated restore
    inbox delivery, actual native Debug checkout/restoration, cold opening and
    retained entitlement after a fresh process launch are recorded. Owner-clicked
    signed candidate activation and retained entitlement also pass. The signed
    native restore form delivered its real email, and the owner-clicked handoff
    shows active, verified lifetime access in that candidate. Production
    distribution remains pending.
  - Authenticated Apple account and downloaded public-certificate metadata
    establish Studio team `T95VDD3A4W`, its existing signing certificate and
    notarization key ID. GitHub secret metadata confirms the verified issuer is
    configured. These checks establish setup metadata, not signing or notarization
    success; private-file provisioning and team alignment remain unfinished.
  - The approved CI certificate matches its generated key; `notarytool history`
    authenticates with the new dedicated key. GitHub secret metadata confirms all
    six Apple inputs are configured. Artifact notarization remains unverified.
- `Release signing matches the verified Studio account.`
  - `scripts/release-entitlements.test.mjs`: app, widget and artifact-verifier
    identity must match `T95VDD3A4W`; the regression failed before the correction
    and passes afterward. The twelve release-policy tests pass.
- `Lifecycle reconciliation tests use an isolated license store.`
  - `LifecycleWiringTests/licenseActivationReconciles()`: observed failing with
    the real retained sandbox purchase before injecting the helper's per-test
    defaults into its license gate. The original free-to-Plus assertions remain.
- `The release embeds the public half of its retained updater signing key.`
  - `scripts/sparkle-public-key.test.mjs`: published RFC 8032 seed/public-key
    vector, malformed/missing inputs, and absence of private material in output.
    All four cases failed before the helper existed and pass afterward.
  - `scripts/release-entitlements.test.mjs`: derived key reaches the archive and
    appcast signing precedes DMG publication; both workflow regressions failed
    before their corrections. All 57 repository script tests pass.
  - A signature from the installed pinned Sparkle `sign_update` binary verifies
    with the derived fixture public key. No production secret was retrieved;
    execution with the retained GitHub secret and the signed artifact is pending.
- `Stripe staging and production are explicitly isolated.`
  - `web/worker/test/purchase-flow.test.ts`: nine guard regressions failed first;
    live/test mismatches, malformed/missing event flags, invalid/missing runtime
    configuration and wrong-mode replay are rejected before KV access. A valid
    live fixture is accepted only with explicit live configuration. All 28 issuer
    tests and TypeScript checks pass locally.
  - `scripts/license-worker.test.mjs`: six rendering regressions failed first;
    required live/test values reach runtime bindings, and missing/invalid or
    hostname-mismatched selections cannot produce a deployment config. All 61
    repository script tests pass. Generated Wrangler bindings include the mode.
  - Provider audit: only the account's shared Test mode environment exists.
    A separate general sandbox provides full settings isolation, but is optional
    for the existing checkout/restore integration. Keep shared settings untouched
    and use test-only payment objects and the staging webhook. The owner
    stopped live Stripe mutations and production purchase-service rollout;
    `Documentation/plus-activation.md` records the two prior live metadata edits.
    Guard source is pushed at `e6fc60c9` with a successful staging Worker Build;
    deployed runtime mode and provider purchase acceptance remain unverified.
  - `web/worker/test/purchase-flow.test.ts`: ten health mode/signer combinations
    failed first and pass with allowlisted `test`/`live` output and sanitized
    `unconfigured` for missing/invalid bindings. Exact response keys, no-store,
    unchanged signer HTTP status and absence of KV/email side effects are covered.
    The diagnostic is local pending review/push; it does not certify payment flow.

## Plus activation deployment integration

- `LicenseActivationTests` covers issuer selection, independent signer trust,
  activation persistence, invalid callbacks, and restoration/renewal races.
- `scripts/license-worker.test.mjs` exercises the approved production domain with
  live payment mode and rejects incompatible host/mode configuration.
- `web/worker/test/deployment.node.mjs` checks generated native configuration,
  restricted recovery email, matching portal, environment-specific rate limits,
  explicit live/test modes, and refusal of production resources in staging.
- `web/worker/test/domain.test.ts` covers deployment identity headers and retired
  hosts; purchase-flow tests cover sanitized signer/mode health and purchase paths.
- `landing/tests/unit/purchase-profile.test.mjs` exercises production, staging,
  and local issuer/scheme pairs and rejects unknown deployment modes.
- Website checks and purchase browser scenarios cover the generated issuer,
  one-click callback, manual fallback, retry, and inbox restoration.
- Signed candidate and actual hosted purchase/restoration remain release checks;
  local mock responses and unsigned compilation cannot satisfy them.

- `scripts/website-artifact.test.mjs` rejects production purchase settings in a
  staging artifact, staging stamps in production publication, and incorrect
  restoration schemes, including retired Studio Dev callbacks on either or both
  staging purchase pages. Website CI runs browser acceptance for both retained modes.
- Recovery-renderer regressions accept the current production portal and reject
  issuer/portal environment mismatches; local profile tests use the native
  development app's staging issuer.
- `scripts/website-deploy.test.mjs` executes each operator command with an inherited
  opposite mode and mismatched page output. Correct builds retain their requested
  mode and package the verified directory despite an inherited asset override;
  mismatches stop before any provider command.
- Deployment configuration tests validate an independent purchase website while
  preserving account/passkey identity and rejecting insecure or cross-environment
  origins. Native Worker configuration and recovery renderer tests both select
  the purchase website and reject the staging account portal as a restore target.
- `DeploymentEndpointTests` checks staging/Studio purchase entry independently
  of account identity and preserves the production destination. Setup command
  tests review the separate checkout website and reject test credentials before
  any provider command using disposable local fixtures.

- Provisioning validation reads Apple’s ApplicationIdentifierPrefix and accepts
  its literal wildcard-string domain authorization
  while the signed app retains its exact account-domain entitlements.
- `scripts/release-entitlements.test.mjs` requires Hardened Runtime in the app
  and widget Release configurations. The signed candidate still requires Apple
  notarization acceptance; build-setting checks do not establish that outcome.
- Signed entitlement comparison resolves only the approved Studio Keychain
  prefix, validates signing-derived identity fields, and rejects added, missing,
  or changed capabilities. Read-only file selection remains explicitly declared;
  the comparison does not discard unexpected permissions to accept an artifact.


### Development app consolidation

| Behavior | Coverage |
| --- | --- |
| Only Curfew and Curfew Dev are built; app/widget IDs and install paths stay distinct | `scripts/dev-consolidation.test.mjs`; signed Debug/Release builds |
| Development preferences, shared history, account and Docket credential services stay in the installed store | `CurfewFlavorTests.derivedValues`; `AppNamespaceTests`; `scripts/dev-consolidation.test.mjs` |
| Canonical and predecessor development identities resolve consistently for embedded helpers | `CurfewFlavorTests`; `AppNamespaceTests.studioIdentityWins` |
| A development app cannot inherit production enforcement priority | `AppNamespaceTests.ownershipSurvivesTheRename`; `DevelopmentDaemonSafetyTests` |
| Signed Dev arms normally, cannot enter demo fixtures, and disarms only in a real test host | `DevelopmentLaunchBehaviorTests`; isolated CI captures exercise unsigned demo fixtures |
| Uninstall targets Curfew Dev and its retained store without removing production or dormant personal-development state | `UninstallCoordinatorTests` |

The installed upgrade additionally requires readback of schedule, history,
account connectivity, authenticated helper readiness, and ordinary update trust.
Do not run lockout/shutdown acceptance or UI suites on the operator desktop.

| Protection discovery and visible background-protection removal | `scripts/protection-settings.test.mjs`; `CurfewUITests.testGeneralKeepsNavigationAndSetupInView`; signed installed Settings review |
| Protection navigation exposes its title through the native text value; demo Connections includes browser controls | `CurfewUITests.testSettingsSidebarSupportsArrowKeys`; `testManageAIAccessAlwaysOpensConnections`; `testTaskBrowserEnforcementPanelActions` on the isolated runner |
| Home leads with the product; footer policies remain keyboard accessible; Plus deep links survive delayed webfonts | `landing/tests/acceptance/site.spec.mjs` in Chromium, Firefox and WebKit |
| Purchase pages use the matching production or canonical Dev activation scheme | `landing/tests/unit/purchase-profile.test.mjs`; staging and production browser acceptance; Astro typecheck and shared TypeScript lint |

| Incremental signed builds refresh embedded helpers/plists; Dev uses its canonical service | `scripts/dev-consolidation.test.mjs`; `DaemonPlistTests`; `AppNamespaceTests`; signed helper reconnect |
