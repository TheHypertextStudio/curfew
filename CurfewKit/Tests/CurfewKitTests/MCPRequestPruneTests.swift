@testable import CurfewKit
import Darwin
import Foundation
import Testing

struct MCPRequestPruneTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Preview changes no files and selects only old completed unprotected records")
    func preview() throws {
        try withQueue { url in
            let old = resolved(daysAgo: 60)
            let denied = resolved(daysAgo: 50, status: .denied)
            let protected = resolved(daysAgo: 70)
            let recent = resolved(daysAgo: 5)
            var pending = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
            pending.resolvedAt = now.addingTimeInterval(-100 * 86400)
            var undated = resolved(daysAgo: 90)
            undated.resolvedAt = nil
            try append([old, denied, protected, recent, pending, undated], to: url)
            let before = try Data(contentsOf: url)
            let plan = try MCPRequestQueue.previewResolvedPrune(
                before: now.addingTimeInterval(-30 * 86400), from: url,
                protectedRequestIDs: { [protected.id] }
            )
            #expect(Set(plan.candidateIDs) == [old.id, denied.id])
            #expect(plan.pendingCount == 1)
            #expect(plan.protectedResolvedCount == 1)
            #expect(try Data(contentsOf: url) == before)
        }
    }

    @Test("A preview with unavailable authority creates no parent or sidecar lock")
    func unavailablePreview() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: (any Error).self) {
            _ = try MCPRequestQueue.previewResolvedPrune(
                before: nil, from: directory.appendingPathComponent("queue.json"),
                protectedRequestIDs: { throw CocoaError(.fileNoSuchFile) }
            )
        }
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("Apply reloads grant protection inside the queue lock and never removes pending records")
    func freshProtectionInsideLock() throws {
        try withQueue { url in
            let old = resolved(daysAgo: 60)
            let protected = resolved(daysAgo: 70)
            let pending = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
            try append([old, protected, pending], to: url)
            let plan = try MCPRequestQueue.previewResolvedPrune(
                before: nil, from: url, protectedRequestIDs: { [] }
            )
            var readUnderLock = false
            let result = try MCPRequestQueue.pruneResolved(plan, protectedRequestIDs: {
                let descriptor = open(url.appendingPathExtension("lock").path, O_RDWR | O_CLOEXEC)
                guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
                defer { close(descriptor) }
                let acquired = flock(descriptor, LOCK_EX | LOCK_NB)
                readUnderLock = acquired != 0 && (errno == EWOULDBLOCK || errno == EAGAIN)
                if acquired == 0 {
                    flock(descriptor, LOCK_UN)
                }
                return [protected.id]
            })
            #expect(readUnderLock)
            #expect(result.removedIDs == [old.id])
            let retained = try MCPRequestQueue.loadChecked(from: url)
            #expect(retained.map(\.id) == [protected.id, pending.id])
            #expect(retained.first == protected)
        }
    }

    @Test("Apply cannot expand a confirmed preview or remove a record that changed afterward")
    func confirmedSnapshot() throws {
        try withQueue { url in
            let unchanged = resolved(daysAgo: 50)
            var changed = resolved(daysAgo: 60, status: .denied)
            try append([unchanged, changed], to: url)
            let plan = try MCPRequestQueue.previewResolvedPrune(
                before: nil, from: url, protectedRequestIDs: { [] }
            )
            changed.denialReason = "Keep this updated outcome."
            try MCPRequestQueue.update(changed, to: url)
            let added = resolved(daysAgo: 90)
            try MCPRequestQueue.append(added, to: url)
            let result = try MCPRequestQueue.pruneResolved(plan, protectedRequestIDs: { [] })
            #expect(result.removedIDs == [unchanged.id])
            #expect(try MCPRequestQueue.loadChecked(from: url) == [changed, added])
        }
    }

    @Test("Cleanup rejects failed runtime reads without replacing the queue")
    func failedAuthority() throws {
        try withQueue { url in
            try MCPRequestQueue.append(resolved(daysAgo: 60), to: url)
            let plan = try MCPRequestQueue.previewResolvedPrune(
                before: nil, from: url, protectedRequestIDs: { [] }
            )
            let before = try Data(contentsOf: url)
            #expect(throws: (any Error).self) {
                _ = try MCPRequestQueue.pruneResolved(plan, protectedRequestIDs: {
                    throw CocoaError(.coderReadCorrupt)
                })
            }
            #expect(try Data(contentsOf: url) == before)
        }
    }

    @Test("Repeated cleanup preserves bytes and modification time after the selected IDs are gone")
    func repeatedApply() throws {
        try withQueue { url in
            let old = resolved(daysAgo: 60)
            let pending = MCPPendingRequest(tool: .requestExtension, argumentsJSON: "{}")
            try append([old, pending], to: url)
            let plan = try MCPRequestQueue.previewResolvedPrune(
                before: nil, from: url, protectedRequestIDs: { [] }
            )
            #expect(try MCPRequestQueue.pruneResolved(plan, protectedRequestIDs: { [] })
                .removedIDs == [old.id])
            let before = try Data(contentsOf: url)
            try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: url.path)
            #expect(try MCPRequestQueue.pruneResolved(plan, protectedRequestIDs: { [] }).removedIDs
                .isEmpty)
            #expect(try Data(contentsOf: url) == before)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            #expect(attributes[.modificationDate] as? Date == now)
        }
    }

    @Test("Runtime protection includes unacknowledged receipts and legacy grant IDs")
    func runtimeProtection() throws {
        let request = resolved(daysAgo: 60)
        let legacy = UUID()
        let store = EnforcementRuntimeStateStore()
        try store.save(EnforcementRuntimeState(
            dayToken: "2026-11-03", mcpGrantReceipts: [MCPGrantReceipt(
                request: request,
                appliedAt: now
            )],
            legacyMCPGrantRequestIDs: [legacy]
        ))
        #expect(try MCPRequestQueue.protectedGrantRequestIDs(from: store) == [request.id, legacy])
        #expect(throws: (any Error).self) {
            _ = try MCPRequestQueue.protectedGrantRequestIDs(from: EnforcementRuntimeStateStore())
        }
    }

    private func resolved(daysAgo: Int, status: MCPRequestStatus = .approved) -> MCPPendingRequest {
        let date = now.addingTimeInterval(TimeInterval(-daysAgo * 86400))
        var request = MCPPendingRequest(
            tool: .requestExtension,
            argumentsJSON: "{\"reason\":\"Private request text\"}",
            requestedAt: date.addingTimeInterval(-60),
            signature: "test-signature"
        )
        request.status = status
        request.resolvedAt = date
        request.denialReason = status == .denied ? "Private denied reason." : nil
        return request
    }

    private func append(_ requests: [MCPPendingRequest], to url: URL) throws {
        for request in requests {
            try MCPRequestQueue.append(request, to: url)
        }
    }

    private func withQueue(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("requests.json"))
    }
}
