@testable import Curfew
import Foundation
import Testing

/// Behaviour tests for ``ProtectedWorkStore``. Every test drives a temporary
/// file so the suite never touches the real Application Support directory.
struct ProtectedWorkStoreTests {
    private func makeStore() -> (ProtectedWorkStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent("protected-work.json")
        return (ProtectedWorkStore(recordURL: url), directory)
    }

    @Test("A claim makes work active and grants the requested lease")
    func claimMakesWorkActive() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date()
        let claim = try store.claim(
            label: "delegate: build athena",
            source: .cli,
            leaseMinutes: 5,
            now: now,
            policy: .default
        )

        #expect(store.hasActiveWork(now: now))
        #expect(claim.expiresAt == now.addingTimeInterval(5 * 60))
        #expect(store.activeClaims(now: now).map(\.id) == [claim.id])
    }

    @Test("An unrenewed claim lapses on its own")
    func claimExpires() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date()
        try store.claim(
            label: "agent turn",
            source: .mcp,
            leaseMinutes: 1,
            now: now,
            policy: .default
        )

        #expect(store.hasActiveWork(now: now.addingTimeInterval(59)))
        #expect(!store.hasActiveWork(now: now.addingTimeInterval(61)))
    }

    @Test("Renewing by id moves the expiry and keeps the original start")
    func renewalExtendsWithoutDuplicating() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Whole-second date on purpose: the store persists ISO 8601 without
        // fractional seconds, so a `Date()` here would come back from disk
        // truncated and the equality below would be testing the formatter
        // rather than the renewal.
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = try store.claim(
            label: "long job",
            source: .cli,
            leaseMinutes: 5,
            now: start,
            policy: .default
        )

        let renewAt = start.addingTimeInterval(120)
        let renewed = try store.claim(
            id: first.id,
            label: "long job",
            source: .cli,
            leaseMinutes: 5,
            now: renewAt,
            policy: .default
        )

        #expect(renewed.id == first.id)
        #expect(renewed.startedAt == first.startedAt)
        #expect(renewed.expiresAt == renewAt.addingTimeInterval(5 * 60))
        #expect(store.activeClaims(now: renewAt).count == 1)
    }

    @Test("A lease longer than the ceiling is clamped, not honored")
    func leaseIsClamped() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date()
        let claim = try store.claim(
            label: "greedy",
            source: .mcp,
            leaseMinutes: 10000,
            now: now,
            policy: .default
        )
        let ceiling = TimeInterval(ProtectedWorkPolicy.leaseCeilingMinutes * 60)
        #expect(claim.expiresAt == now.addingTimeInterval(ceiling))
    }

    @Test("Releasing drops the claim immediately")
    func releaseDropsTheClaim() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date()
        let claim = try store.claim(
            label: "done early",
            source: .mcp,
            now: now,
            policy: .default
        )
        try store.release(id: claim.id)
        #expect(!store.hasActiveWork(now: now))
    }

    @Test("Expired claims are pruned on the next write")
    func expiredClaimsArePruned() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let start = Date()
        try store.claim(label: "old", source: .cli, leaseMinutes: 1, now: start, policy: .default)
        try store.claim(
            label: "new",
            source: .cli,
            leaseMinutes: 5,
            now: start.addingTimeInterval(600),
            policy: .default
        )
        #expect(store.load().count == 1)
        #expect(store.load().first?.label == "new")
    }

    @Test("A missing or corrupt file means no protection, never protection by accident")
    func unreadableFileFailsClosed() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(!store.hasActiveWork(now: Date()))

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.recordURL)
        #expect(!store.hasActiveWork(now: Date()))
    }

    @Test("The claims file is not world-readable")
    func claimsFileIsOwnerOnly() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.claim(label: "secret job name", source: .cli, now: Date(), policy: .default)
        let attributes = try FileManager.default.attributesOfItem(atPath: store.recordURL.path)
        let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
        #expect(permissions.int16Value == 0o600)
    }
}
