@testable import Curfew
@testable import CurfewKit
import Foundation
import ServiceManagement
import Testing

@MainActor
private final class NotificationRequestSpy: WarningNotificationManaging {
    var onSnoozeRequested: (() -> Void)?
    var voice = VoicePack.standard
    private(set) var permissionRequests = 0

    func requestPermissionIfNeeded() {
        permissionRequests += 1
    }

    func update(stage _: WarningStage, now _: Date, alreadyFiredElsewhere _: Set<String>) {}
    func deliverDistractionNudge() {}
}

@MainActor
enum SetupModelFactory {
    static func store(_ configure: (inout CurfewSettings) -> Void = { _ in
    }) -> CurfewSettingsStore {
        let defaults = UserDefaults(suiteName: "GettingStartedModelTests.\(UUID().uuidString)")
            ?? .standard
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        configure(&settings)
        store.save(settings)
        return store
    }

    static func model(
        store: CurfewSettingsStore? = nil,
        trusted: Bool = false,
        flags: FeatureFlags? = nil,
        helper: PrivilegedHelperManager? = nil,
        notifications: (any WarningNotificationManaging)? = nil,
        activity: (any ActivityRecording)? = nil,
        deadlines: LockoutDeadlineStore? = nil,
        router: AppRouterSpy? = nil,
        trust: FakeAccessibilityAuthorization? = nil
    ) -> CurfewAppModel {
        CurfewAppModel(
            settingsStore: store ?? SetupModelFactory.store(),
            appRouter: router ?? AppRouterSpy(),
            flavor: .production,
            featureFlags: flags,
            activityRecorder: activity ?? NullActivityRecording(),
            notificationManager: notifications,
            privilegedHelperManager: helper,
            lockoutDeadlineStore: deadlines ?? .ephemeralForTesting(),
            accessibilityAuthorization: trust ?? FakeAccessibilityAuthorization(trusted: trusted)
        )
    }

    static func absentHelper() -> PrivilegedHelperManager {
        let helper = PrivilegedHelperManager(
            daemonService: StubAppService(status: .notRegistered),
            loginItemService: StubAppService(status: .notRegistered),
            daemonRPC: StubDaemonRPC(statusResult: .failure(StubServiceError.registerFailed))
        )
        helper.refreshStatus()
        return helper
    }

    static func installedHelper() -> PrivilegedHelperManager {
        let helper = PrivilegedHelperManager(
            daemonService: StubAppService(status: .enabled),
            loginItemService: StubAppService(status: .notRegistered),
            daemonRPC: StubDaemonRPC(statusResult: .failure(StubServiceError.registerFailed))
        )
        helper.refreshStatus()
        return helper
    }
}

@MainActor
struct SetupHealthTests {
    @Test("No health warning shows anywhere before setup completes")
    func warningsHiddenBeforeSetup() {
        let model = SetupModelFactory.model(trusted: false)

        #expect(model.enforcementHealth == .degradedNoAccessibility)
        #expect(model.presentedEnforcementHealth == .active)
        #expect(model.menuBarSymbolName != EnforcementHealth.degradedBadgeSymbol)
        #expect(!model.showsHealthWarnings)
    }

    @Test("Health warnings return once setup has completed")
    func warningsShowAfterSetup() {
        let store = SetupModelFactory.store { $0.hasCompletedInitialSetup = true }
        let model = SetupModelFactory.model(store: store, trusted: false)

        #expect(model.presentedEnforcementHealth == .degradedNoAccessibility)
        #expect(model.menuBarSymbolName == EnforcementHealth.degradedBadgeSymbol)
        #expect(model.showsHealthWarnings)
    }

    @Test("Every health surface reads the gated health, not the raw verdict")
    func surfacesUseGatedHealth() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let surfaces = [
            "Curfew/ContentView.swift",
            "Curfew/CurfewApp.swift",
            "Curfew/UI/SettingsView+EnforcementPanels.swift"
        ]
        for path in surfaces {
            let source = try String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
            #expect(!source.contains("model.enforcementHealth"), "\(path) shows raw health")
            #expect(source.contains("model.presentedEnforcementHealth"), "\(path)")
        }
        let today = try String(
            contentsOf: root.appendingPathComponent("Curfew/UI/Destinations/TodayView.swift"),
            encoding: .utf8
        )
        #expect(!today.contains("showAccessibilityWarning: !model.isAccessibilityTrusted"))
        #expect(today.contains("model.showsHealthWarnings"))
    }

    @Test("A fresh install that finished setup without the helper is healthy")
    func absentHelperIsHealthy() {
        // No locking day, so the result does not depend on the time the test runs.
        let store = SetupModelFactory.store {
            $0.hasCompletedInitialSetup = true
            $0.schedule = .allDaysOff
        }
        let model = SetupModelFactory.model(
            store: store,
            trusted: true,
            flags: .shippingV1,
            helper: SetupModelFactory.absentHelper()
        )
        model.refreshAccessibilityTrust()

        #expect(model.privilegedHelperManager.enforcementAvailability == .notRequired)
        #expect(model.enforcementHealth == .active)
        #expect(model.presentedEnforcementHealth == .active)
        #expect(model.helperAbsenceNote == GettingStartedCopy.helperAbsentNote)
    }

    @Test("A helper that was installed and then broke is still reported")
    func brokenHelperIsStillDetected() {
        // No locking day, so the result does not depend on the time the test runs.
        let store = SetupModelFactory.store {
            $0.hasCompletedInitialSetup = true
            $0.schedule = .allDaysOff
        }
        let model = SetupModelFactory.model(
            store: store,
            trusted: true,
            flags: .shippingV1,
            helper: SetupModelFactory.installedHelper()
        )
        model.refreshAccessibilityTrust()

        #expect(model.privilegedHelperManager.enforcementAvailability == .unavailable)
        #expect(model.enforcementHealth == .degradedHelperUnavailable)
        #expect(model.presentedEnforcementHealth == .degradedHelperUnavailable)
        #expect(model.helperAbsenceNote == nil)
    }

    @Test("A failed helper install the person asked for is still reported")
    func failedInstallIsReported() {
        let helper = PrivilegedHelperManager(
            daemonService: StubAppService(
                status: .notRegistered,
                registerResult: .failure(StubServiceError.registerFailed)
            ),
            loginItemService: StubAppService(status: .notRegistered),
            daemonRPC: StubDaemonRPC(statusResult: .failure(StubServiceError.registerFailed))
        )
        helper.installDaemon()
        #expect(helper.enforcementAvailability == .registrationFailed)
    }

    @Test("Builds without the helper never mention it")
    func noHelperNoteWithoutHelperFeature() {
        let model = SetupModelFactory.model(trusted: true, flags: .default)
        #expect(model.helperAbsenceNote == nil)
    }
}

@MainActor
struct SetupPromptTimingTests {
    @Test("Arming after setup never asks for notifications on its own")
    func startDoesNotRequestNotifications() {
        let spy = NotificationRequestSpy()
        let store = SetupModelFactory.store { $0.hasCompletedInitialSetup = true }
        let model = SetupModelFactory.model(store: store, trusted: true, notifications: spy)

        model.start()

        #expect(model.started)
        #expect(spy.permissionRequests == 0)
    }

    @Test("Opening the Accessibility pane for setup does not fire the system prompt")
    func paneOpensWithoutPrompt() {
        let trust = FakeAccessibilityAuthorization(trusted: false)
        let model = SetupModelFactory.model(trust: trust)

        model.openAccessibilityPaneForSetup()

        #expect(trust.openSettingsCallCount == 1)
        #expect(trust.promptForTrustCallCount == 0)
    }
}

@MainActor
struct SetupReturnTests {
    @Test("Setup opens on every launch until it is completed")
    func reopensUntilCompleted() {
        let store = SetupModelFactory.store()
        #expect(SetupModelFactory.model(store: store).shouldOpenSettingsOnLaunch)
        #expect(SetupModelFactory.model(store: store).shouldOpenSettingsOnLaunch)

        let done = SetupModelFactory.store { $0.hasCompletedInitialSetup = true }
        #expect(!SetupModelFactory.model(store: done).shouldOpenSettingsOnLaunch)
    }

    @Test("Setup reopens at the step the person reached")
    func resumesAtStep() {
        let store = SetupModelFactory.store()
        var flow = FirstRunFlow()
        flow.chooseSchedule(.weeklySchedule)
        SetupModelFactory.model(store: store).saveSetupProgress(flow)

        let reopened = SetupModelFactory.model(store: store).loadSetupFlow()

        #expect(reopened.currentStep == .permissions)
        #expect(reopened.scheduleChoice == .weeklySchedule)
    }

    @Test("A finished setup reopens as a summary, not the walkthrough")
    func finishedSetupReopensAsSummary() {
        let store = SetupModelFactory.store { $0.hasCompletedInitialSetup = true }
        let flow = SetupModelFactory.model(store: store, trusted: true).loadSetupFlow()
        #expect(flow.currentStep == .ready)
        #expect(flow.isReview)
    }

    @Test("The setup window opens at the size its content needs")
    func windowSizeMatchesContent() {
        #expect(GettingStartedLayout.windowSize.width >= GettingStartedLayout.contentMinimum.width)
        #expect(GettingStartedLayout.windowSize.height >= GettingStartedLayout.contentMinimum
            .height)
    }

    @Test("While setup is pending the main window waits instead of opening beside it")
    func mainWindowWaitsForSetup() {
        #expect(CurfewLaunchBehavior.mainWindowLaunchBehavior(
            suppressesOrdinaryWindows: false, setupPending: true
        ) == .suppressed)
        #expect(CurfewLaunchBehavior.mainWindowLaunchBehavior(
            suppressesOrdinaryWindows: false, setupPending: false
        ) == .presented)
        #expect(CurfewLaunchBehavior.mainWindowLaunchBehavior(
            suppressesOrdinaryWindows: true, setupPending: false
        ) == .suppressed)
    }

    @Test("Finishing setup closes it and opens Today")
    func finishOpensToday() {
        let router = AppRouterSpy()
        let model = SetupModelFactory.model(router: router)
        model.finishGettingStarted()
        #expect(router.dismissedWindows == [CurfewAppModel.gettingStartedWindowID])
        #expect(router.openedWindows == [MainWorkspaceSection.windowID])
    }
}

@MainActor
struct SetupScheduleTests {
    @Test("Step 1 is prefilled from the current schedule")
    func prefill() {
        let store = SetupModelFactory.store {
            $0
                .schedule =
                WeeklySchedule(rules: Dictionary(uniqueKeysWithValues: Weekday.allCases.map {
                    ($0, DayRule(
                        isDayOff: $0 == .saturday || $0 == .sunday,
                        lockMinutes: 17 * 60 + 30,
                        unlockMinutes: 8 * 60
                    ))
                }))
        }
        let draft = SetupModelFactory.model(store: store).setupScheduleDraft

        #expect(draft.lockMinutes == 17 * 60 + 30)
        #expect(draft.unlockMinutes == 8 * 60)
        #expect(draft.workingDays == [.monday, .tuesday, .wednesday, .thursday, .friday])
    }

    @Test("Applying step 1 writes the times and days through the schedule path")
    func applyDraft() {
        let model = SetupModelFactory.model()
        let draft = SetupScheduleDraft(
            lockMinutes: 19 * 60,
            unlockMinutes: 6 * 60 + 30,
            workingDays: [.monday, .wednesday]
        )

        model.applySetupSchedule(draft)

        let monday = model.settings.schedule.rule(for: .monday)
        let tuesday = model.settings.schedule.rule(for: .tuesday)
        #expect(!monday.isDayOff)
        #expect(monday.lockMinutes == 19 * 60)
        #expect(monday.unlockMinutes == 6 * 60 + 30)
        #expect(tuesday.isDayOff)
        #expect(tuesday.lockMinutes == 19 * 60)
        #expect(model.settings.pendingScheduleChange == nil)
        #expect(!model.automaticScheduleEnabled)
    }

    @Test("Tonight's curfew comes from the saved schedule")
    func nextCurfew() throws {
        let calendar = Calendar.current
        let store = SetupModelFactory.store {
            $0
                .schedule =
                WeeklySchedule(rules: Dictionary(uniqueKeysWithValues: Weekday.allCases.map {
                    ($0, DayRule(isDayOff: false, lockMinutes: 18 * 60, unlockMinutes: 7 * 60))
                }))
        }
        let model = SetupModelFactory.model(store: store)
        let morning = try #require(calendar.date(
            bySettingHour: 9,
            minute: 0,
            second: 0,
            of: Date()
        ))
        let evening = try #require(calendar.date(
            bySettingHour: 18,
            minute: 0,
            second: 0,
            of: morning
        ))

        #expect(model.nextCurfew(after: morning, usesWeeklySchedule: true) == evening)
        #expect(model.nextCurfew(after: morning, usesWeeklySchedule: false) == nil)
        let late = evening.addingTimeInterval(3600)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: evening))
        #expect(model.nextCurfew(after: late, usesWeeklySchedule: true) == tomorrow)
    }
}
