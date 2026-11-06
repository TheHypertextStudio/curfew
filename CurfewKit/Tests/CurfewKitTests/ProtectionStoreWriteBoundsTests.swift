import CurfewKit
import Foundation
import Testing

struct ProtectionStoreWriteBoundsTests {
    @Test("An oversized release preserves the prior verified release")
    func oversizedReleasePreservesRecovery() throws {
        try withStoreDirectory { directory in
            let store = BreakGlassStore(
                recordURL: directory.appendingPathComponent("release.json"),
                secretURL: directory.appendingPathComponent("secret")
            )
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let release = try store.issue(
                reason: "Restore access after a failed build",
                issuedBy: "test",
                now: now
            )
            let original = try Data(contentsOf: store.recordURL)
            #expect(throws: (any Error).self) {
                _ = try store.issue(
                    reason: String(repeating: "🛠", count: 20000),
                    issuedBy: "test",
                    now: now
                )
            }
            #expect(try Data(contentsOf: store.recordURL) == original)
            #expect(store.activeRelease(now: now)?.id == release.id)
        }
    }

    @Test("An oversized renewal preserves a readable claim that can still be released")
    func oversizedRenewalPreservesClaim() throws {
        try withStoreDirectory { directory in
            let store = ProtectedWorkStore(recordURL: directory
                .appendingPathComponent("claims.json"))
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let claim = try store.claim(
                label: "Build release",
                source: .cli,
                now: now,
                policy: .default
            )
            let original = try Data(contentsOf: store.recordURL)
            #expect(throws: (any Error).self) {
                _ = try store.claim(
                    id: claim.id, label: String(repeating: "\"", count: 530_000),
                    source: .cli, now: now, policy: .default
                )
            }
            #expect(try Data(contentsOf: store.recordURL) == original)
            #expect(try store.loadThrowing() == [claim])
            try store.release(id: claim.id)
            #expect(try store.loadThrowing().isEmpty)
        }
    }

    @Test("The claims bound applies to the complete encoded collection")
    func oversizedCollectionPreservesClaims() throws {
        try withStoreDirectory { directory in
            let store = ProtectedWorkStore(recordURL: directory
                .appendingPathComponent("claims.json"))
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let label = String(repeating: "a", count: 530_000)
            let claim = try store.claim(label: label, source: .cli, now: now, policy: .default)
            let original = try Data(contentsOf: store.recordURL)
            #expect(throws: (any Error).self) {
                _ = try store.claim(label: label, source: .cli, now: now, policy: .default)
            }
            #expect(try Data(contentsOf: store.recordURL) == original)
            #expect(try store.loadThrowing() == [claim])
        }
    }
}

private func withStoreDirectory(_ body: (URL) throws -> Void) throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try body(directory)
}
