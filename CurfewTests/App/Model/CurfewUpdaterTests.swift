import Combine
@testable import Curfew
import Testing

struct CurfewUpdaterTests {
    @Test("Current build always includes the required Sparkle updater")
    func updateAvailabilityMatchesLinkedFramework() {
        #expect(CurfewUpdater.isAvailable)
    }

    @MainActor
    @Test("Update checks become available again after cancellation or failure")
    func updateAvailabilityFollowsTheWholeCheck() {
        let availability = CurrentValueSubject<Bool, Never>(true)
        var requests = 0
        let updater = CurfewUpdater(availability: availability.eraseToAnyPublisher()) {
            requests += 1
            availability.send(false)
        }

        #expect(updater.canCheckForUpdates)
        updater.checkForUpdates()
        #expect(requests == 1)
        #expect(!updater.canCheckForUpdates)

        updater.checkForUpdates()
        #expect(requests == 1)

        availability.send(true)
        #expect(updater.canCheckForUpdates)
        updater.checkForUpdates()
        #expect(requests == 2)
    }

    @MainActor
    @Test("A starting updater waits until Sparkle allows the first check")
    func unavailableUpdaterDoesNotStartACheck() {
        let availability = CurrentValueSubject<Bool, Never>(false)
        var requests = 0
        let updater = CurfewUpdater(availability: availability.eraseToAnyPublisher()) {
            requests += 1
        }

        updater.checkForUpdates()
        #expect(requests == 0)
        availability.send(true)
        #expect(updater.canCheckForUpdates)
        updater.checkForUpdates()
        #expect(requests == 1)
    }
}
