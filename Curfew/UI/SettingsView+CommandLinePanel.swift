import CurfewKit
import SwiftUI

extension SettingsView {
    var commandLinePanel: some View {
        Section {
            Text(
                "Use curfew-ctl to read your schedule, export activity, " +
                    "and request changes from Terminal."
            )
            .foregroundStyle(CurfewTheme.mutedInk)
            Button("Install command line tool…") {
                prepareCLIInstallation()
            }
            .accessibilityIdentifier("install-command-line-tool")
            .confirmationDialog("Install curfew-ctl?", isPresented: $showsCLIInstallation) {
                Button("Install") { applyCLIInstallation() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(cliInstallationSummary)
            }
            if !cliInstallationMessage.isEmpty {
                Text(cliInstallationMessage)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("command-line-installation-result")
            }
        } header: {
            Text("Command line (beta)")
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
