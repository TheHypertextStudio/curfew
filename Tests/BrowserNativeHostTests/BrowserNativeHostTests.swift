@testable import CurfewKit
import Foundation
import Testing

struct BrowserNativeHostTests {
    @Test func policyReadsWithoutAppAndHeartbeatRecordsCaller() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserNativeStore(directory: directory)
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
