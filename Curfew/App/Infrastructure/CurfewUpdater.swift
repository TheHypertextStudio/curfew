import Combine
import Observation
import Sparkle

/// Required Sparkle updater backing the app's update command.
@MainActor
@Observable
final class CurfewUpdater {
    static let isAvailable = true

    @ObservationIgnored private let performUpdateCheck: () -> Void
    @ObservationIgnored private var availabilitySubscription: AnyCancellable?

    private(set) var canCheckForUpdates = false

    convenience init() {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        self.init(availability: controller.updater.publisher(for: \.canCheckForUpdates)
            .eraseToAnyPublisher()) {
                controller.checkForUpdates(nil)
            }
    }

    /// Sparkle publishes availability on the main thread, including after an
    /// update dialog is canceled or fails. Keep observing for the whole session
    /// instead of freezing the menu at its startup or in-flight value.
    init(availability: AnyPublisher<Bool, Never>, check: @escaping () -> Void) {
        self.performUpdateCheck = check
        self.availabilitySubscription = availability.sink { [weak self] available in
            self?.canCheckForUpdates = available
        }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        performUpdateCheck()
    }
}
