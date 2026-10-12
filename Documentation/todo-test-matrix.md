# Todo Test Matrix

## In-progress event-driven account sync

`CurfewKitTests/AccountStatusPublicationLedgerTests` covers acknowledged unchanged
heartbeats, in-flight coalescing, failed-send retry, failed intermediate states,
late success/failure fencing and every existing enforcement-report field. The
headless package suite passes; this is publication policy evidence, not installed
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
main actor without over-fulfillment exceptions; clean CI RED remains required
before the ordering fix. This draft is not ready to ship.

`NativeAccountSyncTransportTests/testStalePollCannotStartAnOperationAfterDisconnect()`
requires stale reconciliation to return before invoking its operation, independent
of network fixtures. CI RED is pending. CI 38307160113 exposed nil URLProtocol
handlers after teardown; its status-refresh and cadence tests did not pass.

This file maps completed todo items (`[x]`) in `Documentation/todos.md` to automated behavior tests.

Signed-build/manual validation for shutdown, WidgetKit, the privileged helper,
Sparkle, notarization, and related Apple-provisioned release surfaces lives in
`Documentation/RELEASE.md`; this matrix intentionally tracks automated coverage
only. CloudKit and Calendar are dormant in v0.1. Model behavior fixtures use
`makeTestAppModel()` or `LockoutDeadlineStore.ephemeralForTesting()` so unit
tests cannot read or mutate a user's App Group lockout record.

## 0. Foundation and Project Structure

- `Adopt the Studio website and Mintlify standard` (in progress).
  - `landing/tests/unit/site-worker.test.mjs` retains docs/asset/search delegation, path/query/forwarded origin, credential isolation, redirects/errors and HTML-guide mode behavior.
  - `landing/tests/acceptance/site.spec.mjs` retains clean/HTML aliases, direct URL/reload, Back/Forward, keyboard/reduced motion, safe unconfigured license error and 404 behavior.
  - `scripts/landing-contract.test.mjs` retains public account, download and legal-content behavior. Obsolete command-string/source-policy checks, lifecycle declaration tests and release-identity assertions are removed with their implementation.
  - Website CI uses the adopted frozen registry lock, normal Astro build and native Wrangler preview. The temporary registry proposal job and bespoke parity/copier/assembler/lifecycle are removed.
  - Successful main Website and docs runs retain native Astro dist after the existing three-browser checks. Manual staging uses only an exact successful push/main run, verifies main immediately before Wrangler, and requires its distinct staging credential. Static workflow validation is separate from deployment acceptance; no new/manual tests or provider operations are performed for this slice.
  - Shared docs generation and pinned native Mintlify validation remain. The prepared `mcp-guide` source, old public canonical and exact Pages/Worker alias remain; public proxy/source identity acceptance is separate.
  - This source cleanup adds/runs no manual tests. Static lint/type/build and workflow checks are recorded separately; existing hosted behavior suites remain configured.

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
  - `SetupUXTests/completeOnboardingFlowUpdatesState()`
- `Onboarding completion now requires opening live schedule settings and acknowledging permissions guidance before finish.`
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
  - `NativeAccountSyncTransportTests/testRootKeyDistributionFailureCannotBeOverwrittenByAHealthyAccountPoll()`
  - `NativeAccountSyncTransportTests/testFailedStatusPublicationRemainsUnhealthyAfterSuccessfulPolls()`
  - `NativeAccountSyncTransportTests/testOlderStatusSuccessCannotOverwriteTheLatestStatusFailure()`
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

Remote full-suite follow-up: package endpoints now derive app/widget service isolation from their bundle identity when app-only compilation flags cannot propagate into SwiftPM; standalone tools retain their explicit service flag. Setup tests inject Accessibility trust, consent-copy expectations use the approved shorter labels, and the browser uninstall test waits for actual enqueue under loaded CI. A compatibility `landing` symlink preserves the existing Pages root without deployment configuration changes.

Remote capture correction: fully fitting native forms may expose a scrollbar with zero range. Bottom captures now verify the lowest text/control bounds as well as scrollbar position, and accommodate native wheel direction; long clipped panes still fail. The initial remote General capture was visually inspected and shared inline; it is interim evidence until final-head recapture.

Pages verification rejected assets linked outside its configured root, so the compatibility symlink was replaced by the physical `landing/` asset directory. `web/landing/package.json` retains workspace commands and points Wrangler at that root, including its Functions. Deployment settings stay unchanged; script checks verify physical assets and the command target.

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

Remote locks require both a fresh daemon heartbeat and an authenticated ready connection, while Studio Dev still yields to a live higher-priority Curfew owner. Settings refreshes signed status on opening, activation, and the existing heartbeat interval. Pending approval opens the macOS approval pane; installed connection failures route to General; installation is offered only when needed. Account messages describe an unchanged schedule instead of claiming protection is active.

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
