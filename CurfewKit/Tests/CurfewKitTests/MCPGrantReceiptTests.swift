@testable import CurfewKit
import Foundation
import Testing

struct MCPGrantReceiptTests {
    @Test("A post-commit error leaves the complete private receipt snapshot available to recovery")
    func uncertainCommit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("runtime.json")
        let request = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        let state = EnforcementRuntimeState(
            dayToken: "2026-11-03",
            extensionMinutes: 15,
            extensionUses: 1,
            mcpGrantReceipts: [MCPGrantReceipt(
                request: request,
                appliedAt: Date()
            )]
        )
        let store = EnforcementRuntimeStateStore(
            recordURL: url,
            afterPersist: {
                throw CocoaError(.fileWriteUnknown)
            }
        )
        #expect(throws: (any Error).self) { try store.save(state) }
        #expect(try EnforcementRuntimeStateStore(recordURL: url).load() == state)
        let mode = try FileManager.default
            .attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test("Legacy and invalid grants never enter the acknowledgement journal")
    func unsafePreparation() throws {
        let now = Date()
        let request = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
        let legacy = EnforcementRuntimeState(
            dayToken: "2026-11-03",
            mcpReceiptTrackingStartedAt: now,
            legacyMCPGrantRequestIDs: [request.id]
        )
        #expect(throws: (any Error).self) {
            try MCPGrantJournal.prepareExtension(
                request,
                state: legacy,
                proposal: MCPGrantProposal(minutes: 15, usedCount: 1, resetBoundary: now),
                appliedAt: now
            )
        }
        let tracked = EnforcementRuntimeState(
            dayToken: "2026-11-03",
            mcpReceiptTrackingStartedAt: now
        )
        #expect(throws: (any Error).self) {
            try MCPGrantJournal.prepareExtension(
                request,
                state: tracked,
                proposal: MCPGrantProposal(minutes: -1, usedCount: 1, resetBoundary: now),
                appliedAt: now
            )
        }
    }

    @Test("Multiple unacknowledged grants survive reload and replay without adding time")
    func multipleReceipts() throws {
        let now = Date()
        let first = MCPPendingRequest(
            tool: .requestExtension,
            argumentsJSON: #"{"reason":"first"}"#
        )
        let second = MCPPendingRequest(
            tool: .requestExtension,
            argumentsJSON: #"{"reason":"second"}"#
        )
        var state = EnforcementRuntimeState(
            dayToken: "2026-11-03",
            mcpReceiptTrackingStartedAt: now
        )
        for (index, request) in [first, second].enumerated() {
            let prepared = try MCPGrantJournal.prepareExtension(
                request,
                state: state,
                proposal: MCPGrantProposal(minutes: 15, usedCount: index + 1, resetBoundary: now),
                appliedAt: now
            )
            guard case .prepared(let updated) = prepared
            else { Issue.record("Expected a new grant."); return }
            state = updated
        }
        let store = EnforcementRuntimeStateStore()
        try store.save(state)
        let saved = try #require(try store.load())
        #expect(saved.mcpGrantReceipts?.count == 2)
        #expect(saved.extensionUses == 2)
        #expect(saved.extensionMinutes == 30)
        let replay = try MCPGrantJournal.prepareExtension(
            first,
            state: saved,
            proposal: MCPGrantProposal(minutes: 15, usedCount: 3, resetBoundary: now),
            appliedAt: now
        )
        guard case .replay(let receipt) = replay
        else { Issue.record("A committed request was reapplied."); return }
        #expect(receipt.matches(first))
        let conflict = MCPPendingRequest(
            id: first.id,
            tool: .requestExtension,
            argumentsJSON: "different"
        )
        #expect(throws: (any Error).self) { try MCPGrantJournal.receipt(for: conflict, in: saved) }
        #expect(try store.load() == saved)
    }

    @Test("Runtime persistence keeps unacknowledged request identities with grant counters")
    func receiptSurvivesReload() throws {
        let state = EnforcementRuntimeState(
            dayToken: "2026-11-03",
            extensionMinutes: 15,
            extensionUses: 1
        )
        let initialData = try JSONEncoder().encode(state)
        var object = try #require(try JSONSerialization
            .jsonObject(with: initialData) as? [String: Any])
        object["mcpGrantReceipts"] = [[
            "requestID": UUID().uuidString,
            "tool": "curfew.request_extension",
            "argumentsSHA256": String(repeating: "a", count: 64),
            "appliedAt": 1000.0
        ]]
        let decoded = try JSONDecoder().decode(
            EnforcementRuntimeState.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("runtime.json")
        try EnforcementRuntimeStateStore(recordURL: url).save(decoded)
        let reloaded = try #require(try EnforcementRuntimeStateStore(recordURL: url).load())
        let reloadedData = try JSONEncoder().encode(reloaded)
        let saved = try #require(try JSONSerialization
            .jsonObject(with: reloadedData) as? [String: Any])
        #expect((saved["mcpGrantReceipts"] as? [[String: Any]])?.count == 1)
        #expect(reloaded.extensionMinutes == 15)
        #expect(reloaded.extensionUses == 1)
    }

    @Test("An oversized runtime replacement preserves the previous readable snapshot")
    func oversizedSnapshotPreservesState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("runtime.json")
        let store = EnforcementRuntimeStateStore(recordURL: url)
        let original = EnforcementRuntimeState(dayToken: "2026-11-03", extensionUses: 1)
        try store.save(original)
        let before = try Data(contentsOf: url)
        let oversized = EnforcementRuntimeState(dayToken: String(repeating: "x", count: 65536))
        #expect(throws: (any Error).self) { try store.save(oversized) }
        #expect(try Data(contentsOf: url) == before)
        #expect(try store.load() == original)
    }
}
