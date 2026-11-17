import AppIntents
import CurfewKit

/// Mirrors the MCP `curfew_get_time_remaining` read tool. Returns the whole
/// number of minutes until curfew as the intent's value (so Shortcuts can
/// branch on it) plus a short spoken dialog.
///
/// Read-only: shares the MCP read path; no consent flow.
struct TimeRemainingIntent: AppIntent {
    static var title: LocalizedStringResource = "Get time left"

    static var description = IntentDescription(
        "Returns the minutes until curfew locks this Mac.",
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
            dialog = IntentDialog(stringLiteral: IntentCopy.locked(
                unlockTime: status.unlockDate.map(CurfewIntentSupport.formatTime)
            ))
        case "day_off":
            minutes = .max
            dialog = IntentDialog(stringLiteral: IntentCopy.dayOff)
        case "working", "warning":
            guard let observedMinutes = status.minutesRemaining else {
                throw CurfewIntentError.statusUnavailable
            }
            minutes = observedMinutes
            dialog = IntentDialog(stringLiteral: CurfewIntentSupport.countdownLine(
                minutes: minutes,
                curfewTime: status.lockDate.map(CurfewIntentSupport.formatTime)
            ))
        default:
            throw CurfewIntentError.statusUnavailable
        }
        return .result(value: minutes, dialog: dialog)
    }
}
