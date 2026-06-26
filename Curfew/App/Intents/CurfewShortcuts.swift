import AppIntents

/// Exposes Curfew's intents as App Shortcuts so they appear in Spotlight, the
/// Shortcuts app, and Siri with zero user setup. Each phrase must contain the
/// `\(.applicationName)` token so Siri can disambiguate against other apps.
struct CurfewAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CurfewStatusIntent(),
            phrases: [
                "What's my \(.applicationName) status",
                "Check \(.applicationName) status",
                "Am I in \(.applicationName)"
            ],
            shortTitle: "Curfew Status",
            systemImageName: "moon.stars"
        )
        AppShortcut(
            intent: TimeRemainingIntent(),
            phrases: [
                "How long until \(.applicationName)",
                "Time remaining in \(.applicationName)",
                "When does \(.applicationName) lock"
            ],
            shortTitle: "Time Remaining",
            systemImageName: "timer"
        )
        AppShortcut(
            intent: RequestExtensionIntent(),
            phrases: [
                "Request a \(.applicationName) extension",
                "Ask \(.applicationName) for more time"
            ],
            shortTitle: "Request Extension",
            systemImageName: "plus.circle"
        )
        AppShortcut(
            intent: RequestOverrideIntent(),
            phrases: [
                "Request a \(.applicationName) override",
                "Override \(.applicationName)"
            ],
            shortTitle: "Request Override",
            systemImageName: "lock.open"
        )
        AppShortcut(
            intent: SetScheduleIntent(),
            phrases: [
                "Set my \(.applicationName) schedule",
                "Change my \(.applicationName) curfew time"
            ],
            shortTitle: "Set Schedule",
            systemImageName: "calendar"
        )
    }
}
