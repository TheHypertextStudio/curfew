import AppKit
import CurfewKit
import SwiftUI

/// Claude Desktop integration panel extensions on `SettingsView`.
/// Adds a one-click "Add to Claude Desktop" button and a state pill
/// reflecting whether the merge has already been applied.
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
            switch result {
            case .registered, .alreadyRegistered:
                // Claude only reads MCP servers at launch, so a config change
                // does nothing until a full quit + relaunch — the #1 reason a
                // freshly-added server "doesn't show up". Make that explicit and
                // offer to do it, since closing the window is not enough.
                presentRestartAlert(alreadyRegistered: result == .alreadyRegistered)
            case .claudeNotInstalled:
                let alert = NSAlert()
                alert.messageText = "Claude Desktop not found."
                alert.informativeText =
                    "Install Claude Desktop first, then come back here."
                alert.runModal()
            default:
                let alert = NSAlert()
                alert.messageText = "Claude Desktop updated."
                alert.runModal()
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Could not update Claude Desktop config."
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    /// Tells the user Curfew is in the config and that Claude must be fully
    /// relaunched, offering to quit + reopen it for them.
    private func presentRestartAlert(alreadyRegistered: Bool) {
        let alert = NSAlert()
        alert.messageText = alreadyRegistered
            ? "Curfew is already in Claude's config."
            : "Curfew added to Claude Desktop."
        alert.informativeText =
            "Claude only loads MCP servers when it launches. Fully quit Claude "
                + "(⌘Q — closing the window isn't enough) and reopen it, then look "
                + "for the Curfew tools. You can let Curfew do that now."
        alert.addButton(withTitle: "Quit & Reopen Claude")
        alert.addButton(withTitle: "I'll Do It Myself")
        if alert.runModal() == .alertFirstButtonReturn {
            relaunchClaudeDesktop()
        }
    }

    /// Gracefully quits any running Claude Desktop instance and reopens it so
    /// the new MCP server is picked up. Falls back to `/Applications/Claude.app`
    /// when no instance is running.
    private func relaunchClaudeDesktop() {
        let workspace = NSWorkspace.shared
        let running = workspace.runningApplications.filter {
            $0.bundleURL?.lastPathComponent == "Claude.app"
        }
        let appURL = running.first?.bundleURL
            ?? URL(fileURLWithPath: "/Applications/Claude.app")
        running.forEach { $0.terminate() }
        // Give Claude a moment to quit before relaunching.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            workspace.openApplication(at: appURL, configuration: .init()) { _, _ in }
        }
    }
}
