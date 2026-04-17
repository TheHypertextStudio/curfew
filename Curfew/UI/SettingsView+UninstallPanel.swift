import AppKit
import SwiftUI

extension SettingsView {
    /// Advanced → Uninstall panel. Exists as a separate seam so
    /// `advancedPanel` can stay focused on everyday power-user toggles and
    /// the destructive action gets a visible boundary.
    ///
    /// The uninstall itself is a one-way operation (no restore) but we only
    /// touch filesystem + UserDefaults state that the app itself wrote —
    /// the app bundle in `/Applications` is left alone and surfaced to the
    /// user via a drag-to-Trash prompt, which matches Finder conventions
    /// and avoids having to re-obtain elevated permissions.
    var uninstallPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Uninstall",
                subtitle: "Remove all local state written by Curfew on this Mac."
            )

            Text(
                "Clears the activity log, MCP request queue, the " +
                    "bypass-deterrent LaunchAgent, and your settings. " +
                    "Your iCloud-synced schedule (Pro) is not affected."
            )
            .font(CurfewTypography.body(13))
            .foregroundStyle(CurfewTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)

            Button("Uninstall Curfew…") {
                confirmUninstall()
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
            .accessibilityHint("Opens a confirmation dialog before clearing local state.")
        }
    }

    /// Presents the confirmation dialog, runs the coordinator, then surfaces
    /// the outcome. Broken out of the button closure because `NSAlert`
    /// chaining reads better at statement level than inside a trailing
    /// closure.
    private func confirmUninstall() {
        let alert = NSAlert()
        alert.messageText = "Uninstall Curfew on this Mac?"
        alert.informativeText =
            "Curfew will remove its local state (activity log, settings, " +
            "license key, LaunchAgent). You'll then be prompted to drag " +
            "Curfew.app to the Trash. This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let outcome = UninstallCoordinator.performUninstall()
        presentUninstallResult(outcome)
    }

    private func presentUninstallResult(_ outcome: UninstallCoordinator.Outcome) {
        let summary = NSAlert()
        summary.alertStyle = outcome.allSucceeded ? .informational : .warning
        summary.messageText = outcome.allSucceeded
            ? "Curfew's local state is cleared."
            : "Uninstall completed with some errors."
        summary.informativeText = outcome.summary + "\n\n" +
            "Drag Curfew from /Applications to the Trash to finish removing the app."
        summary.addButton(withTitle: "Reveal in Finder")
        summary.addButton(withTitle: "Done")

        if summary.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([
                URL(fileURLWithPath: "/Applications/Curfew.app")
            ])
        }
    }
}
