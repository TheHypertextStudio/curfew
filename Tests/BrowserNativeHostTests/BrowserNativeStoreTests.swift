@testable import CurfewKit
import Foundation
import Testing

struct BrowserNativeStoreTests {
    private let now = Date(timeIntervalSince1970: 1_788_537_600)

    @Test func signedQueueScrubsSecretsBeforePublishingResolutionAndPrunes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowserNativeStore(directory: root)
        let request = try reviewRequest()
        let id = try store.enqueue(request, at: now)
        #expect(try store.pending(at: now).count == 1)
        let result = BrowserNativeReviewResult(decision: "deny", reason: "Stay on task.")
        try store.resolve(id: id, result: result, at: now)
        #expect(try store.response(id: id)?.result == result)
        let signed = try #require(JSONSerialization
            .jsonObject(with: Data(contentsOf: store.queueURL)) as? [String: Any])
        let encodedPayload = try #require(signed["payload"] as? String)
        let payload = try #require(Data(base64Encoded: encodedPayload))
        let contents = try #require(String(data: payload, encoding: .utf8))
        #expect(!contents.contains("private justification"))
        #expect(!contents.contains("private answer"))
        #expect(try store.pending(at: now).isEmpty)
        try store.prune(at: now.addingTimeInterval(121))
        #expect(try store.response(id: id) == nil)
        for url in [store.queueURL, store.secretURL] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }

    @Test func queueRejectsTamperingAndStaleRequests() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowserNativeStore(directory: root)
        _ = try store.enqueue(reviewRequest(), at: now)
        #expect(try store.pending(at: now.addingTimeInterval(61)).isEmpty)
        var object = try #require(JSONSerialization
            .jsonObject(with: Data(contentsOf: store.queueURL)) as? [String: Any])
        object["signature"] = "forged"
        try JSONSerialization.data(withJSONObject: object).write(to: store.queueURL)
        #expect(throws: (any Error).self) { try store.pending(at: now) }
    }

    @Test func snapshotPreservesExpiryAndHeartbeatProvesBothProcesses() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowserNativeStore(directory: root)
        let origin = try BrowserDestinationScope.validatedOrigin("https://example.com")
        let policy = BrowserPolicySnapshot(
            schemaVersion: "browser-policy/1", sessionID: UUID(), task: .init(
                id: "task",
                title: "Task"
            ),
            tracking: .paused, scopes: [], grants: [.init(
                scope: origin,
                expiresAt: now.addingTimeInterval(30)
            )],
            breakEndsAt: now.addingTimeInterval(15), connectionIsHealthy: false, generatedAt: now
        )
        try store.writePolicy(policy, at: now)
        #expect(try store.readPolicy()?.policy == policy)
        let destination = try NormalizedHTTPDestination("https://example.com/private")
        #expect(try store.readPolicy()?.policy?
            .allows(destination, at: now.addingTimeInterval(31)) == false)
        try store.recordHeartbeat(
            origin: "chrome-extension://abcdefghijklmnopabcdefghijklmnop/",
            at: now
        )
        #expect(try store.health(at: now).isHealthy)
        #expect(try !store.health(at: now.addingTimeInterval(61)).isHealthy)
    }

    private func reviewRequest() throws -> BrowserNativeRequest {
        let json = """
        {"schemaVersion":"browser-host/1","requestId":"review-1","type":"review_destination",
         "sessionId":"00000000-0000-0000-0000-000000000001","destination":{"origin":"https://example.com","path":"/private"},
         "justification":"private justification","challengeAnswer":"private answer"}
        """
        return try BrowserNativeRequest.decode(Data(json.utf8))
    }
}
