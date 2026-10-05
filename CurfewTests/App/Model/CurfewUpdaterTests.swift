@testable import Curfew
import Foundation
import Testing

@MainActor
struct CurfewUpdaterTests {
    @Test("Missing update configuration keeps development launch alive and reports the error")
    func missingConfigurationDisablesUpdates() {
        let updater = CurfewUpdater(bundle: Bundle(for: BundleMarker.self))
        #expect(!updater.canCheckForUpdates)
        #expect(updater.initializationError != nil)
        updater.checkForUpdates()
        #expect(!updater.canCheckForUpdates)
    }

    private final class BundleMarker {}
}
