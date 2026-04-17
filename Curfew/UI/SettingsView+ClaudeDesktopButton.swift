import AppKit
import SwiftUI

extension SettingsView {
    /// One-click button that merges Curfew's server block into Claude
    /// Desktop's config. Falls back to the "copy" path when Claude Desktop
    /// isn't installed — the UI surfaces both so power users on other
    /// MCP hosts (Cursor, etc.) still have the copy-paste flow.
    ///
    /// Lives in its own file so `SettingsView+InfoPanels.swift` stays
    /// under the 400-line file-length lint rule; the registration logic
    /// itself is in `ClaudeDesktopRegistration.swift`.
    @ViewBuilder
    var claudeDesktopRegisterButton: some View {
        let status = ClaudeDesktopRegistration.currentStatus()
        switch status {
        case .claudeNotInstalled:
            EmptyView()
        case .alreadyRegistered:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(CurfewTheme.accent)
                Text("Registered in Claude Desktop")
                    .font(CurfewTypography.label(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
        case .willReplace, .notRegistered, .registered:
            Button("Add to Claude Desktop") {
                runClaudeDesktopRegister()
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
        }
    }

    /// Fires the registration path and surfaces the outcome via NSAlert.
    /// Broken out of the button closure because `NSAlert` chaining reads
    /// better at statement level than inside a trailing closure.
    private func runClaudeDesktopRegister() {
        do {
            let result = try ClaudeDesktopRegistration.register()
            let alert = NSAlert()
            switch result {
            case .registered:
                alert.messageText = "Claude Desktop configured."
                alert.informativeText =
                    "Curfew is now registered with Claude Desktop. " +
                    "Restart Claude Desktop to pick up the change."
            case .alreadyRegistered:
                alert.messageText = "Already registered."
                alert.informativeText =
                    "Claude Desktop already points at this build of Curfew."
            case .claudeNotInstalled:
                alert.messageText = "Claude Desktop not found."
                alert.informativeText =
                    "Install Claude Desktop first, then come back here."
            default:
                alert.messageText = "Claude Desktop updated."
                alert.informativeText = ""
            }
            alert.runModal()
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not update Claude Desktop config."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }
}
