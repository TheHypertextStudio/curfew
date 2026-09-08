@testable import Curfew
import Foundation
import Testing

@MainActor
final class LiveHealthFixture {
    let clock = ControllerClock(now: Date(timeIntervalSince1970: 1_788_537_600))
    let transport: HealthControllerTransport
    let coordinator: DocketBrowserPolicyCoordinator
    let runtime: BrowserNativeRuntime
    let nativeStore: BrowserNativeStore
    let settingsStore: BrowserIntegrationSettingsStore
    private let directory: URL
    private let suite: String
    private let healthUpdates: AsyncStream<Date>
    private let healthContinuation: AsyncStream<Date>.Continuation

    init(enforcementEnabled: Bool = true) throws {
        (self.healthUpdates, self.healthContinuation) = AsyncStream.makeStream(of: Date.self)
        self.directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let nativeStore = BrowserNativeStore(directory: directory)
        self.nativeStore = nativeStore
        try nativeStore.activate()
        try nativeStore.recordHeartbeat(
            origin: "chrome-extension://loammdknmfbkjnckaeeagnmakinknbck",
            at: clock.now
        )
        self.suite = "CurfewLiveBrowserHealthTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        self.settingsStore = BrowserIntegrationSettingsStore(defaults: defaults)
        settingsStore.save(.init(
            docketConnectedOnce: true,
            chromeConnectedOnce: true,
            enforcementEnabled: enforcementEnabled
        ))
        let credentialStore = DocketCredentialStore(secretStore: HealthCredentialStore())
        try credentialStore.save(.init(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: clock.now.addingTimeInterval(3600)
        ))
        let transport = HealthControllerTransport(now: clock.now)
        self.transport = transport
        self.coordinator = DocketBrowserPolicyCoordinator(
            transport: transport,
            credentials: credentialStore
        )
        self.runtime = BrowserNativeRuntime(store: nativeStore, coordinator: coordinator)
    }

    deinit {
        healthContinuation.finish()
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: suite)
    }

    func makeController() async -> TaskBrowserEnforcementController {
        await coordinator.poll(at: clock.now)
        return TaskBrowserEnforcementController(
            runtime: runtime,
            settingsStore: settingsStore,
            now: { self.clock.now },
            healthUpdates: healthUpdates
        )
    }

    func pulseHealthMonitor() {
        healthContinuation.yield(clock.now)
    }
}

@MainActor
final class ControllerClock {
    var now: Date

    init(now: Date) {
        self.now = now
    }
}

@MainActor
private final class HealthCredentialStore: AccountSecretStoring {
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

actor HealthControllerTransport: DocketMCPTransporting {
    let now: Date
    private var unavailable = false

    init(now: Date) {
        self.now = now
    }

    func setUnavailable(_ unavailable: Bool) {
        self.unavailable = unavailable
    }

    func readActiveWork(accessToken _: String) throws -> DocketActiveWork {
        if unavailable {
            throw DocketClientError.unavailable
        }
        return .init(
            observedAt: now,
            tracking: .paused,
            recordID: "record-health",
            task: .init(
                id: "task-health",
                organizationID: "org-health",
                title: "Monitor task browser health",
                description: nil,
                stateType: "started",
                workspace: .init(id: "workspace-health", name: "Health"),
                project: nil,
                labels: [],
                references: []
            )
        )
    }

    func readTaskState(
        organizationID _: String,
        taskID _: String,
        accessToken _: String
    ) throws -> DocketTaskStateObservation {
        throw DocketClientError.unavailable
    }

    func reviewDestination(
        _: DocketDestinationReviewInput,
        accessToken _: String
    ) throws -> DocketDestinationReview {
        .deny(reason: "Not used by this test.")
    }
}
