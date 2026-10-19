@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

struct FirstRunSafetyFlowTests {
    @Test("Opening the schedule editor alone cannot authorize automatic lockout")
    func openingScheduleDoesNotConfirmIt() {
        var flow = FirstRunFlow()
        flow.advance()

        flow.markScheduleReviewed()

        #expect(!flow.canAdvance)
        flow.advance()
        #expect(flow.currentStep == .schedule)
    }

    @Test("Reviewing seven rules and choosing the weekly schedule is one transition")
    func reviewedWeeklyChoiceAdvances() {
        var flow = FirstRunFlow()
        flow.advance()

        flow.chooseReviewedWeeklySchedule()

        #expect(flow.scheduleChoice == .weeklySchedule)
        #expect(flow.canAdvance)
        flow.advance()
        #expect(flow.currentStep == .extensionBudget)
    }

    @Test("Remote-only setup can be explicitly selected without a weekly schedule")
    func remoteOnlyChoiceAdvancesWithoutScheduleReview() {
        var flow = FirstRunFlow()
        flow.advance()

        flow.chooseSchedule(.remoteControlsOnly)

        #expect(flow.canAdvance)
        flow.advance()
        #expect(flow.currentStep == .extensionBudget)
    }
}

@MainActor
struct FirstRunSafetyModelTests {
    @Test("First-run setup cannot silently arm a schedule that already locks")
    func immediateLockNeedsSeparateAcknowledgement() {
        let suiteName = "CurfewSettingsStoreTests.ImmediateSetup.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.schedule = .init(rules: Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map {
                ($0, DayRule(isDayOff: false, lockMinutes: 0, unlockMinutes: 23 * 60 + 59))
            }
        ))
        store.save(settings)
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )

        model.completeInitialSetup(choice: .weeklySchedule)

        #expect(!model.settings.hasCompletedInitialSetup)
        #expect(!model.automaticScheduleEnabled)

        let outcome = model.completeInitialSetup(
            choice: .weeklySchedule,
            confirmedImmediateLock: true
        )
        #expect(outcome == .activated)
        #expect(model.settings.hasCompletedInitialSetup)
        #expect(model.automaticScheduleEnabled)
    }

    @Test("Returning remote-only users cannot silently arm a lock-now schedule")
    func enableNeedsSeparateImmediateLockAcknowledgement() {
        let suiteName = "CurfewSettingsStoreTests.ImmediateEnable.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        settings.schedule = .init(rules: Dictionary(
            uniqueKeysWithValues: Weekday.allCases.map {
                ($0, DayRule(isDayOff: false, lockMinutes: 0, unlockMinutes: 23 * 60 + 59))
            }
        ))
        store.save(settings)
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            flavor: .studioDevelopment,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )

        model.enableAutomaticSchedule()

        #expect(!model.automaticScheduleEnabled)

        let outcome = model.enableAutomaticSchedule(confirmedImmediateLock: true)
        #expect(outcome == .activated)
        #expect(model.automaticScheduleEnabled)
    }

    @Test("Crossing 22:00 between render and click requires a fresh lock-now decision")
    func boundaryIsCheckedAtActivation() throws {
        let suiteName = "CurfewSettingsStoreTests.BoundaryActivation.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
        let calendar = Calendar.current
        let before = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 13, hour: 21, minute: 59
        )))
        let after = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 13, hour: 22
        )))
        let nearlyAtBoundary = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 10, day: 13, hour: 21, minute: 59, second: 59
        )))

        #expect(!model.scheduleWouldLock(at: before))
        #expect(model.scheduleWouldLock(at: after))
        #expect(model.completeInitialSetup(choice: .weeklySchedule, at: after)
            == .requiresImmediateLockConfirmation)
        #expect(model.completeInitialSetup(choice: .weeklySchedule, at: nearlyAtBoundary)
            == .requiresImmediateLockConfirmation)
        #expect(!model.settings.hasCompletedInitialSetup)
    }

    @Test("Completed remote-only installs edit their inactive schedule immediately")
    func remoteOnlyScheduleEditIsImmediate() {
        let suiteName = "CurfewSettingsStoreTests.RemoteOnlyEdit.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        store.save(settings)
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            flavor: .studioDevelopment,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )
        var proposed = model.settings.schedule
        proposed.rules[.monday]?.lockMinutes = 23 * 60

        model.queueScheduleUpdate(proposed)

        #expect(model.settings.schedule == proposed)
        #expect(model.settings.pendingScheduleChange == nil)
    }

    @Test("A confirmed weekly schedule still delays weaker edits")
    func activeScheduleWeakeningStillQueues() {
        let suiteName = "CurfewSettingsStoreTests.ActiveEdit.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        store.save(settings)
        store.saveAutomaticScheduleConsent(true)
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            flavor: .studioDevelopment,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )
        var proposed = model.settings.schedule
        proposed.rules[.monday]?.lockMinutes = 23 * 60

        model.queueScheduleUpdate(proposed)

        #expect(model.settings.schedule != proposed)
        #expect(model.settings.pendingScheduleChange?.proposedSchedule == proposed)
    }

    @Test("Existing production installs retain their configured automatic schedule")
    func completedProductionInstallKeepsSchedule() {
        let suiteName = "CurfewSettingsStoreTests.ProductionConsent.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.schedule = .startupHours
        settings.hasCompletedInitialSetup = true
        store.save(settings)
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            flavor: .production,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )

        #expect(model.automaticScheduleEnabled)
        #expect(model.effectiveSchedule == .startupHours)
        #expect(store.loadAutomaticScheduleConsent() == nil)
    }

    @Test(
        "Remote-only consent preserves existing durable deadlines",
        arguments: [LockoutKind.remoteCommand, .scheduledTime]
    )
    func remoteOnlyPreservesDurableDeadline(kind: LockoutKind) {
        let suiteName = "CurfewSettingsStoreTests.DurableConsent.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        store.save(settings)
        let deadlineStore = LockoutDeadlineStore.ephemeralForTesting()
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            flavor: .studioDevelopment,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: deadlineStore
        )
        let now = Date()
        model.currentTime = now
        deadlineStore.save(LockoutDeadlineRecord(
            lockoutStartedAt: now,
            scheduledUnlockAt: now.addingTimeInterval(300),
            kind: kind
        ))

        model.enforceDurableDeadlineIfActive()

        #expect(model.state.phase == .locked)
        #expect(model.state.unlockDate == deadlineStore.load()?.scheduledUnlockAt)
    }
}

@MainActor
struct DevelopmentScheduleMigrationTests {
    @Test(
        "Completed development installs persist remote-only rollback safety",
        arguments: [CurfewFlavor.development, .studioDevelopment]
    )
    func completedDevelopmentDefaultsToRemoteOnly(flavor: CurfewFlavor) {
        let suiteName = "CurfewSettingsStoreTests.StudioConsent.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = CurfewSettingsStore(defaults: defaults)
        var settings = CurfewSettings.default
        var savedRule = settings.schedule.rule(for: .monday)
        savedRule.lockMinutes = 22 * 60
        savedRule.unlockMinutes = 8 * 60
        settings.schedule.rules[.monday] = savedRule
        settings.hasCompletedInitialSetup = true
        store.save(settings)
        let model = CurfewAppModel(
            settingsStore: store,
            appRouter: AppRouterSpy(),
            flavor: flavor,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )

        #expect(!model.automaticScheduleEnabled)
        #expect(model.effectiveSchedule == .allDaysOff)
        #expect(model.state.phase == .dayOff)
        #expect(model.settings.schedule.rule(for: .monday) == savedRule)
        #expect(!model.hasExplicitAutomaticScheduleConsent)
        #expect(store.loadAutomaticScheduleConsent() == false)

        let relaunchedModel = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            flavor: flavor,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )
        #expect(!relaunchedModel.automaticScheduleEnabled)
        #expect(!relaunchedModel.hasExplicitAutomaticScheduleConsent)

        store.saveAutomaticScheduleConsent(true)
        let optedInModel = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            flavor: flavor,
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )
        #expect(optedInModel.automaticScheduleEnabled)
        #expect(optedInModel.hasExplicitAutomaticScheduleConsent)
    }
}

@MainActor
struct FirstRunScheduleEditTests {
    @Test("First-run schedule edits replace the draft immediately without cooldown")
    func firstRunScheduleEditIsImmediate() {
        let suiteName = "CurfewSettingsStoreTests.InitialSchedule.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            Issue.record("Unable to create isolated UserDefaults suite.")
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let model = CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            activityRecorder: NullActivityRecording(),
            lockoutDeadlineStore: .ephemeralForTesting()
        )
        var proposed = model.settings.schedule
        proposed.rules[.monday]?.lockMinutes = 22 * 60

        model.queueScheduleUpdate(proposed)

        #expect(model.settings.schedule.rule(for: .monday).lockMinutes == 22 * 60)
        #expect(model.settings.pendingScheduleChange == nil)
    }
}
