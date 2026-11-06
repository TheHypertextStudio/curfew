@testable import curfew_ctl
import CurfewKit
import Foundation
import Testing

struct RequestCommandTests {
    @Test("Submission reports the result from the same queue it changed")
    func submittedQueueResult() throws {
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        settings.mcpEnabled = true
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = directory.appendingPathComponent("requests.json")
        let request = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        var result: [String: Any] = [:]
        try submitCLIRequest(
            request,
            json: true,
            settings: settings,
            queueURL: queue,
            sign: { _ in "test-signature" },
            emit: { value, _ in result = value }
        )
        #expect(result["request_id"] as? String == request.id.uuidString)
        #expect(result["status"] as? String == "pending")
        #expect(try MCPRequestQueue.loadChecked(from: queue).count == 1)
    }

    @Test("Extension requests preserve the existing wire tool and reason")
    func extensionRequest() throws {
        let command = try ExtensionCommand.parse(["--reason", "Finish saving my work", "--json"])
        let request = try command.makeRequest()
        #expect(request.tool == .requestExtension)
        #expect(request.status == .pending)
        let object = try JSONSerialization
            .jsonObject(with: Data(request.argumentsJSON.utf8)) as? [String: String]
        #expect(object?["reason"] == "Finish saving my work")
    }

    @Test("An empty extension reason cannot be queued")
    func emptyReason() {
        #expect(throws: (any Error).self) { _ = try ExtensionCommand.parse(["--reason", "  "]) }
    }

    @Test("Request results distinguish pending, denial, and missing records")
    func results() {
        var request = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        #expect(RequestStatusCommand
            .result(id: request.id, requests: [request])["status"] as? String == "pending")
        request.status = .denied
        request.denialReason = "Budget exhausted"
        let denied = RequestStatusCommand.result(id: request.id, requests: [request])
        #expect(denied["status"] as? String == "denied")
        #expect(denied["denial_reason"] as? String == "Budget exhausted")
        #expect(RequestStatusCommand
            .result(id: UUID(), requests: [request])["status"] as? String == "not_found")
    }

    @Test("Corrupt request files fail instead of masquerading as no requests")
    func corruptRequests() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("bad json".utf8).write(to: url)
        #expect(throws: (any Error).self) { _ = try MCPRequestQueue.loadChecked(from: url) }
    }

    @Test("Retrying the same request ID never creates another grant request")
    func idempotentSubmission() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("requests.json")
        let request = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        try MCPRequestQueue.append(request, to: url)
        try MCPRequestQueue.append(request, to: url)
        #expect(try MCPRequestQueue.loadChecked(from: url).count == 1)
        let conflicting = MCPPendingRequest(id: request.id, tool: .setSchedule, argumentsJSON: "{}")
        #expect(throws: (any Error).self) { try MCPRequestQueue.append(conflicting, to: url) }
    }

    @Test("Request mutations reject a symlinked sidecar lock")
    func unsafeLock() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = directory.appendingPathComponent("requests.json")
        let target = directory.appendingPathComponent("unrelated")
        try Data("preserve".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: queue.appendingPathExtension("lock"),
            withDestinationURL: target
        )
        #expect(throws: (any Error).self) {
            try MCPRequestQueue.append(
                MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}"),
                to: queue
            )
        }
        #expect(!FileManager.default.fileExists(atPath: queue.path))
        #expect(try String(contentsOf: target, encoding: .utf8) == "preserve")
    }

    @Test("An oversized append preserves the readable request queue")
    func oversizedRequest() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = directory.appendingPathComponent("requests.json")
        let original = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        try MCPRequestQueue.append(original, to: queue)
        let before = try Data(contentsOf: queue)
        let oversized = MCPPendingRequest(
            tool: .requestExtension,
            argumentsJSON: String(repeating: "x", count: 16 * 1024 * 1024)
        )
        #expect(throws: (any Error).self) { try MCPRequestQueue.append(oversized, to: queue) }
        #expect(try Data(contentsOf: queue) == before)
        #expect(try MCPRequestQueue.loadChecked(from: queue).map(\.id) == [original.id])
    }

    @Test("Disabled integrations reject requests before signing or queue mutation")
    func disabledIntegrations() throws {
        var settings = CurfewSettings.default
        settings.hasCompletedInitialSetup = true
        settings.mcpEnabled = false
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = directory.appendingPathComponent("requests.json")
        var signingCalls = 0
        let request = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        #expect(throws: (any Error).self) {
            try submitCLIRequest(
                request,
                json: true,
                settings: settings,
                queueURL: queue,
                sign: { _ in
                    signingCalls += 1
                    return nil
                }
            )
        }
        #expect(signingCalls == 0)
        #expect(!FileManager.default.fileExists(atPath: queue.path))
    }
}
