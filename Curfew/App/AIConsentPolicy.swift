import Foundation

/// Governs how the Curfew app responds to write requests from `curfew-mcp`.
///
/// The default policy is ``queue`` — every AI write request pauses for
/// user approval before taking effect. This keeps the user in control and
/// prevents an AI assistant from silently extending a curfew on their behalf.
///
/// Auto-approve exists for power users who want Claude to manage their focus
/// session entirely and trust it to act without a modal. It carries no safety
/// net: every request is granted immediately.
enum AIConsentPolicy: String, Codable, CaseIterable {
    /// Every write request from an AI tool is queued and shown as a consent
    /// sheet in the Curfew app. The user approves or denies before the action
    /// takes effect. This is the default and the recommended setting.
    case queue

    /// All AI write requests are granted automatically without showing a
    /// consent sheet. A banner notification is posted instead so the user
    /// remains aware of what was granted. Use only if you fully trust your
    /// AI assistant's judgment and want hands-free operation.
    case autoApprove

    /// All AI write requests are silently denied. `curfew-mcp` clients
    /// will see every write tool return a "policy denies" error. Use when
    /// you want read-only AI access without any chance of AI-triggered
    /// changes to enforcement.
    case deny

    /// Human-readable label for display in Settings.
    var displayName: String {
        switch self {
        case .queue: return "Queue for approval (recommended)"
        case .autoApprove: return "Auto-approve all requests"
        case .deny: return "Deny all write requests"
        }
    }

    /// Short description shown below the picker.
    var rationale: String {
        switch self {
        case .queue:
            return "You'll see a prompt in Curfew before any AI-requested change takes effect."
        case .autoApprove:
            return "AI tools can extend or override your curfew without asking first."
        case .deny:
            return "AI tools can read your schedule and status but cannot change anything."
        }
    }
}
