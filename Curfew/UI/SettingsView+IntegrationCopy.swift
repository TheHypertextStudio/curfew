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
    and reflection text. They can't end the lock or turn off Curfew.
    """

    static let localAIAuthorityDetails = """
    While this switch is on, connected AI assistants can read your Curfew status, schedule, \
    activity, and reflections. Reflection text is shared with the assistant when it asks. \
    Assistants can ask for more time or a schedule change; Curfew follows the choice below. \
    They can't grant an override, end the lock or turn off Curfew.

    If “Let AI assistants declare work in progress” is on in Protected work settings, an \
    assistant can postpone shutdown for the configured time without asking. This keeps the \
    task running but never unlocks the screen.
    """

    static let localAISetupExplanation = """
    Choose Add to Claude Desktop for automatic setup. Use Copy Configuration only when \
    setting up another compatible desktop app.
    """
}
