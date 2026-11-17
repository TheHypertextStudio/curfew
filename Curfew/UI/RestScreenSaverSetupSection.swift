import AppKit
import CurfewKit
import SwiftUI

/// Explicit setup requests; opening Settings never changes the selected screensaver.
struct RestScreenSaverSetupSection: View {
    @State private var state: RestScreenSaverInstallation.State = .missingCompanion
    @State private var confirmingRemoval = false
    @State private var selection: RestSaverChoice.Selection = .unknown
    @State private var usesSelectedSaver = RestSaverFacts(defaults: .standard).usesSelectedSaver

    var body: some View {
        Section {
            LabeledContent {
                Button(installationTitle) {
                    state = installation.requestInstallation()
                }
                .accessibilityIdentifier("rest-saver-install")
            } label: {
                Text("Curfew's screen saver")
                Text(statusText)
            }
            LabeledContent {
                Button("Open Screen Saver Settings…") {
                    state = installation.openSystemSettings()
                }
                .accessibilityIdentifier("rest-saver-settings")
            } label: {
                Text("Choose Curfew in System Settings")
                Text("Your Mac's usual password still applies.")
            }
            if RestSaverChoice.offersSelectedSaverOption(selection: selection) {
                Toggle(
                    "Use this Mac's screen saver when the lock is idle",
                    isOn: $usesSelectedSaver
                )
                .toggleStyle(.switch)
                .onChange(of: usesSelectedSaver) { _, value in
                    RestSaverFacts(defaults: .standard).usesSelectedSaver = value
                }
                .accessibilityIdentifier("rest-saver-use-selected")
            }
            if canRemove {
                Button("Remove Curfew's screen saver…", role: .destructive) {
                    confirmingRemoval = true
                }
                .buttonStyle(.link)
                .confirmationDialog(
                    "Move Curfew's screen saver to the Trash?",
                    isPresented: $confirmingRemoval
                ) {
                    Button("Move to Trash", role: .destructive) {
                        state = installation.removeInstallation()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You can install it again here. Your theme is kept.")
                }
            }
        } header: {
            Text("Screen saver")
        }
        .onAppear {
            state = installation.inspect()
            selection = RestSaverSelectionReader.live()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            state = installation.inspect()
            selection = RestSaverSelectionReader.live()
        }
    }

    private var installationTitle: String {
        switch state {
        case .versionMismatch: "Update…"
        case .installed: "Reinstall…"
        default: "Install…"
        }
    }

    private var canRemove: Bool {
        switch state {
        case .installed, .versionMismatch: true
        default: false
        }
    }

    private var statusText: String {
        switch state {
        case .missingCompanion:
            "The companion is missing from this copy of Curfew. Reinstall the app to restore it."
        case .available(let version):
            "Version \(version) is ready to install."
        case .installed(let version):
            "Version \(version) is installed. Choose it in System Settings to use it."
        case .versionMismatch(let bundled, let installed):
            "Installed version \(installed). Version \(bundled) is available with this app."
        case .installRequestAccepted(let version):
            """
            Installation of version \(version) was requested. Finish the macOS installer, \
            then select Curfew in System Settings.
            """
        case .operationRejected(let reason):
            "\(reason) You can also open Screen Saver in System Settings."
        }
    }

    private var installation: RestScreenSaverInstallation {
        let userLibraryScreenSavers = FileManager.default.urls(
            for: .libraryDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("Screen Savers", isDirectory: true)
        return RestScreenSaverInstallation(
            locations: .init(
                bundledSaver: Bundle.main.url(forResource: "Curfew", withExtension: "saver"),
                userInstallationDirectory: userLibraryScreenSavers
            ),
            open: { NSWorkspace.shared.open($0) },
            removeOwnedSaver: { url in
                let expected = userLibraryScreenSavers.appendingPathComponent(
                    "Curfew.saver",
                    isDirectory: true
                )
                let moduleIdentifier = RestScreenSaverInstallation.moduleIdentifier
                guard url.standardizedFileURL.path == expected.standardizedFileURL.path,
                      url.resolvingSymlinksInPath().path == expected.standardizedFileURL.path,
                      Bundle(url: url)?.bundleIdentifier == moduleIdentifier
                else {
                    throw CocoaError(.fileWriteNoPermission)
                }
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
        )
    }
}
