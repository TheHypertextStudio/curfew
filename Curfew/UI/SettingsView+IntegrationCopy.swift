import CurfewKit
import Foundation

extension SettingsView {
    enum IntegrationSection: Hashable {
        case localAI
        case requestHandling
        case taskBrowser
        case helper
    }

    static let integrationSectionOrder: [IntegrationSection] = [
        .localAI,
        .requestHandling,
        .taskBrowser,
        .helper
    ]

    static let localAISectionTitle = "AI assistants on this Mac"

    static let localAIExplanation = """
    While enabled, local assistants can read your Curfew status, schedule, activity, \
    and reflection text. They cannot end lockout or turn off Curfew.
    """

    static let localAIAuthorityDetails = """
    While this switch is on, connected AI assistants can read your Curfew status, schedule, \
    activity, and reflections. Reflection text is shared with the assistant when it asks. \
    Assistants can request an extension or schedule change; Curfew follows the choice below. \
    They cannot grant an override. They cannot end an active lockout or turn off enforcement.

    If “Let AI assistants declare work in progress” is on in Protected Work settings, an \
    assistant can postpone shutdown for the configured time without asking. This keeps the \
    task running but never unlocks the screen.
    """

    static let localAISetupExplanation = """
    Choose Add to Claude Desktop for automatic setup. Use Copy Configuration only when \
    setting up another compatible desktop app.
    """
}
