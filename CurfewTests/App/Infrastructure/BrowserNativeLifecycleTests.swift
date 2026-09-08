@testable import Curfew
import Foundation
import Testing

@MainActor
struct BrowserNativeLifecycleTests {
    @Test func uninstallRevokesAWaitingHostAndPreservesOtherFlavor() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let executable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/studio.hypertext.curfew.browser")
        let id = BrowserNativeInstallation.developmentExtensionID
        let other: CurfewFlavor = CurfewFlavor.current == .development ? .production : .development
        let otherManifest = try BrowserNativeInstallation.install(
            extensionID: id,
            executable: executable,
            home: home,
            flavor: other
        )
        let otherData = try Data(contentsOf: otherManifest)
        _ = try BrowserNativeInstallation.install(
            extensionID: id,
            executable: executable,
            home: home
        )
        let directory = BrowserNativeInstallation.browserDirectory(home: home, flavor: .current)
        let store = BrowserNativeStore(directory: directory)
        let request = try BrowserNativeRequest.decode(Data("""
        {"schemaVersion":"browser-host/1","requestId":"live","type":"review_destination",
        "sessionId":"00000000-0000-0000-0000-000000000001",
        "destination":{"origin":"https://example.com","path":"/"},"justification":"test"}
        """.utf8))
        let host = BrowserNativeHost(store: store, callerOrigin: "test", reviewTimeout: 0.15)
        let waiting = Task { await host.handle(request) }
        for _ in 0 ..< 100 {
            if try !store.pending(at: Date()).isEmpty {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try store.pending(at: Date()).count == 1)
        let outcome = UninstallCoordinator.performUninstall(
            home: home,
            defaultsSuiteName: "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        )
        #expect(outcome.allSucceeded)
        let response = await waiting.value
        #expect(response.error == "host_unavailable")
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        #expect(try Data(contentsOf: otherManifest) == otherData)
        let otherStore = BrowserNativeStore(directory: BrowserNativeInstallation.browserDirectory(
            home: home,
            flavor: other
        ))
        #expect(try otherStore.isActive())
    }

    @Test func failedFirstPollPreservesSignedPolicyAcrossRuntimeRestart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserNativeStore(directory: directory)
        try store.activate()
        let now = Date(timeIntervalSince1970: 1_788_537_600)
        let policy = BrowserPolicySnapshot(
            schemaVersion: "browser-policy/1", sessionID: UUID(),
            task: .init(id: "task", title: "Finish the task"), tracking: .running,
            scopes: [], grants: [], breakEndsAt: nil,
            connectionIsHealthy: false, generatedAt: now
        )
        try store.writePolicy(policy, at: now)
        let runtime = BrowserNativeRuntime(
            store: store,
            coordinator: DocketBrowserPolicyCoordinator(
                credentials: DocketCredentialStore(secretStore: EmptyBrowserCredentials())
            )
        )
        await runtime.coordinator.poll(at: now)
        let host = BrowserNativeHost(store: store, callerOrigin: "test")
        let request = try BrowserNativeRequest.decode(Data(
            #"{"schemaVersion":"browser-host/1","requestId":"restart","type":"get_policy"}"#.utf8
        ))
        let response = await host.handle(request)
        #expect(response.policy?.sessionID == policy.sessionID)
        #expect(response.policy?.connectionIsHealthy == false)
    }

    @Test func stoppedRuntimeDoesNotRecreateUninstalledState() async {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = BrowserNativeRuntime(store: BrowserNativeStore(directory: directory))
        runtime.stop()
        await runtime.processPending()
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func disablingEnforcementClearsAndReenablingRestoresTheRetainedPolicy() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserNativeStore(directory: directory)
        try store.activate()
        let now = Date(timeIntervalSince1970: 1_788_537_600)
        let credentials = DocketCredentialStore(secretStore: FixedBrowserCredentials(now: now))
        let coordinator = DocketBrowserPolicyCoordinator(
            transport: ActiveBrowserTransport(now: now),
            credentials: credentials
        )
        let runtime = BrowserNativeRuntime(store: store, coordinator: coordinator)
        try runtime.setEnforcementEnabled(true, at: now)
        await coordinator.poll(at: now)
        let sessionID = try #require(try store.readPolicy()?.policy?.sessionID)

        try runtime.setEnforcementEnabled(false, at: now.addingTimeInterval(1))
        #expect(try store.readPolicy()?.policy == nil)

        try runtime.setEnforcementEnabled(true, at: now.addingTimeInterval(2))
        #expect(try store.readPolicy()?.policy?.sessionID == sessionID)
    }

    @Test func disabledEnforcementStaysClearedAfterAQueuedReview() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserNativeStore(directory: directory)
        try store.activate()
        let now = Date()
        let coordinator = DocketBrowserPolicyCoordinator(
            transport: ActiveBrowserTransport(now: now),
            credentials: DocketCredentialStore(secretStore: FixedBrowserCredentials(now: now))
        )
        let runtime = BrowserNativeRuntime(store: store, coordinator: coordinator)
        await coordinator.poll(at: now)
        let sessionID = try #require(coordinator.policy(at: now)?.sessionID)
        let request = try BrowserNativeRequest.decode(Data("""
        {"schemaVersion":"browser-host/1","requestId":"disabled","type":"review_destination",
        "sessionId":"\(sessionID.uuidString)","destination":{"origin":"https://example.com",
        "path":"/"},"justification":"review while disabled"}
        """.utf8))
        _ = try store.enqueue(request, at: now)
        try runtime.setEnforcementEnabled(false, at: now)

        await runtime.processPending()

        #expect(try store.readPolicy()?.policy == nil)
    }

    @Test func uninstallRemovesBrowserManifestAndSignedState() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        let executable = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources/studio.hypertext.curfew.browser")
        let manifest = try BrowserNativeInstallation.install(
            extensionID: BrowserNativeInstallation.developmentExtensionID,
            executable: executable,
            home: home
        )
        let directory = home
            .appendingPathComponent(
                "Library/Application Support/Curfew\(CurfewFlavor.current.displaySuffix)/browser"
            )
        let store = BrowserNativeStore(directory: directory)
        try store.activate()
        try store.writePolicy(nil, at: Date())
        let outcome = UninstallCoordinator.performUninstall(
            home: home, defaultsSuiteName: "studio.hypertext.curfew.tests.\(UUID().uuidString)"
        )
        #expect(outcome.allSucceeded)
        #expect(!FileManager.default.fileExists(atPath: manifest.path))
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func queuedReviewGetsResolvedWithoutPersistingPrivateAnswers() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserNativeStore(directory: directory)
        try store.activate()
        let data = Data("""
        {"schemaVersion":"browser-host/1","requestId":"one","type":"review_destination",
        "sessionId":"00000000-0000-0000-0000-000000000001",
        "destination":{"origin":"https://example.com","path":"/private"},"justification":"private"}
        """.utf8)
        let id = try store.enqueue(BrowserNativeRequest.decode(data), at: Date())
        let runtime = BrowserNativeRuntime(
            store: store,
            coordinator: DocketBrowserPolicyCoordinator()
        )
        await runtime.processPending()
        let entry = try #require(try store.response(id: id))
        #expect(entry.result?.decision == "deny")
        #expect(entry.request.justification == nil)
        #expect(entry.request.challengeAnswer == nil)
    }
}

@MainActor
private final class EmptyBrowserCredentials: AccountSecretStoring {
    func data(for _: String) throws -> Data? {
        nil
    }

    func save(_: Data, for _: String) throws {}
    func delete(_: String) throws {}
}

@MainActor
private final class FixedBrowserCredentials: AccountSecretStoring {
    private var values: [String: Data]

    init(now: Date) {
        self.values = [
            DocketCredentialStore.accessTokenAccount: Data("access".utf8),
            DocketCredentialStore.refreshTokenAccount: Data("refresh".utf8),
            DocketCredentialStore.expirationAccount: Data(
                String(now.addingTimeInterval(3600).timeIntervalSince1970).utf8
            )
        ]
    }

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

private actor ActiveBrowserTransport: DocketMCPTransporting {
    let now: Date

    init(now: Date) {
        self.now = now
    }

    func readActiveWork(accessToken _: String) async throws -> DocketActiveWork {
        DocketActiveWork(
            observedAt: now,
            tracking: .running,
            recordID: "record-1",
            task: .init(
                id: "task-lvbt",
                organizationID: "org-lvbt",
                title: "Complete LVBT social strategy",
                description: nil,
                stateType: "started",
                workspace: .init(id: "workspace-lvbt", name: "LVBT"),
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
