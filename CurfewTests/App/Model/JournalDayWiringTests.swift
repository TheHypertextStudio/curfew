@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

/// The model records the two Journal facts: how the day ended and whether the
/// one thing was done. These tests drive the model calls directly with a
/// seeded state; nothing here arms enforcement or shows a lock.
@MainActor
struct JournalDayWiringTests {
    private let calendar = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 16) -> Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 11,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func makeModel(recorder: any ActivityRecording) -> CurfewAppModel {
        let suite = "studio.hypertext.curfew.tests.journal.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defaults.removePersistentDomain(forName: suite)
        return CurfewAppModel(
            settingsStore: CurfewSettingsStore(defaults: defaults),
            appRouter: AppRouterSpy(),
            flavor: .production,
            activityRecorder: recorder,
            lockoutDeadlineStore: ModelTestSupport.lockoutDeadlineStore(),
            accessibilityAuthorization: FakeAccessibilityAuthorization(trusted: true)
        )
    }

    private func evaluation(_ phase: EnforcementPhase, lockDate: Date?) -> CurfewEvaluation {
        CurfewEvaluation(
            phase: phase,
            warningStage: phase == .locked ? .lockout : .none,
            minutesRemaining: phase == .locked ? 0 : 20,
            canRequestExtension: false,
            lockDate: lockDate,
            unlockDate: lockDate?.addingTimeInterval(14 * 3600)
        )
    }

    private func dayEnds(_ store: ActivityStore) throws -> [DayEnding] {
        try store.events(in: .distantPast ... .distantFuture).compactMap(DayEnding.init(event:))
    }

    @Test("The lock records that it ended the day exactly once, across a relaunch")
    func lockRecordsOnce() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "journal-lock")
        let model = makeModel(recorder: ActivityRecorder(store: store))
        model.currentTime = at(18, 1)
        model.state = evaluation(.locked, lockDate: at(18))

        model.recordDayEndedByLockIfNeeded()
        model.recordDayEndedByLockIfNeeded()

        let relaunched = makeModel(recorder: ActivityRecorder(store: store))
        relaunched.currentTime = at(22)
        relaunched.state = evaluation(.locked, lockDate: at(18))
        relaunched.recordDayEndedByLockIfNeeded()

        let ends = try dayEnds(store)
        #expect(ends.count == 1)
        #expect(ends.first?.cause == .lock)
        #expect(ends.first?.stoppedAt == at(18))
        #expect(ends.first?.minutesFromCurfew == 0)
    }

    @Test("A lock moved by an extension stores the curfew that was scheduled")
    func lockAfterExtension() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "journal-extension")
        let model = makeModel(recorder: ActivityRecorder(store: store))
        model.extensionMinutesGrantedToday = 15
        model.currentTime = at(18, 15)
        model.state = evaluation(.locked, lockDate: at(18, 15))

        model.recordDayEndedByLockIfNeeded()

        let end = try #require(try dayEnds(store).first)
        #expect(end.scheduledCurfew == at(18))
        #expect(end.minutesFromCurfew == 15)
    }

    @Test("Calling it a day records the current time, and the lock that follows adds nothing")
    func calledItADay() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "journal-called")
        let model = makeModel(recorder: ActivityRecorder(store: store))
        model.currentTime = at(17, 40)
        model.state = evaluation(.warning, lockDate: at(18))

        #expect(model.recordCalledItADay())
        #expect(!model.recordCalledItADay())

        model.state = evaluation(.locked, lockDate: at(18))
        model.currentTime = at(18)
        model.recordDayEndedByLockIfNeeded()

        let ends = try dayEnds(store)
        #expect(ends.count == 1)
        #expect(ends.first?.cause == .calledItADay)
        #expect(ends.first?.minutesFromCurfew == -20)
        #expect(ends.first?.scheduledCurfew == at(18))
    }

    @Test("Calling it a day outside a working window records nothing")
    func calledItADayOutsideWindow() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "journal-outside")
        let model = makeModel(recorder: ActivityRecorder(store: store))
        model.state = .dayOff
        #expect(!model.recordCalledItADay())
        model.state = evaluation(.locked, lockDate: at(18))
        #expect(!model.recordCalledItADay())
        #expect(try dayEnds(store).isEmpty)
    }

    @Test("The one thing answer is stored against the day, even when answered after midnight")
    func oneThingOutcome() throws {
        let store = try ActivityTestSupport.makeEphemeralStore(label: "journal-one-thing")
        let model = makeModel(recorder: ActivityRecorder(store: store))
        model.currentTime = at(0, 20, day: 17)
        model.state = evaluation(.locked, lockDate: at(23, 30))
        model.recordOneThingOutcome(done: true)

        let records = model.journalDayRecords(in: at(0) ... at(12, day: 17))
        #expect(records.count == 1)
        #expect(records.first?.day == calendar.startOfDay(for: at(12)))
        #expect(records.first?.oneThingDone == true)
    }

    @Test("Activity and reflections are kept long enough for the year view")
    func retention() {
        #expect(CurfewAppModel.activityRetentionSeconds == JournalRetention.activitySeconds)
        #expect(CurfewAppModel.activityRetentionSeconds >= 400 * 24 * 60 * 60)
    }
}
