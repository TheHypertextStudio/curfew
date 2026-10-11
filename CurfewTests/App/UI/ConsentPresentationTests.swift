@testable import Curfew
import CurfewKit
import Foundation
import Testing

struct ConsentPresentationTests {
    private func presentation(_ tool: MCPWriteTool, _ json: String, canExtend: Bool = true)
        -> ConsentPresentation {
        ConsentPresentation(
            request: MCPPendingRequest(tool: tool, argumentsJSON: json),
            schedule: .standardNineToFive, extensionMinutes: 15, canRequestExtension: canExtend,
            extensionsRemaining: 2
        )
    }

    @Test("Extension approval shows the configured duration and current availability")
    func extensionDetails() {
        let available = presentation(.requestExtension, "{}")
        #expect(available.summary == "Extend this session by 15 minutes.")
        #expect(available.canApprove)
        let unavailable = presentation(.requestExtension, "{}", canExtend: false)
        #expect(!unavailable.canApprove)
        #expect(unavailable.detail.contains("no longer available"))
    }

    @Test("Exhausted AI extensions explain the weekly limit and disable approval")
    func exhaustedExtension() {
        let preview = ConsentPresentation(
            request: MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}"),
            schedule: .standardNineToFive,
            extensionMinutes: 15,
            canRequestExtension: true,
            extensionsRemaining: 0
        )
        #expect(!preview.canApprove)
        #expect(preview.detail == "No extensions left this week.")
    }

    @Test("Schedule approval shows actual times, overnight behavior and cooldown")
    func scheduleDetails() {
        let proposal = presentation(
            .setSchedule,
            #"{"weekday":"monday","lock_time":"23:00","unlock_time":"07:00"}"#
        )
        #expect(proposal.canApprove)
        #expect(proposal.summary.contains("Mon"))
        #expect(proposal.summary.contains("23:00"))
        #expect(proposal.summary.contains("07:00 the next day"))
        #expect(proposal.detail.contains("at least 24 hours"))
        #expect(proposal.detail.contains("any active lockout ends"))
    }

    @Test("Approving a schedule edit explains discarded pending days")
    func pendingReplacement() {
        var proposed = WeeklySchedule.standardNineToFive
        proposed.rules[.tuesday] = DayRule(isDayOff: true, lockMinutes: 1080, unlockMinutes: 480)
        let pending = PendingScheduleChange(
            proposedSchedule: proposed, requestedAt: .now,
            effectiveAt: .now.addingTimeInterval(86400), classification: .weaker
        )
        for time in ["18:00", "23:00"] {
            let request = MCPPendingRequest(
                tool: .setSchedule,
                argumentsJSON: "{\"weekday\":\"monday\",\"lock_time\":\"\(time)\"}"
            )
            let preview = ConsentPresentation(
                request: request,
                schedule: .standardNineToFive,
                extensionMinutes: 15,
                canRequestExtension: true,
                extensionsRemaining: 2,
                pendingScheduleChange: pending
            )
            #expect(preview.detail.contains("Tue"))
            #expect(preview.detail.contains(time == "18:00" ? "Cancels" : "Replaces"))
        }
    }

    @Test("Day off is explicit and invalid requests cannot be approved")
    func invalidAndDayOff() {
        let off = presentation(
            .setSchedule,
            #"{"weekday":"monday","lock_time":"18:00","is_day_off":true}"#
        )
        #expect(off.summary == "Make Mon a day off.")
        #expect(off.canApprove)
        for json in [
            "{}",
            "bad json",
            #"{"weekday":"monday","lock_time":"25:00"}"#,
            #"{"weekday":"monday","lock_time":"18:00","unlock_time":"bad"}"#
        ] {
            #expect(!presentation(.setSchedule, json).canApprove)
        }
        #expect(!presentation(.requestOverride, "{}").canApprove)
    }
}
