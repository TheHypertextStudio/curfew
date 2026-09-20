@testable import Curfew
import Foundation
import Testing

@MainActor
struct UninstallCoordinatorTests {
    @Test func productionUninstallIncludesLegacyCoordinatorCredential() {
        let services = UninstallCoordinator.accountKeychainServices(
            flavor: .production,
            curfewService: "curfew",
            docketService: "docket"
        )

        #expect(services == [
            "curfew",
            "docket",
            KeychainDeviceAssertionSecretStore.service
        ])
    }

    @Test func developmentUninstallPreservesLegacyProductionCredential() {
        let services = UninstallCoordinator.accountKeychainServices(
            flavor: .development,
            curfewService: "curfew-dev",
            docketService: "docket-staging"
        )

        #expect(services == ["curfew-dev", "docket-staging"])
    }

    @Test func uninstallErasesFlavorScopedAccountKeychainState() {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        var erasedServices: [String] = []

        let outcome = UninstallCoordinator.performUninstall(
            home: home,
            defaultsSuiteName: "studio.hypertext.curfew.tests.\(UUID().uuidString)",
            eraseKeychainService: { erasedServices.append($0) }
        )

        #expect(outcome.allSucceeded)
        #expect(erasedServices == [
            CurfewServiceEndpoints.current.keychainService,
            DocketServiceEndpoints.current.keychainService
        ])
        #expect(outcome.removed
            .contains("Keychain: \(CurfewServiceEndpoints.current.keychainService)"))
        #expect(outcome.removed
            .contains("Keychain: \(DocketServiceEndpoints.current.keychainService)"))
    }

    @Test func completedUninstallTerminatesAfterPresentingTheOutcome() {
        var events: [String] = []
        let outcome = UninstallCoordinator.Outcome(removed: [], failed: [])

        UninstallLifecycle.finish(
            outcome: outcome,
            present: { _ in events.append("present") },
            terminate: { events.append("terminate") }
        )

        #expect(events == ["present", "terminate"])
    }
}
