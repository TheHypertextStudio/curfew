import CurfewKit
import Testing

struct DayRuleClockUpdateTests {
    @Test("Queued clock edits preserve the current trigger mode and work-hour limit")
    func preservesTriggerAfterWaitingForApproval() {
        for mode in CurfewMode.allCases {
            let current = DayRule(
                isDayOff: false,
                lockMinutes: 1080,
                unlockMinutes: 480,
                mode: mode,
                hoursLimitMinutes: 420,
                exception: DayRuleException()
            )
            let updated = current.applyingClockUpdate(
                lockMinutes: 1260,
                unlockMinutes: 540,
                isDayOff: true
            )
            #expect(updated.mode == mode)
            #expect(updated.hoursLimitMinutes == 420)
            #expect(updated.exception == current.exception)
            #expect(updated.lockMinutes == 1260)
            #expect(updated.unlockMinutes == 540)
            #expect(updated.isDayOff)
            #expect(current.lockMinutes == 1080)
            #expect(!current.isDayOff)
        }
    }

    @Test("Omitted clock-update fields keep the current saved values")
    func omittedValues() {
        let current = DayRule(
            isDayOff: true,
            lockMinutes: 1080,
            unlockMinutes: 420,
            mode: .combined,
            hoursLimitMinutes: 360,
            exception: DayRuleException()
        )
        let updated = current.applyingClockUpdate(lockMinutes: 1200)
        #expect(updated.isDayOff)
        #expect(updated.unlockMinutes == 420)
        #expect(updated.mode == .combined)
        #expect(updated.hoursLimitMinutes == 360)
        #expect(updated.exception == current.exception)
    }

    @Test("An explicit working-day change overrides a saved day off")
    func explicitWorkingDay() {
        let current = DayRule(isDayOff: true, lockMinutes: 1080, unlockMinutes: 480)
        let updated = current.applyingClockUpdate(lockMinutes: 1200, isDayOff: false)
        #expect(!updated.isDayOff)
        #expect(updated.mode == .time)
        #expect(updated.hoursLimitMinutes == nil)
        #expect(updated.exception == nil)
    }
}
