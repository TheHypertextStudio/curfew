@testable import Curfew
import Foundation
import Testing

@MainActor
struct BrowserIntegrationSettingsStoreTests {
    @Test("Browser setup facts and mappings persist outside synced Curfew settings")
    func setupFactsAndMappingsPersist() throws {
        let (store, suiteName) = makeStore()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        var settings = store.load()

        #expect(!settings.docketConnectedOnce)
        #expect(!settings.chromeConnectedOnce)
        #expect(!settings.enforcementEnabled)
        #expect(settings.mappings.isEmpty)

        settings.recordDocketConnection()
        settings.recordChromeConnection()
        let mapping = try settings.addMapping(
            selector: .task("task-lvbt"),
            destination: "https://instagram.com",
            scopeKind: .origin
        )
        let didEnable = settings.setEnforcementEnabled(true)
        #expect(didEnable)
        store.save(settings)

        let restored = store.load()
        #expect(restored.docketConnectedOnce)
        #expect(restored.chromeConnectedOnce)
        #expect(restored.enforcementEnabled)
        #expect(restored.mappings == [mapping])
    }

    @Test("Enforcement stays off until Docket and Chrome have each connected once")
    func setupGateRequiresBothConnections() {
        var settings = BrowserIntegrationSettings()

        let enabledBeforeSetup = settings.setEnforcementEnabled(true)
        #expect(!enabledBeforeSetup)
        settings.recordDocketConnection()
        let enabledBeforeChrome = settings.setEnforcementEnabled(true)
        #expect(!enabledBeforeChrome)
        settings.recordChromeConnection()
        let enabledAfterSetup = settings.setEnforcementEnabled(true)
        #expect(enabledAfterSetup)
        #expect(settings.enforcementEnabled)
    }

    @Test("Removing a mapping persists the remaining normalized list")
    func mappingRemovalPersists() throws {
        let (store, suiteName) = makeStore()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        var settings = BrowserIntegrationSettings()
        let removed = try settings.addMapping(
            selector: .project("project-old"),
            destination: "https://example.com/old",
            scopeKind: .pathPrefix
        )
        let retained = try settings.addMapping(
            selector: .label("social"),
            destination: "https://instagram.com",
            scopeKind: .origin
        )
        settings.removeMapping(id: removed.id)
        store.save(settings)

        #expect(store.load().mappings == [retained])
    }

    private func makeStore() -> (BrowserIntegrationSettingsStore, String) {
        let suiteName = "BrowserIntegrationSettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        return (BrowserIntegrationSettingsStore(defaults: defaults), suiteName)
    }
}
