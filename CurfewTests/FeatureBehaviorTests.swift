import AppKit
import Foundation
import Testing
@testable import Curfew

@MainActor
struct WarningNotificationManagerTests {
    @Test("T-30 and T-15 notifications include snooze category without sound")
    func earlyWarningPayload() throws {
        let thirty = try #require(WarningNotificationManager.payload(for: .thirtyMinutes))
        let fifteen = try #require(WarningNotificationManager.payload(for: .fifteenMinutes))

        #expect(thirty.categoryIdentifier == WarningNotificationManager.warningSnoozeCategoryIdentifier)
        #expect(fifteen.categoryIdentifier == WarningNotificationManager.warningSnoozeCategoryIdentifier)
        #expect(!thirty.playsSound)
        #expect(!fifteen.playsSound)
    }

    @Test("Final warning notifications use standard category with sound")
    func finalWarningPayload() throws {
        let five = try #require(WarningNotificationManager.payload(for: .fiveMinutes))
        let two = try #require(WarningNotificationManager.payload(for: .twoMinutes))
        let one = try #require(WarningNotificationManager.payload(for: .oneMinute))

        #expect(five.categoryIdentifier == WarningNotificationManager.warningCategoryIdentifier)
        #expect(two.categoryIdentifier == WarningNotificationManager.warningCategoryIdentifier)
        #expect(one.categoryIdentifier == WarningNotificationManager.warningCategoryIdentifier)
        #expect(five.playsSound)
        #expect(two.playsSound)
        #expect(one.playsSound)
    }

    @Test("Notification category definitions expose snooze action only in snooze category")
    func categoryDefinitions() {
        let definitions = WarningNotificationManager.categoryDefinitions()
        let byIdentifier = Dictionary(uniqueKeysWithValues: definitions.map { ($0.identifier, $0) })

        let snoozeDefinition = byIdentifier[WarningNotificationManager.warningSnoozeCategoryIdentifier]
        let warningDefinition = byIdentifier[WarningNotificationManager.warningCategoryIdentifier]

        #expect(snoozeDefinition?.actionIdentifiers == [WarningNotificationManager.snoozeActionIdentifier])
        #expect(warningDefinition?.actionIdentifiers == [])
    }
}

@MainActor
struct OverlayWindowConfigurationTests {
    @Test("Warning overlay windows are floating and click-through")
    func warningWindowConfiguration() {
        let configuration = OverlayCoordinator.warningWindowConfiguration
        #expect(configuration.styleMask == NSWindow.StyleMask.borderless)
        #expect(configuration.level == NSWindow.Level.floating)
        #expect(configuration.ignoresMouseEvents)
        #expect(configuration.collectionBehavior.contains(NSWindow.CollectionBehavior.canJoinAllSpaces))
        #expect(configuration.collectionBehavior.contains(NSWindow.CollectionBehavior.fullScreenAuxiliary))
        #expect(configuration.collectionBehavior.contains(NSWindow.CollectionBehavior.stationary))
    }

    @Test("Lockout windows are screenSaver-level and capture input")
    func lockoutWindowConfiguration() {
        let configuration = OverlayCoordinator.lockoutWindowConfiguration
        #expect(configuration.styleMask == NSWindow.StyleMask.borderless)
        #expect(configuration.level == NSWindow.Level.screenSaver)
        #expect(!configuration.ignoresMouseEvents)
        #expect(configuration.collectionBehavior.contains(NSWindow.CollectionBehavior.canJoinAllSpaces))
        #expect(configuration.collectionBehavior.contains(NSWindow.CollectionBehavior.fullScreenAuxiliary))
        #expect(configuration.collectionBehavior.contains(NSWindow.CollectionBehavior.stationary))
        #expect(!configuration.isMovable)
    }

    @Test("Floating timer windows stay above standard app content")
    func timerWindowConfiguration() {
        let configuration = OverlayCoordinator.timerWindowConfiguration
        #expect(configuration.styleMask == NSWindow.StyleMask.borderless)
        #expect(configuration.level == NSWindow.Level.statusBar)
        #expect(configuration.ignoresMouseEvents)
    }
}

struct EncouragementMessageRotationTests {
    @Test("Encouragement messages rotate through all entries and wrap")
    func messageRotationWraps() {
        let first = EncouragementMessageCatalog.next(after: nil)
        let second = EncouragementMessageCatalog.next(after: first)
        let third = EncouragementMessageCatalog.next(after: second)
        let fourth = EncouragementMessageCatalog.next(after: third)
        let fifth = EncouragementMessageCatalog.next(after: fourth)
        let wrapped = EncouragementMessageCatalog.next(after: fifth)

        #expect(first != second)
        #expect(second != third)
        #expect(third != fourth)
        #expect(fourth != fifth)
        #expect(wrapped == first)
    }
}

struct AutoShutdownConfigurationTests {
    @Test("Default auto-shutdown delay is 10 minutes")
    func defaultAutoShutdownDelay() {
        #expect(CurfewSettings.default.autoShutdownDelayMinutes == 10)
    }

    @Test("Shutdown countdown status line appears while waiting")
    func shutdownCountdownStatusLine() {
        var workflow = ShutdownWorkflow()
        let spy = ShutdownControllerSpy(results: [])
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 10,
            controller: spy
        )

        let status = workflow.statusLine(now: now)
        #expect(status?.contains("10:00") == true)
    }

    @Test("Shutdown delay clamps to one minute minimum")
    func shutdownDelayMinimumClamp() {
        var workflow = ShutdownWorkflow()
        let spy = ShutdownControllerSpy(results: [])
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        workflow.update(
            now: now,
            isLocked: true,
            isEnabled: true,
            delayMinutes: 0,
            controller: spy
        )

        let status = workflow.statusLine(now: now)
        #expect(status?.contains("1:00") == true)
    }
}

private final class ShutdownControllerSpy: ShutdownControlling {
    private var results: [Bool]

    init(results: [Bool]) {
        self.results = results
    }

    func requestGracefulTermination() {}

    func executeShutdown() -> Bool {
        guard !results.isEmpty else {
            return false
        }
        return results.removeFirst()
    }
}

struct WarningIntervalsPersistenceTests {
    @Test("Warning intervals are normalized and persisted")
    func warningIntervalsPersistNormalized() {
        let suiteName = "CurfewSettingsStoreTests.WarningIntervals.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.warningIntervals = WarningIntervals(
            thirtyMinutes: 10,
            fifteenMinutes: 9,
            fiveMinutes: 8,
            twoMinutes: 7,
            oneMinute: 6
        )
        store.save(settings)

        let loaded = store.load()
        #expect(loaded.warningIntervals == settings.warningIntervals.normalized)
    }
}

struct OverrideRequestPolicyTests {
    @Test("Override policy requires cooldown completion and 50+ chars")
    func overridePolicyValidation() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cooldownEnd = OverrideRequestPolicy.cooldownEnd(startedAt: now)
        let validReason = String(repeating: "a", count: OverrideRequestPolicy.minimumJustificationCharacters)

        #expect(!OverrideRequestPolicy.canConfirm(reason: "short", now: now, cooldownEndsAt: nil, overridesRemaining: 1))
        #expect(!OverrideRequestPolicy.canConfirm(reason: validReason, now: now, cooldownEndsAt: cooldownEnd, overridesRemaining: 1))
        #expect(OverrideRequestPolicy.canConfirm(reason: validReason, now: cooldownEnd, cooldownEndsAt: cooldownEnd, overridesRemaining: 1))
        #expect(!OverrideRequestPolicy.canConfirm(reason: validReason, now: cooldownEnd, cooldownEndsAt: cooldownEnd, overridesRemaining: 0))
    }

    @Test("Override defaults align with product settings")
    func overrideDefaults() {
        #expect(CurfewSettings.default.overrideWeeklyLimit == 2)
        #expect(CurfewSettings.default.overrideDurationMinutes == OverrideRequestPolicy.defaultOverrideDurationMinutes)
        #expect(CurfewSettings.default.extensionWeeklyLimit == 3)
        #expect(CurfewSettings.default.extensionDurationMinutes == 15)
    }
}

struct OverrideWindowBehaviorTests {
    @Test("Override grants temporary access, then re-locks after expiration")
    func relocksAfterOverrideEnds() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let engine = CurfewEnforcementEngine(calendar: calendar)

        let overrideUntil = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 18, minute: 35))
        )
        let duringOverride = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 18, minute: 5))
        )
        let afterOverride = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 18, minute: 36))
        )

        let duringState = engine.evaluate(
            at: duringOverride,
            schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0,
            overrideUntil: overrideUntil
        )
        let afterState = engine.evaluate(
            at: afterOverride,
            schedule: .standardNineToFive,
            extensionMinutesGrantedToday: 0,
            overrideUntil: overrideUntil
        )

        #expect(duringState.phase == .working)
        #expect(afterState.phase == .locked)
    }
}

struct ExtensionResetConfigurationTests {
    @Test("Default extension reset weekday is Monday")
    func defaultResetWeekdayIsMonday() {
        #expect(CurfewSettings.default.resetWeekday == .monday)
    }

    @Test("Extension budget resets at configured weekday boundary")
    func extensionBudgetResetsOnBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))

        let tracker = ExtensionBudgetTracker(
            weeklyLimit: 1,
            extensionMinutes: 15,
            resetWeekday: .monday,
            calendar: calendar
        )

        let sunday = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 1, hour: 12, minute: 0))
        )
        let monday = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 2, day: 2, hour: 12, minute: 0))
        )

        #expect(tracker.requestExtension(at: sunday))
        #expect(tracker.remaining == 0)
        tracker.resetIfNeeded(at: monday)
        #expect(tracker.remaining == 1)
    }
}

@MainActor
struct ExtensionActivationInteractionTests {
    @Test("Tapping extension action alone does not consume budget")
    func tapDoesNotConsumeBudget() {
        let model = CurfewAppModel()
        model.currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        model.state = CurfewEvaluation(
            phase: .warning,
            warningStage: .fifteenMinutes,
            minutesRemaining: 15,
            canRequestExtension: true,
            lockDate: nil,
            unlockDate: nil
        )

        let before = model.extensionsRemaining
        model.tapExtensionRequest()

        #expect(model.extensionsRemaining == before)
    }

    @Test("Hold-confirm extension action consumes budget")
    func holdConfirmConsumesBudget() {
        let model = CurfewAppModel()
        model.currentTime = Date()
        model.state = CurfewEvaluation(
            phase: .warning,
            warningStage: .fifteenMinutes,
            minutesRemaining: 15,
            canRequestExtension: true,
            lockDate: nil,
            unlockDate: nil
        )

        let before = model.extensionsRemaining
        model.confirmExtensionRequest()

        #expect(model.extensionsRemaining == max(0, before - 1))
    }
}

struct OverrideEventStoreTests {
    @Test("Override events append and reload from settings store")
    func overrideEventsPersist() {
        let suiteName = "CurfewSettingsStoreTests.OverrideEvents.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CurfewSettingsStore(defaults: defaults)
        let event = OverrideEvent(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            deviceName: "Test Device",
            reason: "This is a deliberate override reason with sufficient detail.",
            grantedDurationMinutes: 30
        )
        store.appendOverrideEvent(event)

        let loaded = store.loadOverrideEvents()
        #expect(loaded == [event])
    }
}

@MainActor
struct OverrideEventLoggingTests {
    @Test("Confirming override logs timestamp, device, reason, and duration")
    func confirmOverrideLogsEvent() {
        let suiteName = "CurfewSettingsStoreTests.OverrideLogging.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CurfewSettingsStore(defaults: defaults)
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: GettingStartedPresenterSpy()
        )

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reason = String(repeating: "r", count: OverrideRequestPolicy.minimumJustificationCharacters)

        model.currentTime = now
        model.state = CurfewEvaluation(
            phase: .locked,
            warningStage: .lockout,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        model.overridesRemaining = 1
        model.overrideCooldownEndsAt = now.addingTimeInterval(-1)
        model.overrideReasonDraft = reason

        model.confirmOverride()

        let event = try? #require(model.overrideEvents.last)
        #expect(event != nil)
        #expect(event?.timestamp == now)
        #expect(event?.reason == reason)
        #expect(event?.grantedDurationMinutes == model.settings.overrideDurationMinutes)
        #expect(!(event?.deviceName.isEmpty ?? true))
        #expect(store.loadOverrideEvents().count == 1)
    }
}

struct AppConfigurationTests {
    @Test("Host app disables LSUIElement so it launches as a normal app window")
    func hostAppIsWindowed() throws {
        let appBundle = try #require(Bundle.allBundles.first(where: { $0.bundleIdentifier == "studio.hypertext.Curfew" }))
        let value = appBundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool
        #expect(value == false)
    }
}

struct LaunchBehaviorTests {
    @Test("Debug launches keep enforcement disarmed unless explicitly enabled")
    func debugLaunchDefaultsToSafeMode() {
        #expect(!CurfewLaunchBehavior.shouldStartEnforcement(environment: [:], isDebugBuild: true))
        #expect(
            CurfewLaunchBehavior.shouldStartEnforcement(
                environment: ["CURFEW_ENABLE_ENFORCEMENT": "1"],
                isDebugBuild: true
            )
        )
        #expect(
            !CurfewLaunchBehavior.shouldStartEnforcement(
                environment: ["CURFEW_SKIP_ENFORCEMENT": "1"],
                isDebugBuild: true
            )
        )
    }

    @Test("Release launches arm enforcement unless explicitly skipped")
    func releaseLaunchStartsByDefault() {
        #expect(CurfewLaunchBehavior.shouldStartEnforcement(environment: [:], isDebugBuild: false))
        #expect(
            !CurfewLaunchBehavior.shouldStartEnforcement(
                environment: ["CURFEW_SKIP_ENFORCEMENT": "1"],
                isDebugBuild: false
            )
        )
    }
}

struct FeatureFlagTests {
    @Test("Deferred modules remain disabled by default")
    func defaultsAreOff() {
        let flags = FeatureFlags.default
        #expect(!flags.widgetKitEnabled)
        #expect(!flags.cloudSyncEnabled)
        #expect(!flags.mcpServerEnabled)
        #expect(!flags.privilegedHelperEnabled)
    }
}

@MainActor
struct AppCoordinatorTests {
    @Test("Coordinator starts enforcement when launch policy allows and setup is complete")
    func startsEnforcement() {
        let suiteName = "CurfewSettingsStoreTests.AppCoordinator.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        store.save(settings)

        let presenter = GettingStartedPresenterSpy()
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: presenter
        )

        let coordinator = AppCoordinator()
        coordinator.handleInitialLaunch(
            model: model,
            shouldStartEnforcement: true
        )

        #expect(model.isEnforcementRunning)
        #expect(presenter.presentCallCount == 1)
    }

    @Test("Coordinator keeps enforcement disarmed when launch policy disables start")
    func doesNotStartWhenDisallowed() {
        let suiteName = "CurfewSettingsStoreTests.AppCoordinator.NoStart.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        store.save(settings)

        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: GettingStartedPresenterSpy()
        )

        let coordinator = AppCoordinator()
        coordinator.handleInitialLaunch(
            model: model,
            shouldStartEnforcement: false
        )

        #expect(!model.isEnforcementRunning)
    }
}

@MainActor
struct EnforcementSnapshotTests {
    @Test("Snapshot reflects warning-phase state and extension copy")
    func warningSnapshot() {
        let model = CurfewAppModel()

        model.state = CurfewEvaluation(
            phase: .warning,
            warningStage: .fifteenMinutes,
            minutesRemaining: 15,
            canRequestExtension: true,
            lockDate: Date(timeIntervalSince1970: 1_700_000_000),
            unlockDate: Date(timeIntervalSince1970: 1_700_003_600)
        )
        model.extensionsRemaining = 2
        model.settings.extensionDurationMinutes = 20

        let snapshot = model.snapshot

        #expect(snapshot.phase == .warning)
        #expect(snapshot.symbolName == "exclamationmark.triangle")
        #expect(snapshot.statusLine == "Wrap up time")
        #expect(snapshot.timeRemainingText == "0:15")
        #expect(snapshot.canRequestExtension)
        #expect(snapshot.extensionsRemaining == 2)
        #expect(snapshot.extensionRequestTitle == "Hold 2s for +20m extension")
        #expect(snapshot.scheduleWindowText.contains("->"))
    }

    @Test("Snapshot shows idle messaging when no schedule window is active")
    func dayOffSnapshot() {
        let model = CurfewAppModel()

        model.state = CurfewEvaluation(
            phase: .dayOff,
            warningStage: .none,
            minutesRemaining: .max,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )

        let snapshot = model.snapshot

        #expect(snapshot.phase == .dayOff)
        #expect(snapshot.symbolName == "moon.zzz")
        #expect(snapshot.timeRemainingText == "—")
        #expect(snapshot.scheduleWindowText == "No enforcement window is active today.")
        #expect(!snapshot.canRequestExtension)
    }
}

struct MainWorkspaceSectionTests {
    @Test("Main workspace navigation includes overview, configuration, and onboarding")
    func sectionSet() {
        #expect(MainWorkspaceSection.allCases == [.overview, .configuration, .onboarding])
    }
}

struct SettingsSectionTests {
    @Test("Settings sections include schedule, enforcement, integrations, devices, and advanced")
    func sectionSet() {
        #expect(
            SettingsSection.allCases == [
                .schedule,
                .enforcement,
                .integrations,
                .devices,
                .advanced
            ]
        )
    }
}

struct FirstRunFlowTests {
    @Test("First-run flow contains required setup steps")
    func requiredSteps() {
        #expect(
            FirstRunStep.allCases == [
                .welcome,
                .schedule,
                .extensionBudget,
                .permissions,
                .confirmation
            ]
        )
    }

    @Test("First-run flow advances and retreats within bounds")
    func navigationBounds() {
        var flow = FirstRunFlow()
        #expect(flow.currentStep == .welcome)

        flow.retreat()
        #expect(flow.currentStep == .welcome)

        flow.advance()
        #expect(flow.currentStep == .schedule)
        flow.advance()
        #expect(flow.currentStep == .extensionBudget)
        flow.advance()
        #expect(flow.currentStep == .permissions)
        flow.advance()
        #expect(flow.currentStep == .confirmation)

        flow.advance()
        #expect(flow.currentStep == .confirmation)
    }
}

struct GettingStartedCopyTests {
    @Test("Getting started copy reinforces commitment and enforcement model")
    func warmCommitmentCopy() {
        let message = GettingStartedCopy.commitmentMessage.lowercased()
        #expect(message.contains("thinking clearly"))
        #expect(message.contains("enforce"))
    }
}

@MainActor
struct SetupUXTests {
    @Test("Open settings action activates app and opens Settings window route")
    func openSettingsActionRoutesThroughRouter() {
        let router = AppRouterSpy()
        let model = CurfewAppModel(
            appRouter: router,
            gettingStartedPresenter: GettingStartedPresenterSpy()
        )

        model.openSettings()

        #expect(router.activateCallCount == 1)
        #expect(router.showSettingsCallCount == 1)
    }

    @Test("Getting Started action presents onboarding window route")
    func gettingStartedActionRoutesThroughPresenter() {
        let presenter = GettingStartedPresenterSpy()
        let model = CurfewAppModel(
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: presenter
        )

        model.showGettingStarted()

        #expect(presenter.presentCallCount == 1)
    }

    @Test("Completing onboarding marks setup complete and dismisses onboarding")
    func completeOnboardingFlowUpdatesState() {
        let suiteName = "CurfewSettingsStoreTests.OnboardingComplete.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let presenter = GettingStartedPresenterSpy()
        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            gettingStartedPresenter: presenter
        )

        #expect(!model.settings.hasCompletedInitialSetup)
        model.completeOnboardingFlow()
        #expect(model.settings.hasCompletedInitialSetup)
        #expect(presenter.dismissCallCount == 1)
    }
}

@MainActor
struct OverrideComposerStateTests {
    @Test("Override composer does not auto-open outside lockout")
    func composerStaysHiddenWhenNotLocked() {
        let model = CurfewAppModel()
        let now = Date()

        model.currentTime = now
        model.overridesRemaining = 1
        model.overrideCooldownEndsAt = now.addingTimeInterval(-1)
        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 20,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )

        model.reconcileOverrideComposerState(previousPhase: .working)
        #expect(!model.isOverrideComposerVisible)
    }

    @Test("Override cooldown and composer state reset after leaving lockout")
    func composerStateResetsWhenLockoutEnds() {
        let model = CurfewAppModel()
        let now = Date()

        model.currentTime = now
        model.overridesRemaining = 1
        model.overrideCooldownEndsAt = now.addingTimeInterval(-1)
        model.overrideReasonDraft = String(repeating: "x", count: 60)
        model.isOverrideComposerVisible = true
        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 20,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )

        model.reconcileOverrideComposerState(previousPhase: .locked)

        #expect(model.overrideCooldownEndsAt == nil)
        #expect(!model.isOverrideComposerVisible)
        #expect(model.overrideReasonDraft.isEmpty)
    }
}

@MainActor
private final class AppRouterSpy: AppRouting {
    private(set) var activateCallCount = 0
    private(set) var showSettingsCallCount = 0

    func activate() {
        activateCallCount += 1
    }

    func showSettings() {
        showSettingsCallCount += 1
    }
}

@MainActor
private final class GettingStartedPresenterSpy: GettingStartedPresenting {
    private(set) var presentCallCount = 0
    private(set) var dismissCallCount = 0

    func present(model: CurfewAppModel) {
        presentCallCount += 1
    }

    func dismiss() {
        dismissCallCount += 1
    }
}

@MainActor
struct MenuBarPresentationModelTests {
    @Test("Menu bar symbol and status line reflect enforcement phase")
    func symbolAndStatusForPhase() {
        let model = CurfewAppModel()

        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 90,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.menuBarSymbolName == "clock.badge.checkmark")
        #expect(model.statusLine == "Working window active")

        model.state = CurfewEvaluation(
            phase: .warning,
            warningStage: .fifteenMinutes,
            minutesRemaining: 15,
            canRequestExtension: true,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.menuBarSymbolName == "exclamationmark.triangle")
        #expect(model.statusLine == "Wrap up time")

        model.state = CurfewEvaluation(
            phase: .locked,
            warningStage: .lockout,
            minutesRemaining: 0,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.menuBarSymbolName == "lock.fill")
        #expect(model.statusLine == "Curfew lockout active")

        model.state = CurfewEvaluation(
            phase: .dayOff,
            warningStage: .none,
            minutesRemaining: .max,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.menuBarSymbolName == "moon.zzz")
        #expect(model.statusLine == "Day off")
    }

    @Test("Menu bar countdown uses h:mm formatting and day-off placeholder")
    func timeRemainingTextFormatting() {
        let model = CurfewAppModel()

        model.state = CurfewEvaluation(
            phase: .working,
            warningStage: .none,
            minutesRemaining: 125,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.timeRemainingText == "2:05")

        model.state = CurfewEvaluation(
            phase: .dayOff,
            warningStage: .none,
            minutesRemaining: .max,
            canRequestExtension: false,
            lockDate: nil,
            unlockDate: nil
        )
        #expect(model.timeRemainingText == "—")
    }
}
