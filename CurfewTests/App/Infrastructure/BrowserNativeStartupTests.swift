@testable import Curfew
import Foundation
import Testing

@MainActor
struct BrowserNativeStartupTests {
    @Test func policyCallbacksDoNotWriteBeforeRuntimeStartup() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserNativeStore(directory: directory)
        try store.activate()
        let coordinator = makeCoordinator()
        let runtime = BrowserNativeRuntime(store: store, coordinator: coordinator)

        coordinator.onPolicyChanged?(browserPolicy(at: Date()))
        withExtendedLifetime(runtime) {}

        #expect(try store.readPolicy() == nil)
    }

    @Test func disabledSettingsStayDisabledWhenTheNativeStoreStartsLater() throws {
        let fixture = try StartupFixture(enforcementEnabled: false)
        defer { fixture.cleanUp() }

        #expect(!fixture.runtime.enforcementEnabled)
        fixture.runtime.start()
        #expect(try fixture.nativeStore.isActive())
        #expect(try fixture.nativeStore.readPolicy()?.policy == nil)

        fixture.coordinator.onPolicyChanged?(browserPolicy(at: Date()))

        #expect(try fixture.nativeStore.readPolicy()?.policy == nil)
        #expect(!fixture.runtime.enforcementEnabled)
        #expect(!fixture.controller.settings.enforcementEnabled)
        #expect(!fixture.controller.viewModel.enforcementEnabled)
        #expect(!fixture.settingsStore.load().enforcementEnabled)
    }

    @Test func enabledSettingsRestoreAfterValidSetupStartsTheNativeStore() throws {
        let fixture = try StartupFixture(enforcementEnabled: true)
        defer { fixture.cleanUp() }

        fixture.runtime.start()
        let policy = browserPolicy(at: Date())
        fixture.coordinator.onPolicyChanged?(policy)

        #expect(try fixture.nativeStore.readPolicy()?.policy?.sessionID == policy.sessionID)
        #expect(fixture.runtime.enforcementEnabled)
        #expect(fixture.controller.settings.enforcementEnabled)
        #expect(fixture.controller.viewModel.enforcementEnabled)
        #expect(fixture.settingsStore.load().enforcementEnabled)
    }

    private func makeCoordinator() -> DocketBrowserPolicyCoordinator {
        DocketBrowserPolicyCoordinator(
            credentials: DocketCredentialStore(secretStore: StartupBrowserCredentials())
        )
    }

    private func browserPolicy(at date: Date) -> BrowserPolicySnapshot {
        BrowserPolicySnapshot(
            schemaVersion: "browser-policy/1",
            sessionID: UUID(),
            task: .init(id: "task", title: "Finish the task"),
            tracking: .running,
            scopes: [],
            grants: [],
            breakEndsAt: nil,
            connectionIsHealthy: true,
            generatedAt: date
        )
    }
}

@MainActor
private final class StartupFixture {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let suite = "BrowserNativeStartupTests-\(UUID().uuidString)"
    let nativeStore: BrowserNativeStore
    let settingsStore: BrowserIntegrationSettingsStore
    let coordinator: DocketBrowserPolicyCoordinator
    let runtime: BrowserNativeRuntime
    let controller: TaskBrowserEnforcementController

    init(enforcementEnabled: Bool) throws {
        let nativeStore = BrowserNativeStore(directory: directory)
        self.nativeStore = nativeStore
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settingsStore = BrowserIntegrationSettingsStore(defaults: defaults)
        self.settingsStore = settingsStore
        settingsStore.save(.init(
            docketConnectedOnce: true,
            chromeConnectedOnce: true,
            enforcementEnabled: enforcementEnabled
        ))
        let coordinator = DocketBrowserPolicyCoordinator(
            credentials: DocketCredentialStore(secretStore: StartupBrowserCredentials())
        )
        self.coordinator = coordinator
        let runtime = BrowserNativeRuntime(
            store: nativeStore,
            coordinator: coordinator,
            startupIsAllowed: { true },
            installForStartup: { try nativeStore.activate() }
        )
        self.runtime = runtime
        self.controller = TaskBrowserEnforcementController(
            runtime: runtime,
            settingsStore: settingsStore
        )
    }

    func cleanUp() {
        runtime.stop()
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: suite)
    }
}

@MainActor
private final class StartupBrowserCredentials: AccountSecretStoring {
    func data(for _: String) throws -> Data? {
        nil
    }

    func save(_: Data, for _: String) throws {}
    func delete(_: String) throws {}
}
