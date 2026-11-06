@testable import curfew_ctl
import CurfewKit
import Darwin
import Foundation
import Testing

@Suite(.serialized)
struct PrivilegedBreakGlassOwnershipAcceptance {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["CURFEW_ROOT_OWNERSHIP_FIXTURE"] != nil))
    func realCredentialOwnership() throws {
        let user = try fixtureUser()
        let system = SystemBreakGlassCredentials()
        let original = try system.capture()
        #expect(original.uid == 0)
        let storage = BreakGlassUserStorage(user: user, credentials: system)
        let store = user.store(flavor: .production)
        defer { removeFixtureLibrary(user: user, storage: storage) }
        let parents = store.recordURL.deletingLastPathComponent().deletingLastPathComponent()
        try storage.perform {
            try FileManager.default.createDirectory(at: parents, withIntermediateDirectories: true)
        }
        try assertOwner(parents, uid: user.uid)
        try assertOwner(parents.deletingLastPathComponent(), uid: user.uid)
        let key = Data(repeating: 42, count: 32)
        try seedLegacyRootFiles(store: store, key: key)
        let readableBefore = try storage.perform { (try? Data(contentsOf: store.secretURL)) != nil }
        #expect(!readableBefore)
        try BreakGlassOwnershipRepair.repair(user: user, flavor: .production)
        try BreakGlassOwnershipRepair.repair(user: user, flavor: .production)
        #expect(try Data(contentsOf: store.secretURL) == key)
        let now = Date()
        let canceller = RootFixtureCanceller()
        let command = try BreakGlassCommand.parse(["--reason", "recover a stalled fixture"])
        for _ in 0 ..< 2 {
            _ = try command.output(
                store: store,
                canceller: canceller,
                isRoot: true,
                now: now,
                issuedBy: "root-fixture@localhost",
                storageAccess: storage
            )
            let readableAfter = try storage.perform { store.activeRelease(now: now) != nil }
            #expect(readableAfter)
            try assertPrivateOwner(store.recordURL, uid: user.uid, gid: user.gid)
            try assertPrivateOwner(store.secretURL, uid: user.uid, gid: user.gid)
        }
        #expect(try Data(contentsOf: store.secretURL) == key)
        #expect(canceller.calls == 2)
        #expect(throws: (any Error).self) {
            try storage.perform { throw CocoaError(.fileReadUnknown) }
        }
        let restored = try system.capture()
        #expect(restored.uid == original.uid)
        #expect(restored.gid == original.gid)
        #expect(Set(restored.groups) == Set(original.groups))
    }

    private func removeFixtureLibrary(
        user: BreakGlassRecoveryUser,
        storage: BreakGlassUserStorage
    ) {
        try? storage.perform {
            try FileManager.default.removeItem(at: user.home.appendingPathComponent("Library"))
        }
    }

    private func fixtureUser() throws -> BreakGlassRecoveryUser {
        let environment = ProcessInfo.processInfo.environment
        let path = try #require(environment["CURFEW_ROOT_OWNERSHIP_FIXTURE"])
        let uid = try #require(environment["CURFEW_ROOT_OWNERSHIP_UID"].flatMap { uid_t($0) })
        let gid = try #require(environment["CURFEW_ROOT_OWNERSHIP_GID"].flatMap { gid_t($0) })
        try #require(geteuid() == 0 && uid != 0)
        let home = URL(fileURLWithPath: path, isDirectory: true)
        var entry = stat()
        try #require(lstat(path, &entry) == 0 && entry.st_mode & S_IFMT == S_IFDIR && entry
            .st_uid == uid)
        try #require(home.lastPathComponent.hasPrefix("curfew-recovery-ownership-"))
        try #require(try FileManager.default.contentsOfDirectory(atPath: path).isEmpty)
        return BreakGlassRecoveryUser(uid: uid, gid: gid, name: "fixture-user", home: home)
    }

    private func seedLegacyRootFiles(store: BreakGlassStore, key: Data) throws {
        try FileManager.default.createDirectory(
            at: store.secretURL.deletingLastPathComponent(),
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o755]
        )
        try key.write(to: store.secretURL)
        #expect(chmod(store.secretURL.path, 0o600) == 0)
        try store.issue(
            reason: "legacy root-owned fixture",
            issuedBy: "root-fixture@localhost",
            now: Date()
        )
        try assertPrivateOwner(store.secretURL, uid: 0)
        try assertPrivateOwner(store.recordURL, uid: 0)
    }

    private func assertOwner(_ url: URL, uid: uid_t) throws {
        var entry = stat()
        try #require(lstat(url.path, &entry) == 0)
        #expect(entry.st_uid == uid)
    }

    private func assertPrivateOwner(_ url: URL, uid: uid_t, gid: gid_t? = nil) throws {
        var entry = stat()
        try #require(lstat(url.path, &entry) == 0)
        #expect(entry.st_uid == uid)
        #expect(entry.st_mode & 0o777 == 0o600)
        if let gid {
            #expect(entry.st_gid == gid)
        }
    }
}

private final class RootFixtureCanceller: PendingShutdownCanceling, @unchecked Sendable {
    var calls = 0
    func cancelPendingShutdown() -> Bool {
        #expect(geteuid() == 0)
        calls += 1
        return true
    }
}
