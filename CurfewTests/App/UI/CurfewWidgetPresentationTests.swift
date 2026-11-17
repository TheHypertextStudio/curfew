@testable import Curfew
import Foundation
import Testing

struct CurfewWidgetPresentationTests {
    private let clock: (Date) -> String = { _ in "6:00 PM" }

    @Test("Before curfew the widget shows hours and minutes and the curfew time")
    func working() {
        let presentation = CurfewWidgetPresentation(
            phase: "working", minutesRemaining: 150, lockDate: Date(), unlockDate: nil,
            timeFormatter: clock
        )
        #expect(presentation.headline == "2:30")
        #expect(presentation.headlineIsCountdown)
        #expect(presentation.line == "until curfew at 6:00 PM")
        #expect(presentation.accessibilityLabel == "2 hours 30 minutes until curfew at 6:00 PM.")
    }

    @Test("The sun sits lower as curfew nears")
    func sunLowers() {
        func height(_ minutes: Int) -> Double? {
            CurfewWidgetPresentation(
                phase: "warning", minutesRemaining: minutes, lockDate: nil, unlockDate: nil
            ).sunHeight
        }
        #expect(height(600) == 1)
        #expect((height(240) ?? 0) > (height(30) ?? 1))
        #expect(height(0) == 0)
    }

    @Test("While locked there is no sun and the line names the unlock time")
    func locked() {
        let presentation = CurfewWidgetPresentation(
            phase: "locked", minutesRemaining: 0, lockDate: nil, unlockDate: Date(),
            timeFormatter: { _ in "7:00 AM" }
        )
        #expect(presentation.sunHeight == nil)
        #expect(presentation.line == "Unlocks at 7:00 AM")
        #expect(!presentation.headlineIsCountdown)
    }

    @Test("Countdown matches the app's H:MM format")
    func countdownFormat() {
        #expect(CurfewWidgetPresentation.countdown(minutes: 5) == "0:05")
        #expect(CurfewWidgetPresentation.countdown(minutes: 61) == "1:01")
        #expect(CurfewWidgetPresentation.countdown(minutes: -3) == "0:00")
    }

    @Test("Widget words avoid internal terms")
    func vocabulary() {
        for phase in ["working", "warning", "locked", "day_off"] {
            let presentation = CurfewWidgetPresentation(
                phase: phase, minutesRemaining: 30, lockDate: Date(), unlockDate: Date()
            )
            for text in [
                presentation.headline,
                presentation.line,
                presentation.accessibilityLabel
            ] {
                for banned in ["enforcement", "Warning", "T-", "streak", "lockout"] {
                    #expect(!text.contains(banned), "\(text)")
                }
            }
        }
    }
}
