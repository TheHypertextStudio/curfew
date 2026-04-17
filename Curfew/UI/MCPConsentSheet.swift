import SwiftUI

/// Modal sheet presented by the Curfew app when `curfew-mcp` has queued a
/// write request awaiting user approval.
///
/// Shown as a sheet on the current front window. The user sees:
///  - Which tool was called and from which context (always the MCP server)
///  - The reason the AI provided (from the `reason` argument)
///  - Approve / Deny buttons
///
/// Approval and denial are handled by the `onApprove` / `onDeny` closures
/// so the presentation site (the app model) can apply the granted action.
struct MCPConsentSheet: View {
    /// The pending request waiting for a decision.
    let request: MCPPendingRequest

    /// Called when the user taps "Approve". The presenter is responsible for
    /// applying the action (granting an extension, override, etc.) and
    /// removing the request from the queue.
    let onApprove: () -> Void

    /// Called when the user taps "Deny". The presenter writes the denial back
    /// to the queue so `curfew-mcp` can return a refusal to the client.
    let onDeny: () -> Void

    /// Decoded reason string from the request's JSON arguments. Falls back to
    /// a generic label when the argument is absent or malformed.
    private var reason: String {
        guard
            let data = request.argumentsJSON.data(using: .utf8),
            let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let text = args["reason"] as? String
        else {
            return "(no reason provided)"
        }
        return text
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AI Request")
                    .font(CurfewTypography.bodyEmphasis(18))
                    .foregroundStyle(CurfewTheme.ink)

                Text("An AI assistant (via \(request.tool.displayName)) is asking to change your Curfew enforcement.")
                    .font(CurfewTypography.body(14))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Request type")
                    .font(CurfewTypography.label(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
                Text(request.tool.displayName)
                    .font(CurfewTypography.bodyEmphasis(14))
                    .foregroundStyle(CurfewTheme.ink)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Reason provided")
                    .font(CurfewTypography.label(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
                Text(reason)
                    .font(CurfewTypography.body(14))
                    .foregroundStyle(CurfewTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Requested at")
                    .font(CurfewTypography.label(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
                Text(requestedAtText)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }

            HStack(spacing: 12) {
                Button("Deny") {
                    onDeny()
                }
                .buttonStyle(CurfewSecondaryButtonStyle())

                Button("Approve") {
                    onApprove()
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var requestedAtText: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return fmt.string(from: request.requestedAt)
    }
}
