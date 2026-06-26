import AppIntents
import CurfewKit

/// Enqueues a signed `requestOverride` ``MCPPendingRequest`` — the same write
/// path the MCP tools use — and routes it through the **unchanged** app
/// consent flow.
///
/// Important: overrides are user-only by design. The app's
/// `handleNewMCPRequests` always refuses an override that arrives through the
/// queue ("Override grants are user-only — confirm one in-app"), because the
/// override friction model — 5-minute cooldown, 50-character reason, 3-second
/// confirm hold — only exists in-app. This intent therefore *prepares* the
/// override (capturing the reason and surfacing it to the app) and tells the
/// user to confirm it in Curfew. It does not, and must not, grant an override
/// on its own.
struct RequestOverrideIntent: AppIntent {
    static var title: LocalizedStringResource = "Request Curfew Override"

    static var description = IntentDescription(
        """
        Prepares a curfew override request with your reason. For your own \
        protection, overrides must be confirmed inside Curfew — this opens the \
        app so you can complete the confirmation.
        """,
        categoryName: "Requests"
    )

    /// Overrides can only be completed in-app, so bring Curfew forward after
    /// queueing the request.
    static var openAppWhenRun = true

    @Parameter(
        title: "Reason",
        description: "Your justification for working past curfew.",
        inputOptions: String.IntentInputOptions(multiline: true)
    )
    var reason: String

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try CurfewIntentSupport.enqueueWriteRequest(
            tool: .requestOverride,
            arguments: ["reason": reason]
        )
        return .result(
            dialog: IntentDialog(
                stringLiteral: "Overrides must be confirmed in Curfew. I've opened the app — "
                    + "finish the confirmation there to work past curfew."
            )
        )
    }
}
