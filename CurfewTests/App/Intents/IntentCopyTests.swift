@testable import Curfew
@testable import CurfewKit
import Foundation
import Testing

struct IntentCopyTests {
    private let banned = ["enforcement", "lockout", "—", "!", "Request "]

    @Test("A missing status asks the person to open Curfew without jargon")
    func missingStatus() {
        #expect(CurfewIntentSupport.statusSummary(nil)
            == "Curfew hasn't checked in. Open it to see where things stand.")
    }

    @Test("Durations read as hours and minutes")
    func durations() {
        #expect(CurfewIntentSupport.durationText(minutes: 210) == "3 hours 30 minutes")
        #expect(CurfewIntentSupport.durationText(minutes: 60) == "1 hour")
        #expect(CurfewIntentSupport.durationText(minutes: 1) == "1 minute")
        #expect(CurfewIntentSupport.durationText(minutes: 45) == "45 minutes")
        #expect(CurfewIntentSupport.durationText(minutes: 61) == "1 hour 1 minute")
    }

    @Test("Countdown names the time left and the curfew time")
    func countdown() {
        let line = CurfewIntentSupport.countdownLine(minutes: 210, curfewTime: "6:00 PM")
        #expect(line == "3 hours 30 minutes until curfew at 6:00 PM.")
        #expect(CurfewIntentSupport.countdownLine(minutes: 5, curfewTime: nil)
            == "5 minutes until curfew.")
    }

    @Test("Request dialogs are short and show no identifiers")
    func requestDialogs() {
        #expect(IntentCopy.moreTimeAsked == "Asked. Approve it in Curfew.")
        #expect(IntentCopy.overrideOpened
            == "Overrides only happen in Curfew. It's open. Make your case there.")
        let schedule = IntentCopy.scheduleAsked(weekday: "Monday", curfewTime: "6:00 PM", isDayOff: false)
        #expect(schedule == "Asked for curfew at 6:00 PM on Monday. Approve it in Curfew.")
        #expect(IntentCopy.scheduleAsked(weekday: "Saturday", curfewTime: nil, isDayOff: true)
            == "Asked for Saturday as a day off. Approve it in Curfew.")
    }

    @Test("Day off and locked lines use the product words")
    func phaseLines() {
        #expect(IntentCopy.dayOff == "Day off. No curfew today.")
        #expect(IntentCopy.locked(unlockTime: "7:00 AM") == "Locked. Unlocks at 7:00 AM.")
        let all = [
            IntentCopy.dayOff, IntentCopy.locked(unlockTime: nil), IntentCopy.moreTimeAsked,
            IntentCopy.overrideOpened, CurfewIntentSupport.statusSummary(nil)
        ]
        for line in all {
            for word in banned {
                #expect(!line.contains(word), "\(line) contains \(word)")
            }
        }
    }
}
