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

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let eval = CurfewIntentSupport.currentEvaluation()
        let minutes = eval.minutesRemaining

        let dialog: IntentDialog
        switch eval.phase {
        case .locked:
            dialog = "Curfew is already active."
        case .dayOff:
            dialog = "There's no curfew today."
        case .working, .warning:
            let noun = minutes == 1 ? "minute" : "minutes"
            dialog = IntentDialog(stringLiteral: "\(minutes) \(noun) until curfew.")
        }
        return .result(value: minutes, dialog: dialog)
    }
}
