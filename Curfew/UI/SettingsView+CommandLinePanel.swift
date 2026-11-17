import CurfewKit
import SwiftUI

extension SettingsView {
    var commandLinePanel: some View {
        SettingsGroup("Command line (beta)") {
            SettingsActionRow(
                title: "curfew-ctl",
                detail: cliInstallationMessage.isEmpty
                    ? "Read your schedule, export activity and ask for changes from Terminal."
                    : cliInstallationMessage,
                actionTitle: "Install command line tool…",
                identifier: "install-command-line-tool"
            ) {
                prepareCLIInstallation()
            }
            .confirmationDialog("Install curfew-ctl?", isPresented: $showsCLIInstallation) {
                Button("Install") { applyCLIInstallation() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(cliInstallationSummary)
            }
        }
    }

    private var cliInstaller: CLIInstallation {
        CLIInstallation(sourceURL: Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/curfew-ctl"))
    }

    private func prepareCLIInstallation() {
        guard !model.isDemoSession else {
            cliInstallationMessage = "This preview does not change your Mac."
            return
        }
        do {
            let plan = try cliInstaller.plan()
            guard !plan.changes.isEmpty else {
                cliInstallationMessage = "The command is already installed. " +
                    "Open a new Terminal and run curfew-ctl --help."
                return
            }
            cliInstallationSummary = plan.changes.joined(separator: "\n")
            showsCLIInstallation = true
        } catch {
            cliInstallationMessage = error.localizedDescription
        }
    }

    private func applyCLIInstallation() {
        do {
            try cliInstaller.install()
            cliInstallationMessage = "The command is installed. " +
                "Open a new Terminal and run curfew-ctl --help."
        } catch {
            cliInstallationMessage = error.localizedDescription
        }
    }
}
