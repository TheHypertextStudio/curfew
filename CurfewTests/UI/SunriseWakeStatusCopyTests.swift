@testable import Curfew
import CurfewKit
import Foundation
import Testing

/// The Sunrise wake status is a sentence with a time, and when something
/// blocks the wake it says what and where to fix it.
struct SunriseWakeStatusCopyTests {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = .current
        return result
    }

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(
            year: 2026,
            month: 10,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    /// The plan's initializer belongs to CurfewKit; its stored form is public.
    private func plan(wakeAt: Date) throws -> SunriseWakePlan {
        let json = """
        {"owner":"o","occurrenceID":"\(UUID().uuidString)",\
        "wakeAt":\(wakeAt.timeIntervalSinceReferenceDate),\
        "holdUntil":\(wakeAt.addingTimeInterval(2100).timeIntervalSinceReferenceDate),\
        "allowsBattery":false}
        """
        return try JSONDecoder().decode(SunriseWakePlan.self, from: Data(json.utf8))
    }

    private func copy(
        _ status: SunriseWakeCoordinator.Status, plan: SunriseWakePlan?,
        wake: Bool = true, curfewOn: Bool = true
    ) -> SunriseWakeStatusCopy {
        SunriseWakeStatusCopy.resolve(
            wakeEnabled: wake, curfewOn: curfewOn, status: status, plan: plan, now: at(19, 12)
        )
    }

    @Test("A scheduled wake names the time and the day")
    func scheduledSentence() throws {
        let wake = at(20, 6, 30)
        let time = wake.formatted(date: .omitted, time: .shortened)
        let tomorrow = try plan(wakeAt: wake)
        let tonight = try plan(wakeAt: at(19, 23))
        let thursday = at(22, 6, 30)
        let later = try plan(wakeAt: thursday)
        let weekday = thursday.formatted(.dateTime.weekday(.wide))
        #expect(copy(.scheduled, plan: tomorrow)
            .sentence == "This Mac will wake at \(time) tomorrow.")
        #expect(copy(.scheduled, plan: tonight).sentence.hasSuffix(" today."))
        #expect(copy(.scheduled, plan: later).sentence.hasSuffix(" on \(weekday)."))
        #expect(copy(.scheduled, plan: tomorrow).fix == nil)
    }

    @Test("While the helper is asked, the sentence says so with the same time")
    func pendingSentence() throws {
        let wake = at(20, 6, 30)
        let time = wake.formatted(date: .omitted, time: .shortened)
        let wakePlan = try plan(wakeAt: wake)
        #expect(copy(.waitingForSchedule, plan: wakePlan).sentence
            == "Asking the Curfew helper to wake this Mac at \(time) tomorrow.")
    }

    @Test("Blocked wakes say what blocks them and where to fix it")
    func blockedSentences() throws {
        let wakePlan = try plan(wakeAt: at(20, 6, 30))
        let helper = copy(.helperUnavailable, plan: wakePlan)
        #expect(helper
            .sentence == "This Mac can't wake without the Curfew helper. Set it up in Protection.")
        #expect(helper.fix == .protection)
        #expect(copy(.requestRejected, plan: wakePlan).fix == .protection)
        #expect(copy(.batteryExcluded, plan: wakePlan).sentence
            ==
            "This Mac is on battery, so it won't wake. Connect power or allow Sunrise on battery.")
        #expect(copy(.scheduled, plan: wakePlan, curfewOn: false).sentence
            == "Curfew is off, so this Mac won't wake for Sunrise.")
        #expect(copy(.waitingForSchedule, plan: nil).sentence
            == "No working morning is coming up, so this Mac won't wake.")
    }

    @Test("With wake off the line says what still happens")
    func wakeOff() {
        #expect(copy(.disabled, plan: nil, wake: false).sentence
            == "Sunrise appears when you first use this Mac in the morning.")
    }

    @Test("Auto-shutdown warns inline, because a shut-down Mac cannot wake")
    func shutdownWarning() {
        #expect(SunriseWakeStatusCopy.shutdownWarning(autoShutdownEnabled: true, wakeEnabled: true)
            ==
            "Auto-shutdown is on. A Mac that has shut down can't wake, "
            + "so Sunrise waits until you turn it on.")
        #expect(SunriseWakeStatusCopy.shutdownWarning(
            autoShutdownEnabled: false,
            wakeEnabled: true
        ) == nil)
        #expect(SunriseWakeStatusCopy.shutdownWarning(
            autoShutdownEnabled: true,
            wakeEnabled: false
        ) == nil)
    }
}
