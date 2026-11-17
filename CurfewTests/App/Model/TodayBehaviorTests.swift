@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

/// Today's resolved content, the Call it a day gate and action, and the one
/// thing. Models here never show a window: overlays are suppressed in the test
/// host, the keyboard shield is a spy and the Curfew helper is disabled.
@MainActor
struct TodayBehaviorTests {
    private let calendar = Calendar.current

    private func at(_ hour: Int, _ minute: Int = 0, day: Int = 16) -> Date {
        calendar.date(from: DateComponents(
            year: 2026, month: 11, day: day, hour: hour, minute: minute
        ))!
    }

    private func situation(
        phase: EnforcementPhase = .working, stage: WarningStage = .none, minutes: Int = 150,
        enforcing: Bool = true, canExtend: Bool = false, extensionsLeft: Int = 2,
        overrideEnds: Date? = nil, callable: Bool = true
    ) -> TodaySituation {
        TodaySituation(
            setupComplete: true, enforcing: enforcing, phase: phase, warningStage: stage,
            minutesRemaining: minutes, upcomingCurfew: phase == .locked ? nil : at(18),
            unlockDate: at(7, day: 17), overrideEnds: overrideEnds,
            canRequestExtension: canExtend, extensionsRemaining: extensionsLeft,
            canCallItADay: callable
        )
    }

    // MARK: - Presentation

    @Test("The working day shows the countdown and the curfew in locale time")
    func workingDay() {
        let today = TodayPresentation.resolve(situation())
        let time = at(18).formatted(date: .omitted, time: .shortened)
        #expect(today.headline == .countdown("2:30"))
        #expect(today.line == "until curfew at \(time)")
        #expect(today.lineSymbol == .curfew)
        #expect(today.callsItADay)
        #expect(today.moreTime == nil)
        #expect(today.showsOneThing)
        #expect(today.spokenTime.hasPrefix("2 hours, 30 minutes"))
    }

    @Test("The warning half hour replaces the curfew line with the stage line")
    func warningLines() {
        let lines: [(WarningStage, String)] = [
            (.thirtyMinutes, "Decide what gets finished and what waits."),
            (.fifteenMinutes, "Finish what you're in. Don't start anything."),
            (.fiveMinutes, "Save everything."),
            (.twoMinutes, "Save everything."),
            (.oneMinute, "Last call.")
        ]
        for (stage, line) in lines {
            let today = TodayPresentation.resolve(situation(
                phase: .warning,
                stage: stage,
                minutes: 12
            ))
            #expect(today.headline == .countdown("0:12"))
            #expect(today.line == line)
            #expect(today.lineSymbol == nil)
        }
    }

    @Test("15 more minutes appears when it can act and says so when none are left")
    func moreTimeStates() {
        let offered = TodayPresentation.resolve(situation(
            phase: .warning, stage: .fifteenMinutes, minutes: 15, canExtend: true
        ))
        #expect(offered.moreTime == .available(extensionsLeft: 2))
        let exhausted = TodayPresentation.resolve(situation(
            phase: .warning, stage: .fifteenMinutes, minutes: 15, canExtend: true,
            extensionsLeft: 0
        ))
        #expect(exhausted.moreTime == .exhausted)
        #expect(VoicePack.standard.holdingWithRemaining(2) == "Keep holding. 2 left this week")
        #expect(VoicePack.standard.added == "Added")
        #expect(VoicePack.standard.noExtensionsLeft == "No extensions left")
    }

    @Test("Locked, off and day off never show a countdown or the actions")
    func statements() {
        let unlock = at(7, day: 17).formatted(date: .omitted, time: .shortened)
        let locked = TodayPresentation.resolve(situation(phase: .locked, minutes: 0))
        #expect(locked.headline == .statement("That's the day."))
        #expect(locked.line == "Unlocks at \(unlock)")
        #expect(locked.lineSymbol == .locked)
        #expect(!locked.callsItADay && locked.moreTime == nil && !locked.showsOneThing)

        let lockedButOff = TodayPresentation.resolve(situation(phase: .locked, enforcing: false))
        #expect(lockedButOff.headline == .statement("Curfew is off."))

        var dayOff = situation(phase: .dayOff, minutes: .max, callable: false)
        dayOff.upcomingCurfew = nil
        let rest = TodayPresentation.resolve(dayOff)
        #expect(rest.headline == .statement("No curfew today."))
        #expect(rest.showsOneThing)
        #expect(!rest.callsItADay)
    }

    // MARK: - Call it a day gate

    private func gate(
        enforcing: Bool = true, setup: Bool = true, phase: EnforcementPhase = .working,
        lock: Date? = nil, unlock: Date? = nil, override: Bool = false
    ) -> Bool {
        CallItADayGate.isAvailable(CallItADayGate.Situation(
            enforcing: enforcing, setupComplete: setup, phase: phase, now: at(15),
            lockDate: lock ?? at(18), unlockDate: unlock ?? at(7, day: 17),
            overrideActive: override
        ))
    }

    @Test("Call it a day is available only while Curfew is on and the day is running")
    func callItADayGate() {
        #expect(gate())
        #expect(gate(phase: .warning))
        #expect(!gate(enforcing: false))
        #expect(!gate(setup: false))
        #expect(!gate(phase: .locked))
        #expect(!gate(phase: .dayOff))
        #expect(!gate(override: true))
        #expect(!gate(lock: at(14)))
        #expect(!gate(unlock: .distantFuture))
    }

    // MARK: - Call it a day, end to end

    private func armedModel(clock: @escaping () -> Date, recorder: any ActivityRecording)
        -> CurfewAppModel {
        let defaults = UserDefaults(suiteName: "CurfewTodayTests.\(UUID().uuidString)")!
        let store = CurfewSettingsStore(defaults: defaults)
        var settings = store.load()
        settings.hasCompletedInitialSetup = true
        settings.autoShutdownEnabled = false
        for day in Weekday.allCases {
            settings.schedule.rules[day] = DayRule(
                isDayOff: false, lockMinutes: 18 * 60, unlockMinutes: 7 * 60
            )
        }
        store.save(settings)
        store.saveAutomaticScheduleConsent(true)
        return CurfewAppModel(
            settingsStore: store, appRouter: AppRouterSpy(), flavor: .production,
            featureFlags: FeatureFlags(
                widgetKitEnabled: false, cloudSyncEnabled: false, mcpServerEnabled: false,
                privilegedHelperEnabled: false, calendarEnabled: false
            ),
            activityRecorder: recorder,
            lockoutDeadlineStore: ModelTestSupport.lockoutDeadlineStore(),
            keyboardShield: KeyboardShieldSpy(),
            runtimeNow: clock(), enforcementClock: clock
        )
    }

    @Test("Call it a day records the stop and holds a durable lock until the scheduled unlock")
    func callItADayLocksDurably() throws {
        var now = at(17, 10)
        let store = try ActivityTestSupport.makeEphemeralStore(label: "today-call-it-a-day")
        let model = armedModel(clock: { now }, recorder: ActivityRecorder(store: store))
        defer { model.stopEnforcementForUninstall() }
        model.start()
        #expect(model.state.phase == .working)
        #expect(model.canCallItADay)

        #expect(model.callItADay())

        #expect(model.state.phase == .locked)
        #expect(model.state.lockDate == at(17, 10))
        let record = try #require(model.lockoutDeadlineStore.load())
        #expect(record.lockoutStartedAt == at(17, 10))
        #expect(record.scheduledUnlockAt == model.state.unlockDate)
        #expect(record.kind == .scheduledTime)
        let ends = try store.events(in: .distantPast ... .distantFuture)
            .compactMap(DayEnding.init(event:))
        #expect(ends.count == 1)
        #expect(ends.first?.cause == .calledItADay)
        #expect(model.isReflectionPending(.evening))
        #expect(!model.canCallItADay)
        #expect(!model.callItADay())

        // The schedule alone says "working" until 6 PM; the record holds.
        now = at(17, 40)
        model.tick()
        #expect(model.state.phase == .locked)
        #expect(model.todayPresentation.headline == .statement("That's the day."))
    }

    @Test("Call it a day does nothing while Curfew is off")
    func callItADayWhileOff() {
        let now = at(17, 10)
        let model = armedModel(clock: { now }, recorder: NullActivityRecording())
        model.displayTick()
        #expect(!model.isEnforcementRunning)
        #expect(!model.canCallItADay)
        #expect(!model.callItADay())
        #expect(model.lockoutDeadlineStore.load() == nil)
        #expect(model.state.phase == .working)
    }

    // MARK: - The one thing

    @Test("The one thing saves through the morning log, ticks and unticks")
    func oneThing() throws {
        let now = at(10)
        let store = try ActivityTestSupport.makeEphemeralStore(label: "today-one-thing")
        let model = armedModel(clock: { now }, recorder: ActivityRecorder(store: store))
        model.reflectionState.recorder = InMemoryReflectionRecording()
        model.currentTime = now
        #expect(model.todaysOneThing == nil)
        #expect(!model.saveTodaysOneThing("   "))

        #expect(model.saveTodaysOneThing("  Ship the billing migration "))
        #expect(model.todaysOneThing == TodayOneThing(
            text: "Ship the billing migration",
            isDone: false
        ))
        #expect(model.reflectionState.gatesResolvedToday.contains(.morning))

        model.setOneThingDone(true)
        #expect(model.todaysOneThing?.isDone == true)
        model.setOneThingDone(false)
        #expect(model.todaysOneThing?.isDone == false)
    }
}

/// Reflections kept in memory, newest last.
@MainActor
final class InMemoryReflectionRecording: ReflectionRecording {
    private(set) var stored: [Reflection] = []
    private(set) var mutationCount = 0

    func record(_ reflection: Reflection) {
        stored.append(reflection)
        mutationCount += 1
    }

    func reflections(in range: ClosedRange<Date>) -> [Reflection] {
        stored.filter { range.contains($0.timestamp) }
    }

    func trim(olderThan _: TimeInterval, now _: Date) {}
}
