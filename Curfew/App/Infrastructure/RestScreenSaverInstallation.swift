import Foundation

/// Metadata and request receipts are distinct from screensaver host acceptance.
@MainActor
struct RestScreenSaverInstallation {
    static let moduleIdentifier = "studio.hypertext.apps.curfew.screensaver"
    static let settingsURL =
        URL(string: "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension")!

    enum State: Equatable {
        case missingCompanion
        case available(version: String)
        case installRequestAccepted(version: String)
        case installed(version: String)
        case versionMismatch(bundled: String, installed: String)
        case operationRejected(reason: String)
    }

    struct Locations {
        let bundledSaver: URL?
        let userInstallationDirectory: URL
    }

    let locations: Locations
    let open: (URL) -> Bool
    let removeOwnedSaver: (URL) throws -> Void

    /// Deliberately inert until the controller observes the contract tests fail.
    func inspect() -> State {
        .missingCompanion
    }

    func requestInstallation() -> State {
        .operationRejected(reason: "Not implemented")
    }

    func openSystemSettings() -> State {
        .operationRejected(reason: "Not implemented")
    }

    func removeInstallation() -> State {
        .operationRejected(reason: "Not implemented")
    }
}
