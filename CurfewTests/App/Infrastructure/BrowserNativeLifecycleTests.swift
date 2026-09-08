@testable import Curfew
import Foundation
import Testing

@MainActor
struct BrowserNativeLifecycleTests {
    @Test func failedFirstPollPreservesSignedPolicyAcrossRuntimeRestart() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserNativeStore(directory: directory)
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
