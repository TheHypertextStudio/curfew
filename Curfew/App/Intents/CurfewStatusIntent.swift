import AppIntents
import CurfewKit

/// Mirrors the MCP `curfew_status` read tool. A stale observation is unknown,
/// never a schedule-derived guess about a live remote lock.
///
/// Read-only: no consent flow, no queue write.
struct CurfewStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Curfew Status"

    static var description = IntentDescription(
        "Reports the current Curfew enforcement phase and how long remains until curfew.",
        categoryName: "Status"
    )

    /// Pure read — no reason to launch the app to answer.
    static var openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let status = CurfewIntentSupport.currentObservedStatus()
        let phase = status?.phase ?? "unknown"
        let summary = CurfewIntentSupport.statusSummary(status)
        return .result(value: phase, dialog: IntentDialog(stringLiteral: summary))
    }
}
