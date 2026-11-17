import AppIntents
import CurfewKit
import Foundation

/// Mirrors the MCP `curfew_set_schedule` write tool. Queues a single-weekday
/// schedule change as a signed ``MCPPendingRequest`` and routes it through the
/// app's unchanged consent + anti-bypass path: weakening changes wait out a
/// 24-hour cooldown, strengthening changes apply at the next day boundary
/// (`SchedulePolicyEngine` classifies it inside the app, not here).
///
/// The queued `argumentsJSON` uses the exact keys the MCP tool emits
/// (`weekday`, `lock_time`, optional `unlock_time` / `is_day_off`) so
/// `applyMCPScheduleUpdate` parses it identically.
struct SetScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "Set curfew for a day"

    static var description = IntentDescription(
        """
        Asks Curfew to change one day's curfew. You approve it in Curfew. A \
        later curfew waits a day; an earlier one starts tomorrow.
        """,
        categoryName: "Requests"
    )

    static var openAppWhenRun = false

    @Parameter(title: "Weekday")
    var weekday: ScheduleWeekday

    @Parameter(
        title: "Curfew time",
        description: "When work ends and this Mac locks.",
        kind: .time
    )
    var lockTime: Date

    @Parameter(
        title: "Unlock time",
        description: "Optional. When this Mac unlocks. Leaves the current time if unset.",
        kind: .time
    )
    var unlockTime: Date?

    @Parameter(
        title: "Day off",
        description: "Mark this weekday as a day off (no curfew).",
        default: false
    )
    var isDayOff: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Set curfew on \(\.$weekday) to \(\.$lockTime)") {
            \.$unlockTime
            \.$isDayOff
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let lockHHMM = Self.hhmm(from: lockTime) else {
            throw CurfewIntentError.invalidLockTime
        }

        var arguments: [String: String] = [
            "weekday": weekday.mcpName,
            "lock_time": lockHHMM
        ]
        if let unlockTime, let unlockHHMM = Self.hhmm(from: unlockTime) {
            arguments["unlock_time"] = unlockHHMM
        }
        if isDayOff {
            arguments["is_day_off"] = "true"
        }

        try CurfewIntentSupport.enqueueWriteRequest(
            tool: .setSchedule,
            arguments: arguments
        )

        return .result(
            dialog: IntentDialog(stringLiteral: IntentCopy.scheduleAsked(
                weekday: weekday.rawValue.capitalized,
                curfewTime: CurfewIntentSupport.formatTime(lockTime),
                isDayOff: isDayOff
            ))
        )
    }

    /// Formats the time-of-day component of `date` as a strict 24-hour
    /// "HH:MM" string — the format the MCP schedule tool and the app-side
    /// parser both expect.
    private static func hhmm(from date: Date) -> String? {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        guard let hour = components.hour, let minute = components.minute,
              hour >= 0, hour < 24, minute >= 0, minute < 60
        else {
            return nil
        }
        return String(format: "%02d:%02d", hour, minute)
    }
}
