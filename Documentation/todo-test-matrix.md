# Todo Test Matrix

This file maps completed todo items (`[x]`) in `Documentation/todos.md` to automated behavior tests.

Signed-build/manual validation for shutdown, WidgetKit, the privileged helper,
CloudKit, notarization, and related Apple-provisioned release surfaces lives in
`Documentation/RELEASE.md`; this matrix intentionally tracks automated coverage
only.

## 0. Foundation and Project Structure

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

- `Persist lockout state through the LaunchDaemon sentinel path.`
  - `LockoutStatePersistenceTests/markLockoutActiveCreatesSentinel()`
  - `LockoutStatePersistenceTests/markLockoutInactiveRemovesSentinel()`
  - `LockoutStatePersistenceTests/markLockoutActiveNoopsWithoutParentDirectory()`
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
  - Build verification: `xcodebuild build -project Curfew.xcodeproj -target CurfewWidget -destination 'platform=macOS'`
- `Use the widget extension kind identifier when reloading host-app timelines.`
  - `WidgetIdentityTests/kindMatchesWidgetExtension()`

## 15. Onboarding

- `Show a first-launch getting-started window so users can configure Curfew immediately.`
  - `CurfewTests/initialSetupPromptShownOnlyOnce()`
- `Persist one-time first-launch setup state so Settings only auto-opens once.`
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
  - `AccountEnrollmentRecoveryTests/browserSignInLinkCleanupPreservesNewClipboardContents()`
  - `AccountEnrollmentRecoveryTests/browserSignInLinkClearsBeforeDeviceEnrollment()`
  - `AccountEnrollmentCopyTests/recoveryKeyCanBeCopied()`
  - `AccountEnrollmentCopyTests/recoveryKeyExportUsesOwnerOnlyFilePermissions()`
  - `AccountOAuthEnrollmentTests/callbackStateIsExact()`
  - `AccountOAuthEnrollmentTests/callbackIsClaimedHTTPS()`
  - `AccountOAuthExternalCallbackTests/externalBrowserCallbackRoutesByExactState()`
  - `AccountOAuthExternalCallbackTests/externalBrowserCallbackIsConsumedOnce()`
  - `AccountOAuthExternalCallbackTests/appDelegateForwardsExternalOAuthCallback()`
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
  that enrollment alone means remote control is working or enabled.`
  - `AccountConnectionPresentationTests/statesStayPlainAndAccurate()`
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
  - Manual review of `landing/docs.html` and `docs/mcp.mdx`
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
- `Initial Release enables only the validated local MCP integration; CloudKit, WidgetKit, Calendar, and privileged helper remain disabled.`
  - `FeatureFlagTests/shippingEnablesOnlyValidatedLocalIntegration()`
- `Conservative signed Release does not request CloudKit or APNs before those integrations are enabled.`
  - `scripts/release-entitlements.test.mjs`
- `Only surface update UI when Sparkle is actually linked into the app target.`
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
  when the access-token record is incomplete.`
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
