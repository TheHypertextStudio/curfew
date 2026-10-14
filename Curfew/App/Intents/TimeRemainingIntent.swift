import AppIntents
import CurfewKit

/// Mirrors the MCP `curfew_get_time_remaining` read tool. Returns the whole
/// number of minutes until lockout as the intent's value (so Shortcuts can
/// branch on it) plus a short spoken dialog.
///
/// Read-only: shares the MCP read path; no consent flow.
struct TimeRemainingIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Time Remaining"

    static var description = IntentDescription(
        "Returns the number of minutes until curfew locks your Mac.",
        categoryName: "Status"
    )

    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        guard let status = CurfewIntentSupport.currentObservedStatus() else {
            throw CurfewIntentError.statusUnavailable
        }

        let minutes: Int
        let dialog: IntentDialog
        switch status.phase {
        case "locked":
            minutes = 0
            dialog = "Curfew is already active."
        case "day_off":
            minutes = .max
            dialog = "No automatic lockout is scheduled now. Remote locks remain possible."
        case "working", "warning":
            guard let observedMinutes = status.minutesRemaining else {
                throw CurfewIntentError.statusUnavailable
            }
            minutes = observedMinutes
            let noun = minutes == 1 ? "minute" : "minutes"
            dialog = IntentDialog(stringLiteral: "\(minutes) \(noun) until curfew.")
        default:
            throw CurfewIntentError.statusUnavailable
        }
        return .result(value: minutes, dialog: dialog)
    }
}
