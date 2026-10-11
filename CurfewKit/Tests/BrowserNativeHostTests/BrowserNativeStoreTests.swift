@testable import CurfewKit
import Foundation
import Testing

struct BrowserNativeStoreTests {
    private let now = Date(timeIntervalSince1970: 1_788_537_600)

    @Test func oversizedDestinationCannotPoisonAnExistingQueue() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowserNativeStore(directory: root)
        try store.activate()
        let id = try store.enqueue(reviewRequest(), at: now)
        let before = try Data(contentsOf: store.queueURL)
        let oversized = try BrowserNativeJSON.decode(
            BrowserNativeRequest.self,
            from: sizedRequest(bytes: 4 * 1024 * 1024)
        )
        #expect(throws: (any Error).self) { try store.enqueue(oversized, at: now) }
        #expect(try Data(contentsOf: store.queueURL) == before)
        #expect(try store.pending(at: now).map(\.id) == [id])
    }

    @Test func oversizedSignedResponseLeavesPriorQueueUnchanged() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowserNativeStore(directory: root)
        try store.activate()
        let id = try store.enqueue(reviewRequest(), at: now)
        let before = try Data(contentsOf: store.queueURL)
        let result = BrowserNativeReviewResult(
            decision: "deny",
            reason: String(repeating: "x", count: 4 * 1024 * 1024)
        )
        #expect(throws: (any Error).self) { try store.resolve(id: id, result: result, at: now) }
        #expect(try Data(contentsOf: store.queueURL) == before)
        #expect(try store.pending(at: now).map(\.id) == [id])
    }

    @Test func completeSignedRecordAcceptsItsLastFittingSize() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowserNativeStore(directory: root)
        try store.activate()
        let id = try store.enqueue(reviewRequest(), at: now)
        var entry = try #require(try store.pending(at: now).first)
        entry.request.justification = nil
        entry.request.challengeAnswer = nil
        entry.resolvedAt = now
        func recordSize(reasonBytes: Int) throws -> Int {
            entry.result = .init(
                decision: "deny",
                reason: String(repeating: "x", count: reasonBytes)
            )
            return try BrowserNativeJSON.encode(SignedSizeProbe(
                payload: BrowserNativeJSON.encode([entry]), signature: Data(repeating: 0, count: 32)
            )).count
        }
        let limit = BrowserNativeStore.maximumRecordBytes
        var lastFitting = try (limit - recordSize(reasonBytes: 0)) * 3 / 4
        while try recordSize(reasonBytes: lastFitting) > limit {
            lastFitting -= 1
        }
        while try recordSize(reasonBytes: lastFitting + 1) <= limit {
            lastFitting += 1
        }
        let before = try Data(contentsOf: store.queueURL)
        #expect(throws: BrowserNativeError.messageTooLarge) {
            try store.resolve(
                id: id,
                result: .init(decision: "deny", reason: String(
                    repeating: "x",
                    count: lastFitting + 1
                )),
                at: now
            )
        }
        #expect(try Data(contentsOf: store.queueURL) == before)
        try store.resolve(
            id: id,
            result: .init(decision: "deny", reason: String(repeating: "x", count: lastFitting)),
            at: now
        )
        let size = try Data(contentsOf: store.queueURL).count
        #expect(size <= limit && size > limit - 4)
        #expect(try store.response(id: id)?.result?.reason.count == lastFitting)
    }

    @Test(arguments: [false, true])
    func requestByteBoundaryAndMaximumQueueStayReadable(unicodeAnswers: Bool) throws {
        let maximum = 20 * 1024
        let request = try BrowserNativeRequest.decode(sizedRequest(
            bytes: maximum,
            unicodeAnswers: unicodeAnswers
        ))
        #expect(throws: (any Error).self) {
            try BrowserNativeRequest.decode(sizedRequest(bytes: maximum + 1))
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowserNativeStore(directory: root)
        try store.activate()
        for _ in 0 ..< 128 {
            _ = try store.enqueue(request, at: now)
        }
        #expect(try Data(contentsOf: store.queueURL).count < 4 * 1024 * 1024)
        #expect(try store.pending(at: now).count == 128)
        #expect(throws: BrowserNativeError.queueFull) { try store.enqueue(request, at: now) }
    }

    private func sizedRequest(bytes: Int, unicodeAnswers: Bool = false) throws -> Data {
        var object: [String: Any] = [
            "schemaVersion": "browser-host/1", "requestId": "size", "type": "review_destination",
            "sessionId": "00000000-0000-0000-0000-000000000001",
            "destination": ["origin": "https://example.com", "path": "/"],
            "justification": "I need this task reference."
        ]
        if unicodeAnswers {
            object["justification"] = String(repeating: "\u{FFFF}", count: 1000)
            object["challengeAnswer"] = String(repeating: "\u{FFFF}", count: 1000)
        }
        let base = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).count
        object["destination"] = [
            "origin": "https://example.com",
            "path": "/" + String(repeating: "x", count: bytes - base)
        ]
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    @Test func signedQueueScrubsSecretsBeforePublishingResolutionAndPrunes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = BrowserNativeStore(directory: root)
        try store.activate()
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
        try store.activate()
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
        try store.activate()
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

private struct SignedSizeProbe: Encodable {
    let payload: Data
    let signature: Data
}
