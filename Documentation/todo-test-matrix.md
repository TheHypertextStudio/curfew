# Todo Test Matrix

This file maps completed todo items (`[x]`) in `Documentation/todos.md` to automated behavior tests.

Signed-build/manual validation for shutdown, WidgetKit, the privileged helper,
CloudKit, notarization, and related Apple-provisioned release surfaces lives in
`Documentation/RELEASE.md`; this matrix intentionally tracks automated coverage
only.

## 0. Foundation and Project Structure

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
  produce and upload the MarketingCapture PNG artifacts.`
  - `scripts/release-entitlements.test.mjs`
  - `scripts/extract-screenshots.sh` (local and hosted runtime coverage)
- `Stripe test-mode staging can use a workers.dev license issuer without
  attaching a production custom domain.`
  - `scripts/license-worker.test.mjs`
- `A Stripe Sandbox checkout can exercise the isolated issuer without a real
  card or production endpoint; webhook delivery and subsequent session-license
  retrieval are recorded as an operator-run staging proof.`
  - `Documentation/license-worker-bootstrap.md` (operator procedure)
  - Stripe Sandbox + isolated `workers.dev` Worker runtime evidence (external)
- `Operator documentation names only the envelope-v2 Worker bootstrap and
  cannot reintroduce a legacy deployment path.`
  - `scripts/license-worker-documentation.test.mjs`
- `Initial-release app surfaces do not offer a hosted checkout until a release
  explicitly provides one.`
  - `PurchaseAvailabilityTests/checkoutIsUnavailable()`

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
