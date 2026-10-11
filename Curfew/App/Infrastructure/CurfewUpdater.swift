import Observation
import Sparkle

/// Required Sparkle updater backing the app's update command.
@MainActor
@Observable
final class CurfewUpdater {
    static let isAvailable = true

    @ObservationIgnored private let controller: SPUStandardUpdaterController

    private(set) var canCheckForUpdates = false

    init() {
        self.controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.canCheckForUpdates = controller.updater.canCheckForUpdates
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
        canCheckForUpdates = controller.updater.canCheckForUpdates
    }
}
