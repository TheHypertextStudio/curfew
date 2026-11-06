@testable import CurfewKit
import Foundation
import Testing

struct MCPQueueAcknowledgementTests {
    @Test("An absent queue entry cannot acknowledge a committed grant")
    func absentEntry() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("queue.json")
        var request = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        request.status = .approved
        #expect(try !MCPRequestQueue.update(request, to: url))
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("Acknowledgement requires the same action and leaves conflicting bytes intact")
    func identityAndOutcome() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("queue.json")
        let original = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        try MCPRequestQueue.append(original, to: url)
        let before = try Data(contentsOf: url)
        var conflict = MCPPendingRequest(
            id: original.id,
            tool: .requestExtension,
            argumentsJSON: "changed"
        )
        conflict.status = .approved
        #expect(throws: (any Error).self) { try MCPRequestQueue.update(conflict, to: url) }
        #expect(try Data(contentsOf: url) == before)
        var approved = original
        approved.status = .approved
        approved.resolvedAt = Date()
        #expect(try MCPRequestQueue.update(approved, to: url))
        #expect(try MCPRequestQueue.loadChecked(from: url).first?.status == .approved)
    }
}
