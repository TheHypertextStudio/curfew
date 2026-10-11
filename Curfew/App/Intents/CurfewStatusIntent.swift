import AppIntents
import CurfewKit

/// Mirrors the MCP `curfew_status` read tool. Returns the current phase plus a
/// spoken/typed summary, reading the same shared settings + enforcement engine
/// the MCP surface uses (see ``CurfewIntentSupport/currentEvaluation(at:)``).
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
        let eval = CurfewIntentSupport.currentEvaluation()
        let phase = phaseName(eval.phase)
        let summary = CurfewIntentSupport.statusSummary(eval)
        return .result(value: phase, dialog: IntentDialog(stringLiteral: summary))
    }
}
