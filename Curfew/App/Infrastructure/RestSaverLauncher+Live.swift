import AppKit
import CurfewAtmosphere
import Foundation

extension RestSaverLauncher {
    /// Resolve the public system application. Never terminate an engine which was
    /// already running before this request, including a saver started by the user.
    static func live(preferences: RestScreenSaverPreferences) -> RestSaverLauncher {
        let identifier = "com.apple.ScreenSaver.Engine"
        var launched: NSRunningApplication?
        return RestSaverLauncher(operations: Operations(
            resolve: {
                guard NSRunningApplication.runningApplications(
                    withBundleIdentifier: identifier
                ).isEmpty else { return nil }
                return NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
            },
            requestReadback: { _ = try preferences.requestReadback() },
            open: { url in
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                let application = try await NSWorkspace.shared.openApplication(
                    at: url, configuration: configuration
                )
                launched = application
                return application.processIdentifier
            },
            hasFullScreenReceipt: preferences.hasFullScreenAcknowledgement,
            isRunning: { pid in
                launched?.processIdentifier == pid && launched?.isTerminated == false
            },
            stopOwned: { pid in
                guard launched?.processIdentifier == pid else { return }
                _ = launched?.terminate()
                launched = nil
            },
            waitForReceipt: {
                // This is a bounded launch acknowledgement, never an unlock or
                // accessibility readiness timeout. Preview receipts cannot satisfy it.
                let deadline = ContinuousClock.now.advanced(by: .seconds(8))
                while ContinuousClock.now < deadline {
                    try Task.checkCancellation()
                    if preferences.hasFullScreenAcknowledgement() {
                        return
                    }
                    try await Task.sleep(for: .milliseconds(100))
                }
            }
        ))
    }
}
