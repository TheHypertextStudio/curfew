@testable import Curfew
import Foundation
import Testing

/// Behaviour tests for the break-glass emergency release.
///
/// The release is the only way out of a `/sbin/shutdown -h +1` the daemon has
/// already issued, so these tests care about two things: that a genuine
/// release is honored without any dependency on the locked display, and that
/// a stale, forged, or lazily-reasoned one is not.
struct BreakGlassStoreTests {
    private func makeStore() -> (BreakGlassStore, URL) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = BreakGlassStore(
            recordURL: directory.appendingPathComponent("break-glass.json"),
            secretURL: directory.appendingPathComponent(".break-glass-secret")
        )
        return (store, directory)
    }

    private let goodReason = "daemon shut the mac down mid agent run"

    @Test("A signed release is honored")
    func issuedReleaseIsActive() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date()
        let release = try store.issue(reason: goodReason, issuedBy: "willie@mac", now: now)
        #expect(release.signature != nil)

        let active = try #require(store.activeRelease(now: now.addingTimeInterval(30)))
        #expect(active.id == release.id)
        #expect(active.reason == goodReason)
    }

    @Test("A thin reason is refused before anything is written")
    func shortReasonIsRefused() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: BreakGlassError.reasonTooShort(
            minimum: BreakGlassStore.minimumReasonCharacters
        )) {
            try store.issue(reason: "oops", issuedBy: "willie@mac", now: Date())
        }
        #expect(!FileManager.default.fileExists(atPath: store.recordURL.path))
    }

    @Test("A tampered record does not verify")
    func tamperedRecordIsRejected() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date()
        try store.issue(reason: goodReason, issuedBy: "willie@mac", now: now)

        var forged = try #require(store.load())
        forged.signature = String(repeating: "ab", count: 32)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(forged).write(to: store.recordURL, options: .atomic)

        #expect(store.activeRelease(now: now) == nil)
    }

    @Test("An unsigned record hand-written to disk is ignored")
    func unsignedRecordIsIgnored() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let now = Date()
        let unsigned = BreakGlassRelease(
            issuedAt: now,
            reason: goodReason,
            issuedBy: "someone@somewhere"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(unsigned).write(to: store.recordURL, options: .atomic)

        #expect(store.activeRelease(now: now) == nil)
    }

    @Test("A release from an earlier lockout does not cover tonight")
    func releaseIsScopedToItsWindow() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Two hours, not twenty: the record must still be inside
        // `defaultValidity`, or this would pass on the aging rule alone and
        // prove nothing about window scoping.
        let earlierWindow = Date()
        try store.issue(reason: goodReason, issuedBy: "willie@mac", now: earlierWindow)

        let tonightStarted = earlierWindow.addingTimeInterval(2 * 60 * 60)
        let now = tonightStarted.addingTimeInterval(60)
        #expect(store.activeRelease(now: now) != nil)
        #expect(store.activeRelease(now: now, issuedAfter: tonightStarted) == nil)
    }

    @Test("A forgotten release ages out even with no window to compare against")
    func releaseAgesOut() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let issued = Date()
        try store.issue(reason: goodReason, issuedBy: "willie@mac", now: issued)

        let later = issued.addingTimeInterval(BreakGlassStore.defaultValidity + 60)
        #expect(store.activeRelease(now: later) == nil)
    }

    @Test("A future-dated record is ignored")
    func futureDatedRecordIsIgnored() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let future = Date().addingTimeInterval(3600)
        try store.issue(reason: goodReason, issuedBy: "willie@mac", now: future)
        #expect(store.activeRelease(now: Date()) == nil)
    }

    @Test("Revoking removes the release")
    func clearRemovesTheRelease() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date()
        try store.issue(reason: goodReason, issuedBy: "willie@mac", now: now)
        store.clear()
        #expect(store.activeRelease(now: now) == nil)
        #expect(store.load() == nil)
    }

    @Test("The release and its key are not world-readable")
    func filesAreOwnerOnly() throws {
        let (store, directory) = makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }

        try store.issue(reason: goodReason, issuedBy: "willie@mac", now: Date())
        for path in [store.recordURL.path, store.secretURL.path] {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
            #expect(permissions.int16Value == 0o600)
        }
    }
}
