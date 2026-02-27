# Todo Test Matrix

This file maps completed todo items (`[x]`) in `Documentation/todos.md` to automated behavior tests.

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

## 15. Onboarding

- `Show a first-launch getting-started window so users can configure Curfew immediately.`
  - `CurfewTests/initialSetupPromptShownOnlyOnce()`
- `Persist one-time first-launch setup state so Settings only auto-opens once.`
  - `CurfewTests/initialSetupPromptShownOnlyOnce()`
- `Build first-run flow: welcome, schedule, extension budget, permissions, confirmation.`
  - `FirstRunFlowTests/requiredSteps()`
  - `FirstRunFlowTests/navigationBounds()`
  - `SetupUXTests/completeOnboardingFlowUpdatesState()`
- `Allow onboarding relaunch from Settings.`
  - `SetupUXTests/gettingStartedActionRoutesThroughPresenter()`
- `Add warm explanatory copy for commitment model and enforcement behavior.`
  - `GettingStartedCopyTests/warmCommitmentCopy()`
