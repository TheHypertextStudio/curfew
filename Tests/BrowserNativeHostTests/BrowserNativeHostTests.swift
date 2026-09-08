@testable import CurfewKit
import Foundation
import Testing

struct BrowserNativeHostTests {
    @Test func liveHostCannotRecreateStateAfterUninstall() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserNativeStore(directory: directory)
        try store.activate()
        let host = BrowserNativeHost(store: store, callerOrigin: "test", reviewTimeout: 0.15)
        let review = try request(type: "review_destination")
        let waiting = Task { await host.handle(review) }
        for _ in 0 ..< 100 {
            if try !store.pending(at: Date()).isEmpty {
                break
            }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(try store.pending(at: Date()).count == 1)
        try store.deactivate()
        try FileManager.default.removeItem(at: directory)
        let result = await waiting.value
        #expect(result.error == "host_unavailable")
        #expect(try await host.handle(request(type: "heartbeat")).error == "host_unavailable")
        #expect(await host.handle(review).error == "host_unavailable")
        #expect(!FileManager.default.fileExists(atPath: directory.path))
        try store.activate()
        #expect(try await host.handle(request(type: "heartbeat")).error == nil)
    }

    @Test func revokedMarkerBlocksEveryMutationWithoutCreatingFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserNativeStore(directory: directory)
        try store.activate()
        let id = try store.enqueue(request(type: "review_destination"), at: Date())
        try store.deactivate()
        let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(throws: (any Error).self) { try store.recordHeartbeat(origin: "test", at: Date()) }
        #expect(throws: (any Error).self) { try store.enqueue(
            request(type: "review_destination"),
            at: Date()
        ) }
        #expect(throws: (any Error).self) { try store.resolve(
            id: id,
            result: .init(decision: "deny", reason: "timeout"),
            at: Date()
        ) }
        #expect(throws: (any Error).self) { try store.writePolicy(nil, at: Date()) }
        #expect(throws: (any Error).self) { try store.prune(at: Date()) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .sorted() == before)
        try FileManager.default.removeItem(at: directory)
        #expect(throws: (any Error).self) { try store.recordHeartbeat(origin: "test", at: Date()) }
        #expect(throws: (any Error).self) { try store.enqueue(
            request(type: "review_destination"),
            at: Date()
        ) }
        #expect(throws: (any Error).self) { try store.resolve(
            id: id,
            result: .init(decision: "deny", reason: "timeout"),
            at: Date()
        ) }
        #expect(throws: (any Error).self) { try store.writePolicy(nil, at: Date()) }
        #expect(throws: (any Error).self) { try store.prune(at: Date()) }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func policyReadsWithoutAppAndHeartbeatRecordsCaller() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserNativeStore(directory: directory)
        try store.activate()
        let origin = try BrowserNativeInstallation
            .origin(extensionID: BrowserNativeInstallation.developmentExtensionID)
        let host = BrowserNativeHost(store: store, callerOrigin: origin)
        let now = Date()
        try store.writePolicy(nil, at: now)
        let policy = try await host.handle(request(type: "get_policy"))
        #expect(policy.requestID == "caller")
        #expect(policy.error == nil)
        #expect(policy.policy == nil)
        let heartbeat = try await host.handle(request(type: "heartbeat"))
        #expect(heartbeat.requestID == "caller")
        #expect(try store.health(at: Date()).extensionOrigin == origin)
    }

    @Test func hostWaitsForScrubbedResultAndBoundsTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserNativeStore(directory: directory)
        try store.activate()
        let host = BrowserNativeHost(store: store, callerOrigin: "test", reviewTimeout: 0.05)
        let response = try await host.handle(request(type: "review_destination"))
        #expect(response.requestID == "caller")
        #expect(response.error == "review_timeout")
        #expect(try store.pending(at: Date()).isEmpty)
    }

    private func request(type: String) throws -> BrowserNativeRequest {
        var object: [String: Any] = [
            "schemaVersion": "browser-host/1",
            "requestId": "caller",
            "type": type
        ]
        if type == "review_destination" {
            object["sessionId"] = UUID().uuidString
            object["destination"] = ["origin": "https://example.com", "path": "/private"]
            object["justification"] = "I need a reference."
        }
        return try BrowserNativeRequest.decode(JSONSerialization.data(withJSONObject: object))
    }
}
