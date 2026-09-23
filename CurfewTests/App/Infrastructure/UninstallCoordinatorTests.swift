@testable import Curfew
import Foundation
import Testing

@MainActor
struct UninstallCoordinatorTests {
    @Test func studioDevelopmentUninstallTouchesOnlyItsOwnState() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let studioSupport = home
            .appendingPathComponent("Library/Application Support/Curfew (Studio Dev)")
        let personalSupport = home
            .appendingPathComponent("Library/Application Support/Curfew (Dev)")
        let productionSupport = home.appendingPathComponent("Library/Application Support/Curfew")
        let studioGroup = home
            .appendingPathComponent(
                "Library/Group Containers/group.studio.hypertext.curfew.studio.dev/Curfew"
            )
        let personalGroup = home
            .appendingPathComponent(
                "Library/Group Containers/group.studio.hypertext.curfew.dev/Curfew"
            )
        let studioCaches = home
            .appendingPathComponent("Library/Caches/studio.hypertext.curfew.studio.dev")
        let personalCaches = home
            .appendingPathComponent("Library/Caches/studio.hypertext.curfew.dev")
        try createMarkedDirectories([
            studioSupport,
            personalSupport,
            productionSupport,
            studioGroup,
            personalGroup,
            studioCaches,
            personalCaches
        ])
        var erasedServices: [String] = []

        let outcome = UninstallCoordinator.performUninstall(
            home: home,
            flavor: .studioDevelopment,
            defaultsSuiteName: "studio.hypertext.curfew.studio.dev.tests.\(UUID().uuidString)",
            unregisterServices: { [] },
            eraseKeychainService: { erasedServices.append($0) }
        )

        verifyStudioUninstallPaths(
            outcome: outcome,
            removed: [studioSupport, studioGroup, studioCaches],
            preserved: [personalSupport, productionSupport, personalGroup, personalCaches]
        )
        #expect(erasedServices == [
            "studio.hypertext.curfew.account-e2ee.studio.dev",
            "studio.hypertext.curfew.docket.studio.dev",
            "studio.hypertext.curfew.studio.dev.coordinator"
        ])
        #expect(UninstallCoordinator.appBundleURL(for: .studioDevelopment).path
            == "/Applications/Curfew Studio Dev.app")
        #expect(UninstallCoordinator.appBundleURL(for: .development).path
            == "/Applications/Curfew.app")
    }

    @Test func failedStudioRegistrationCleanupKeepsStateAndAppRunning() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let marker = home
            .appendingPathComponent("Library/Application Support/Curfew (Studio Dev)/marker")
        try FileManager.default.createDirectory(
            at: marker.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("keep".utf8).write(to: marker)
        var erasedServices: [String] = []
        let outcome = UninstallCoordinator.performUninstall(
            home: home,
            flavor: .studioDevelopment,
            defaultsSuiteName: "studio.test.\(UUID().uuidString)",
            unregisterServices: { ["Privileged daemon could not be removed"] },
            eraseKeychainService: { erasedServices.append($0) }
        )
        var events: [String] = []
        UninstallLifecycle.finish(
            outcome: outcome,
            present: { _ in events.append("present") },
            terminate: { events.append("terminate") }
        )

        #expect(outcome.blockedBeforeCleanup)
        #expect(FileManager.default.fileExists(atPath: marker.path))
        #expect(erasedServices.isEmpty)
        #expect(events == ["present"])
    }

    private func createMarkedDirectories(_ directories: [URL]) throws {
        for directory in directories {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try Data("retain-or-remove".utf8).write(to: directory.appendingPathComponent("marker"))
        }
    }

    private func verifyStudioUninstallPaths(
        outcome: UninstallCoordinator.Outcome,
        removed: [URL],
        preserved: [URL]
    ) {
        #expect(outcome.allSucceeded)
        for path in removed {
            #expect(!FileManager.default.fileExists(atPath: path.path))
        }
        for path in preserved {
            #expect(FileManager.default
                .fileExists(atPath: path.appendingPathComponent("marker").path))
        }
    }

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
