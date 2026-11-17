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
    static var title: LocalizedStringResource = "Ask for more time"

    static var description = IntentDescription(
        """
        Asks Curfew for more time before the lock. You approve it in Curfew, \
        and more time is only given in the last stretch before curfew.
        """,
        categoryName: "Requests"
    )

    /// Queues for in-app consent; no need to bring the app forward ourselves —
    /// the app's request monitor surfaces the consent sheet wherever it runs.
    static var openAppWhenRun = false

    @Parameter(
        title: "Reason",
        description: "Why you need more time. Curfew shows it when you approve.",
        default: ""
    )
    var reason: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try CurfewIntentSupport.enqueueWriteRequest(
            tool: .requestExtension,
            arguments: ["reason": reason]
        )
        return .result(
            dialog: IntentDialog(stringLiteral: IntentCopy.moreTimeAsked)
        )
    }
}
