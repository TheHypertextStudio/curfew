import AppKit
import CurfewKit
import SwiftUI

/// Uninstall panel extensions on `SettingsView`. Isolated from the
/// rest of Advanced so the destructive affordance has a visible seam.
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
        Section("Remove Curfew") {
            Text("Permanently delete settings, history, and the license key from this Mac. "
                + "Your synced schedule is kept. This cannot be undone.")
                .foregroundStyle(CurfewTheme.mutedInk)

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
        let appName = UninstallCoordinator.appBundleURL(for: .current).lastPathComponent
        let alert = NSAlert()
        alert.messageText = "Uninstall Curfew on this Mac?"
        alert.informativeText =
            "Your settings, history, and license key will be deleted from this Mac. " +
            "Your synced schedule is kept. You will then move Curfew to the Trash. " +
            "This cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Uninstall")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn, !model.isDemoSession else { return }

        model.browserNativeRuntime.stop()
        Task {
            guard await model.privilegedHelperManager.prepareForFullUninstall() else {
                presentDaemonUninstallFailure()
                return
            }
            let outcome = UninstallCoordinator.performUninstall(
                unregisterServices: { [] },
                backgroundService: model.backgroundServiceManager,
                onRecoveryStopped: { model.stopEnforcementForUninstall() }
            )
            UninstallLifecycle.finish(
                outcome: outcome, present: presentUninstallResult,
                terminate: { NSApp.terminate(nil) }
            )
        }
    }

    private func presentDaemonUninstallFailure() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Curfew couldn’t be uninstalled."
        alert.informativeText = model.privilegedHelperManager.lastError
            ?? "Background protection must be removed before Curfew can delete its saved data."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func presentUninstallResult(_ outcome: UninstallCoordinator.Outcome) {
        if outcome.blockedBeforeCleanup {
            let warning = NSAlert()
            warning.alertStyle = .warning
            warning.messageText = "Curfew Dev could not be uninstalled yet."
            warning.informativeText = outcome.summary +
                "\n\nThe app and its saved state were kept. " +
                "Retry from Settings before moving the app to Trash."
            warning.runModal()
            return
        }
        let appURL = UninstallCoordinator.appBundleURL(for: .current)
        let summary = NSAlert()
        summary.alertStyle = outcome.allSucceeded ? .informational : .warning
        summary.messageText = outcome.allSucceeded
            ? "Curfew's local state is cleared."
            : "Uninstall completed with some errors."
        summary.informativeText = outcome.summary + "\n\n" +
            "Drag \(appURL.lastPathComponent) from /Applications to the Trash to finish removing the app."
        summary.addButton(withTitle: "Reveal in Finder")
        summary.addButton(withTitle: "Done")

        if summary.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.activateFileViewerSelecting([
                appURL
            ])
        }
    }
}
