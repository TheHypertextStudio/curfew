@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

/// Once the day's work hours are spent, the lock time is the moment they ran
/// out. It must not follow the clock while the Mac stays locked, across a
/// relaunch or past midnight, because the lock screen's sky, the day record
/// and the Journal all read it as when curfew started.
///
/// Every model here is armed through the same path as the app, with the
/// Curfew helper disabled, overlays suppressed by the test host and a spy
/// keyboard shield, so nothing locks this Mac.
@MainActor
struct HoursModeLockTimeTests {
    private let calendar = Calendar.current

    /// Wednesday 18 November 2026, local time.
    private func at(_ hour: Int, _ minute: Int = 0, second: Int = 0, day: Int = 18) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 11, day: day, hour: hour, minute: minute, second: second
        ))!
    }

    /// A rule whose work hours run out at 10:00, counting from midnight the way
    /// `WorkTimeAggregator` does, well before the 22:00 wall-clock curfew.
    private func rule(_ mode: CurfewMode) -> DayRule {
        DayRule(
            isDayOff: false, lockMinutes: 22 * 60, unlockMinutes: 7 * 60,
            mode: mode, hoursLimitMinutes: 10 * 60
        )
    }

    private struct Fixture {
        let defaults: UserDefaults
        let deadlines: LockoutDeadlineStore
        let activityDirectory: URL
    }

    private func fixture(mode: CurfewMode) throws -> Fixture {
        let defaults = try #require(
            UserDefaults(suiteName: "CurfewHoursLockTime.\(UUID().uuidString)")
        )
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = store.load()
        settings.hasCompletedInitialSetup = true
        settings.autoShutdownEnabled = false
        for day in Weekday.allCases {
            settings.schedule.rules[day] = rule(mode)
        }
        store.save(settings)
        store.saveAutomaticScheduleConsent(true)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-hours-lock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return Fixture(
            defaults: defaults,
            deadlines: ModelTestSupport.lockoutDeadlineStore(),
            activityDirectory: directory
        )
    }

    /// One app launch over the fixture's persisted settings, activity history
    /// and lockout record.
    private func launch(_ fixture: Fixture, clock: @escaping () -> Date) throws -> CurfewAppModel {
        let model = try CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: fixture.defaults),
            appRouter: AppRouterSpy(),
            flavor: .production,
            featureFlags: FeatureFlags(
                widgetKitEnabled: false, cloudSyncEnabled: false, mcpServerEnabled: false,
                privilegedHelperEnabled: false, calendarEnabled: false
            ),
            activityRecorder: ActivityRecorder(
                store: ActivityStore(directory: fixture.activityDirectory)
            ),
            lockoutDeadlineStore: fixture.deadlines,
            keyboardShield: KeyboardShieldSpy(),
            runtimeNow: clock(),
            enforcementClock: clock
        )
        model.start()
        return model
    }

    @Test("Hours mode keeps the lock time where the hours ran out while it stays locked")
    func hoursModeLockTimeHolds() throws {
        let fixture = try fixture(mode: .hours)
        var now = at(10)
        let model = try launch(fixture) { now }
        defer {
            model.stopEnforcementForUninstall()
            try? FileManager.default.removeItem(at: fixture.activityDirectory)
        }
        #expect(model.state.phase == .locked)
        #expect(model.state.trigger == .hours)
        #expect(model.state.lockDate == at(10))

        for later in [at(10, second: 1), at(10, 1), at(10, 30), at(13, 45), at(21, 59)] {
            now = later
            model.tick()
            #expect(model.state.phase == .locked)
            #expect(model.state.lockDate == at(10))
            #expect(model.state.trigger == .hours)
        }
    }

    @Test("Combined mode keeps the hours lock time, even past the wall-clock curfew")
    func combinedModeLockTimeHolds() throws {
        let fixture = try fixture(mode: .combined)
        var now = at(10)
        let model = try launch(fixture) { now }
        defer {
            model.stopEnforcementForUninstall()
            try? FileManager.default.removeItem(at: fixture.activityDirectory)
        }
        #expect(model.state.phase == .locked)
        #expect(model.state.trigger == .hours)
        #expect(model.state.lockDate == at(10))

        for later in [at(10, 1), at(11), at(21, 59), at(22), at(23, 30)] {
            now = later
            model.tick()
            #expect(model.state.phase == .locked)
            #expect(model.state.lockDate == at(10))
            #expect(model.state.trigger == .hours)
        }
    }

    @Test("A relaunch during an hours lock keeps the original lock time")
    func relaunchKeepsLockTime() throws {
        let fixture = try fixture(mode: .hours)
        var now = at(10)
        let first = try launch(fixture) { now }
        now = at(10, 20)
        first.tick()
        #expect(first.state.lockDate == at(10))
        first.stopEnforcementForUninstall()
        defer { try? FileManager.default.removeItem(at: fixture.activityDirectory) }

        now = at(12, 5)
        let second = try launch(fixture) { now }
        defer { second.stopEnforcementForUninstall() }
        #expect(second.state.phase == .locked)
        #expect(second.state.lockDate == at(10))
        now = at(12, 6)
        second.tick()
        #expect(second.state.phase == .locked)
        #expect(second.state.lockDate == at(10))
        #expect(second.lockoutDeadlineStore.load()?.lockoutStartedAt == at(10))
    }

    @Test("An hours lock that runs past midnight keeps its lock time until the morning unlock")
    func lockTimeHoldsPastMidnight() throws {
        let fixture = try fixture(mode: .hours)
        var now = at(10)
        let model = try launch(fixture) { now }
        defer {
            model.stopEnforcementForUninstall()
            try? FileManager.default.removeItem(at: fixture.activityDirectory)
        }
        let unlock = at(7, day: 19)
        #expect(model.state.unlockDate == unlock)

        for later in [at(23, 59), at(0, 1, day: 19), at(3, day: 19), at(6, 59, day: 19)] {
            now = later
            model.tick()
            #expect(model.state.phase == .locked)
            #expect(model.state.lockDate == at(10))
            #expect(model.state.unlockDate == unlock)
        }

        // The next working day starts its own count.
        now = at(7, 1, day: 19)
        model.tick()
        #expect(model.state.phase == .working)
        #expect(model.lockoutDeadlineStore.load() == nil)
        #expect((model.state.lockDate ?? .distantPast) > now)
    }
}
