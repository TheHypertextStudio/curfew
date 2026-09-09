@testable import Curfew
import Foundation
import Testing

@MainActor
struct TaskBrowserEnforcementViewModelTests {
    private let now = Date(timeIntervalSince1970: 1_788_537_600)

    @Test("Fresh setup and a live paused task are ready for enforcement")
    func freshSetupIsReady() {
        let viewModel = TaskBrowserEnforcementViewModel(
            settings: .init(
                docketConnectedOnce: true,
                chromeConnectedOnce: true,
                enforcementEnabled: true
            ),
            isAuthorized: true,
            lastSuccessfulPoll: now.addingTimeInterval(-30),
            docketIsHealthy: true,
            nativeHealth: .init(
                extensionOrigin: "chrome-extension://curfew",
                extensionSeenAt: now.addingTimeInterval(-10),
                hostSeenAt: now.addingTimeInterval(-10),
                isHealthy: true
            ),
            hostIsInstalled: true,
            installationError: nil,
            policy: policy(tracking: .paused, breakEndsAt: nil),
            canBeginBreak: true,
            now: now
        )

        #expect(viewModel.docketAuthorization.isHealthy)
        #expect(viewModel.docketPoll.isHealthy)
        #expect(viewModel.extensionHeartbeat.isHealthy)
        #expect(viewModel.nativeHost.isHealthy)
        #expect(viewModel.enforcementReadiness.isHealthy)
        #expect(viewModel.activeTaskTitle == "Complete LVBT social strategy")
        #expect(viewModel.canToggleEnforcement)
        #expect(viewModel.enforcementEnabled)
        #expect(viewModel.canBeginBreak)
        #expect(viewModel.breakEndsAt == nil)
    }

    @Test("A stale extension heartbeat is unhealthy without revoking setup")
    func staleHeartbeatIsUnhealthy() {
        let viewModel = TaskBrowserEnforcementViewModel(
            settings: .init(
                docketConnectedOnce: true,
                chromeConnectedOnce: true,
                enforcementEnabled: true
            ),
            isAuthorized: true,
            lastSuccessfulPoll: now,
            docketIsHealthy: true,
            nativeHealth: .init(
                extensionOrigin: "chrome-extension://curfew",
                extensionSeenAt: now.addingTimeInterval(-61),
                hostSeenAt: now.addingTimeInterval(-10),
                isHealthy: false
            ),
            hostIsInstalled: true,
            installationError: nil,
            policy: policy(tracking: .paused, breakEndsAt: now.addingTimeInterval(-1)),
            canBeginBreak: false,
            now: now
        )

        #expect(!viewModel.extensionHeartbeat.isHealthy)
        #expect(viewModel.extensionHeartbeat.detail == "Last seen 1 minute ago")
        #expect(viewModel.nativeHost.isHealthy)
        #expect(!viewModel.enforcementReadiness.isHealthy)
        #expect(viewModel.canToggleEnforcement)
        #expect(viewModel.enforcementEnabled)
        #expect(!viewModel.canBeginBreak)
        #expect(viewModel.breakEndsAt == nil)
    }

    @Test("A missing extension heartbeat is shown as never")
    func missingHeartbeatIsNever() {
        let viewModel = TaskBrowserEnforcementViewModel(
            settings: .init(),
            isAuthorized: false,
            lastSuccessfulPoll: nil,
            docketIsHealthy: false,
            nativeHealth: .init(
                extensionOrigin: "",
                extensionSeenAt: .distantPast,
                hostSeenAt: .distantPast,
                isHealthy: false
            ),
            hostIsInstalled: true,
            installationError: nil,
            policy: nil,
            canBeginBreak: false,
            now: now
        )

        #expect(!viewModel.extensionHeartbeat.isHealthy)
        #expect(viewModel.extensionHeartbeat.detail == "Never")
        #expect(!viewModel.nativeHost.isHealthy)
    }

    @Test("Missing setup keeps enforcement off and disabled")
    func missingSetupDisablesToggle() {
        let viewModel = TaskBrowserEnforcementViewModel(
            settings: .init(),
            isAuthorized: false,
            lastSuccessfulPoll: nil,
            docketIsHealthy: false,
            nativeHealth: nil,
            hostIsInstalled: false,
            installationError: "Chrome browser integration could not be installed.",
            policy: nil,
            canBeginBreak: false,
            now: now
        )

        #expect(!viewModel.docketAuthorization.isHealthy)
        #expect(!viewModel.nativeHost.isHealthy)
        #expect(!viewModel.enforcementReadiness.isHealthy)
        #expect(!viewModel.canToggleEnforcement)
        #expect(!viewModel.enforcementEnabled)
        #expect(viewModel.activeTaskTitle == nil)
    }

    private func policy(
        tracking: DocketTrackingState,
        breakEndsAt: Date?
    ) -> BrowserPolicySnapshot {
        .init(
            schemaVersion: "browser-policy/1",
            sessionID: UUID(),
            task: .init(id: "task-lvbt", title: "Complete LVBT social strategy"),
            tracking: tracking,
            scopes: [],
            grants: [],
            breakEndsAt: breakEndsAt,
            connectionIsHealthy: true,
            generatedAt: now
        )
    }
}

@MainActor
struct TaskBrowserEnforcementControllerTests {
    private let now = Date(timeIntervalSince1970: 1_788_537_600)

    @Test("The controller records setup proofs and drives every panel action")
    func controllerDrivesPanelActions() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let nativeStore = BrowserNativeStore(directory: directory)
        try nativeStore.activate()
        let suite = "CurfewTaskBrowserControllerTests-\(UUID().uuidString)"
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let defaults = try #require(UserDefaults(suiteName: suite))
        let settingsStore = BrowserIntegrationSettingsStore(defaults: defaults)
        let credentialStore = DocketCredentialStore(
            secretStore: ControllerCredentialStore()
        )
        let oauth = ControllerOAuth(now: now)
        let coordinator = DocketBrowserPolicyCoordinator(
            transport: ControllerTransport(now: now),
            credentials: credentialStore,
            oauth: oauth
        )
        let runtime = BrowserNativeRuntime(store: nativeStore, coordinator: coordinator)
        let controller = TaskBrowserEnforcementController(
            runtime: runtime,
            settingsStore: settingsStore,
            now: { now }
        )

        #expect(!controller.setEnforcementEnabled(true, at: now))
        try await controller.connect(at: now)
        #expect(controller.settings.docketConnectedOnce)
        #expect(!controller.settings.chromeConnectedOnce)
        try nativeStore.recordHeartbeat(at: now)
        controller.refresh(at: now)
        #expect(controller.settings.chromeConnectedOnce)
        #expect(controller.viewModel.canToggleEnforcement)
        #expect(controller.setEnforcementEnabled(true, at: now))
        #expect(try nativeStore.readPolicy()?.policy != nil)

        try testMappingActions(controller: controller, settingsStore: settingsStore)

        #expect(controller.viewModel.canBeginBreak)
        #expect(controller.beginBreak(at: now))
        #expect(controller.viewModel.breakEndsAt == now.addingTimeInterval(15 * 60))
        #expect(!controller.viewModel.canBeginBreak)

        try await controller.disconnect(at: now.addingTimeInterval(1))
        #expect(!controller.viewModel.docketAuthorization.isHealthy)
        #expect(controller.settings.docketConnectedOnce)
        #expect(controller.settings.chromeConnectedOnce)
        #expect(controller.settings.enforcementEnabled)
        #expect(try nativeStore.readPolicy()?.policy != nil)
        #expect(!coordinator.isAuthorized)
        #expect(oauth.connectCount == 1)
    }

    @Test("A failed Docket poll makes a ready panel unhealthy without user action")
    func failedPollUpdatesLiveHealth() async throws {
        let fixture = try LiveHealthFixture()
        let controller = await fixture.makeController()
        #expect(controller.viewModel.enforcementReadiness.isHealthy)

        await fixture.transport.setUnavailable(true)
        fixture.clock.now = fixture.clock.now.addingTimeInterval(1)
        await fixture.coordinator.poll(at: fixture.clock.now)
        fixture.pulseHealthMonitor()
        await waitUntil { !controller.viewModel.docketPoll.isHealthy }

        #expect(!controller.viewModel.docketPoll.isHealthy)
        #expect(!controller.viewModel.enforcementReadiness.isHealthy)
    }

    @Test("A ready panel expires a 61-second Chrome heartbeat without user action")
    func heartbeatExpiryUpdatesLiveHealth() async throws {
        let fixture = try LiveHealthFixture()
        let controller = await fixture.makeController()
        #expect(controller.viewModel.enforcementReadiness.isHealthy)

        fixture.clock.now = fixture.clock.now.addingTimeInterval(61)
        fixture.pulseHealthMonitor()
        await waitUntil { !controller.viewModel.extensionHeartbeat.isHealthy }

        #expect(!controller.viewModel.extensionHeartbeat.isHealthy)
        #expect(!controller.viewModel.nativeHost.isHealthy)
        #expect(!controller.viewModel.enforcementReadiness.isHealthy)
    }

    @Test("A failed disable keeps the runtime, UI, and stored toggle enabled")
    func failedDisableRollsBackEveryToggleLayer() async throws {
        let fixture = try LiveHealthFixture(enforcementEnabled: true)
        let controller = await fixture.makeController()
        try fixture.nativeStore.deactivate()

        let didDisable = controller.setEnforcementEnabled(false, at: fixture.clock.now)

        #expect(!didDisable)
        #expect(controller.settings.enforcementEnabled)
        #expect(controller.viewModel.enforcementEnabled)
        #expect(fixture.settingsStore.load().enforcementEnabled)
        #expect(fixture.runtime.enforcementEnabled)
    }

    @Test("A failed enable keeps the runtime, UI, and stored toggle disabled")
    func failedEnableRollsBackEveryToggleLayer() async throws {
        let fixture = try LiveHealthFixture(enforcementEnabled: false)
        let controller = await fixture.makeController()
        try fixture.nativeStore.deactivate()

        let didEnable = controller.setEnforcementEnabled(true, at: fixture.clock.now)

        #expect(!didEnable)
        #expect(!controller.settings.enforcementEnabled)
        #expect(!controller.viewModel.enforcementEnabled)
        #expect(!fixture.settingsStore.load().enforcementEnabled)
        #expect(!fixture.runtime.enforcementEnabled)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0 ..< 1000 where !condition() {
            await Task.yield()
        }
    }

    private func testMappingActions(
        controller: TaskBrowserEnforcementController,
        settingsStore: BrowserIntegrationSettingsStore
    ) throws {
        let mapping = try controller.addMapping(
            selector: .label("social"),
            destination: "https://instagram.com",
            scopeKind: .origin,
            at: now
        )
        #expect(controller.settings.mappings == [mapping])
        #expect(settingsStore.load().mappings == [mapping])
        controller.removeMapping(id: mapping.id, at: now)
        #expect(controller.settings.mappings.isEmpty)
    }
}

@MainActor
private final class ControllerCredentialStore: AccountSecretStoring {
    private var values: [String: Data] = [:]

    func data(for account: String) throws -> Data? {
        values[account]
    }

    func save(_ data: Data, for account: String) throws {
        values[account] = data
    }

    func delete(_ account: String) throws {
        values[account] = nil
    }
}

@MainActor
private final class ControllerOAuth: DocketOAuthAuthorizing {
    let now: Date
    private(set) var connectCount = 0

    init(now: Date) {
        self.now = now
    }

    func connect(at _: Date) async throws -> DocketOAuthTokens {
        connectCount += 1
        return tokens
    }

    func refresh(now _: Date) async throws -> DocketOAuthTokens {
        tokens
    }

    private var tokens: DocketOAuthTokens {
        .init(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: now.addingTimeInterval(3600)
        )
    }
}

private actor ControllerTransport: DocketMCPTransporting {
    let now: Date

    init(now: Date) {
        self.now = now
    }

    func readActiveWork(accessToken _: String) async throws -> DocketActiveWork {
        .init(
            observedAt: now,
            tracking: .paused,
            recordID: "record-1",
            task: .init(
                id: "task-lvbt",
                organizationID: "org-lvbt",
                title: "Complete LVBT social strategy",
                description: nil,
                stateType: "started",
                workspace: .init(id: "workspace-lvbt", name: "LVBT"),
                project: .init(id: "project-lvbt", name: "Social strategy", summary: nil),
                labels: [.init(id: "social", name: "Social")],
                references: []
            )
        )
    }

    func readTaskState(
        organizationID _: String,
        taskID _: String,
        accessToken _: String
    ) async throws -> DocketTaskStateObservation {
        throw DocketClientError.unavailable
    }

    func reviewDestination(
        _: DocketDestinationReviewInput,
        accessToken _: String
    ) async throws -> DocketDestinationReview {
        .deny(reason: "Not used by this test.")
    }
}

private extension BrowserNativeStore {
    func recordHeartbeat(at date: Date) throws {
        try recordHeartbeat(
            origin: "chrome-extension://loammdknmfbkjnckaeeagnmakinknbck",
            at: date
        )
    }
}
