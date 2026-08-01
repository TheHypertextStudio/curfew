import AppIntents
import CurfewKit

/// Mirrors the MCP `curfew_request_extension` write tool. Enqueues a signed
/// ``MCPPendingRequest`` for `requestExtension` onto the shared queue and lets
/// the running app's consent flow decide — no auto-approve bypass.
///
/// Extensions are only *granted* during a warning stage (the app applies that
/// rule when it resolves the request); this intent just queues the ask, the
/// same way the MCP tool does.
struct RequestExtensionIntent: AppIntent {
    static var title: LocalizedStringResource = "Request Curfew Extension"

    static var description = IntentDescription(
        """
        Queues a request for a short work-session extension. Curfew shows a \
        consent prompt; extensions are only granted during the curfew warning \
        window.
        """,
        categoryName: "Requests"
    )

    /// Queues for in-app consent; no need to bring the app forward ourselves —
    /// the app's request monitor surfaces the consent sheet wherever it runs.
    static var openAppWhenRun = false

    @Parameter(
        title: "Reason",
        description: "Why you need more time (shown to you in the consent prompt).",
        default: ""
    )
    var reason: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = try CurfewIntentSupport.enqueueWriteRequest(
            tool: .requestExtension,
            arguments: ["reason": reason]
        )
        return .result(
            dialog: IntentDialog(
                stringLiteral: "Extension request queued. Approve it in Curfew to apply it. "
                    + "(Request \(id.uuidString.prefix(8)).)"
            )
        )
    }
}
