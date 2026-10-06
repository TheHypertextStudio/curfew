import Combine
import DirectDistribution
import Foundation

@MainActor
final class CurfewUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var initializationError: String?

    private var updater: DirectUpdater?
    private var observation: AnyCancellable?

    init(bundle: Bundle = .main) {
        do {
            let updater = try DirectUpdater(bundle: bundle)
            try updater.start()
            self.updater = updater
            self.observation = updater.$canCheckForUpdates
                .sink { [weak self] in self?.canCheckForUpdates = $0 }
        } catch {
            // Development builds may lack release keys. Candidate preflight rejects them.
            self.initializationError = "Updates are unavailable: \(error)"
            NSLog("Curfew updater initialization failed: %@", String(describing: error))
        }
    }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }
}
