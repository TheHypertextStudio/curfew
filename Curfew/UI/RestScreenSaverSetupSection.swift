import AppKit
import SwiftUI

/// Explicit setup requests; opening Settings never changes the selected screensaver.
struct RestScreenSaverSetupSection: View {
    @State private var state: RestScreenSaverInstallation.State = .missingCompanion
    @State private var confirmingRemoval = false

    var body: some View {
        Section("Screensaver") {
            Text(statusText)
                .foregroundStyle(CurfewTheme.mutedInk)
            Button(installationTitle) {
                state = installation.requestInstallation()
            }
            .accessibilityIdentifier("rest-saver-install")
            Button("Open Screen Saver Settings…") {
                state = installation.openSystemSettings()
            }
            .accessibilityIdentifier("rest-saver-settings")
            Text(
                """
                Choose Curfew in System Settings → Screen Saver after installing. \
                Your Mac’s usual authentication still applies.
                """
            )
            .foregroundStyle(CurfewTheme.mutedInk)
            if canRemove {
                Button("Remove Curfew screensaver…", role: .destructive) {
                    confirmingRemoval = true
                }
                .confirmationDialog(
                    "Move the Curfew screensaver to Trash?",
                    isPresented: $confirmingRemoval
                ) {
                    Button("Move to Trash", role: .destructive) {
                        state = installation.removeInstallation()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text(
                        "You can reinstall it here later. Your rest screen appearance will be kept."
                    )
                }
            }
        }
        .onAppear { state = installation.inspect() }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            state = installation.inspect()
        }
    }

    private var installationTitle: String {
        if case .versionMismatch = state {
            return "Update Curfew screensaver…"
        }
        return "Install Curfew screensaver…"
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
            "Curfew screensaver \(version) is ready to install."
        case .installed(let version):
            "Curfew screensaver \(version) is installed. Select it in System Settings to use it."
        case .versionMismatch(let bundled, let installed):
            "Installed version \(installed). Version \(bundled) is available with this app."
        case .installRequestAccepted(let version):
            """
            Installation of version \(version) was requested. Finish the macOS installer, \
            then select Curfew in System Settings.
            """
        case .operationRejected(let reason):
            "\(reason) You can also open System Settings → Screen Saver directly."
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
