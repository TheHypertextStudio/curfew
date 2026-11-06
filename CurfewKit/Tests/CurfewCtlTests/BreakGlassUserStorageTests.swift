@testable import curfew_ctl
import CurfewKit
import Darwin
import Foundation
import Testing

struct BreakGlassUserStorageTests {
    @Test("Recovery paths and effective identity use the same console account")
    func consoleIdentity() throws {
        let user = try BreakGlassRecoveryUser.resolve(consoleUID: 501) { id in
            BreakGlassRecoveryUser(
                uid: id,
                gid: 20,
                name: "console",
                home: URL(fileURLWithPath: "/Users/console")
            )
        }
        let store = user.store(flavor: .production)
        #expect(user.uid == 501)
        #expect(store.recordURL
            .path == "/Users/console/Library/Application Support/Curfew/break-glass.json")
        #expect(store.secretURL.deletingLastPathComponent() == store.recordURL
            .deletingLastPathComponent())
    }

    @Test("Missing, root, or unresolved console accounts fail without choosing root's home")
    func missingConsole() {
        for uid in [nil, 0, 501] as [uid_t?] {
            #expect(throws: (any Error).self) {
                try BreakGlassRecoveryUser.resolve(consoleUID: uid) { _ in nil }
            }
        }
    }

    @Test("Storage drops root groups and identity before work and restores them afterward")
    func identityScope() throws {
        let credentials = FakeRecoveryCredentials()
        let storage = BreakGlassUserStorage(user: fixtureUser(), credentials: credentials)
        let value = try storage.perform {
            #expect(credentials.state.uid == 501)
            #expect(credentials.state.gid == 20)
            #expect(credentials.state.groups.isEmpty)
            return 42
        }
        #expect(value == 42)
        #expect(credentials.state == FakeRecoveryCredentials.original)
        #expect(credentials.events == [
            "groups:",
            "gid:20",
            "uid:501",
            "uid:0",
            "gid:0",
            "groups:0,20"
        ])
    }

    @Test("Storage errors restore root before they reach the caller")
    func operationFailure() {
        let credentials = FakeRecoveryCredentials()
        let storage = BreakGlassUserStorage(user: fixtureUser(), credentials: credentials)
        #expect(throws: (any Error).self) {
            try storage.perform { throw CocoaError(.fileReadUnknown) }
        }
        #expect(credentials.state == FakeRecoveryCredentials.original)
    }

    @Test("A failed identity drop prevents storage work and restores the original groups")
    func dropFailure() {
        let credentials = FakeRecoveryCredentials()
        credentials.failOn = "uid:501"
        let storage = BreakGlassUserStorage(user: fixtureUser(), credentials: credentials)
        var reachedStorage = false
        #expect(throws: (any Error).self) { try storage.perform { reachedStorage = true } }
        #expect(!reachedStorage)
        #expect(credentials.state == FakeRecoveryCredentials.original)
    }

    @Test("Restoration failure aborts recovery before shutdown cancellation")
    func restoreFailure() throws {
        let credentials = FakeRecoveryCredentials()
        credentials.failOn = "uid:0"
        let storage = BreakGlassUserStorage(user: fixtureUser(), credentials: credentials)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BreakGlassStore(
            recordURL: directory.appendingPathComponent("release.json"),
            secretURL: directory.appendingPathComponent("secret")
        )
        let canceller = CredentialCheckingCanceller(credentials: credentials)
        let command = try BreakGlassCommand.parse(["--reason", "recover a stalled lockout"])
        #expect(throws: (any Error).self) {
            try command.output(
                store: store,
                canceller: canceller,
                isRoot: true,
                now: Date(),
                issuedBy: "tester@host",
                storageAccess: storage
            )
        }
        #expect(canceller.calls == 0)
        #expect(credentials.events.contains("gid:0"))
        #expect(credentials.events.contains("groups:0,20"))
    }

    @Test("Repeated root recovery keeps one readable key and restores root for cancellation")
    func repeatedIssue() throws {
        let credentials = FakeRecoveryCredentials()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BreakGlassStore(
            recordURL: directory.appendingPathComponent("release.json"),
            secretURL: directory.appendingPathComponent("secret")
        )
        let storage = BreakGlassUserStorage(user: fixtureUser(), credentials: credentials)
        let canceller = CredentialCheckingCanceller(credentials: credentials)
        let command = try BreakGlassCommand.parse(["--reason", "recover a stalled lockout"])
        _ = try command.output(
            store: store,
            canceller: canceller,
            isRoot: true,
            now: Date(),
            issuedBy: "tester@host",
            storageAccess: storage
        )
        let key = try Data(contentsOf: store.secretURL)
        _ = try command.output(
            store: store,
            canceller: canceller,
            isRoot: true,
            now: Date(),
            issuedBy: "tester@host",
            storageAccess: storage
        )
        #expect(try Data(contentsOf: store.secretURL) == key)
        #expect(credentials.state == FakeRecoveryCredentials.original)
        #expect(canceller.calls == 2)
    }

    @Test("Dry-run revoke neither repairs ownership nor changes effective identity")
    func previewDoesNotDrop() throws {
        let credentials = FakeRecoveryCredentials()
        let storage = BreakGlassUserStorage(user: fixtureUser(), credentials: credentials)
        let store = BreakGlassStore(
            recordURL: URL(fileURLWithPath: "/unused/release"),
            secretURL: URL(fileURLWithPath: "/unused/secret")
        )
        let command = try BreakGlassCommand.parse(["--revoke", "--dry-run"])
        let canceller = CredentialCheckingCanceller(credentials: credentials)
        _ = try command.output(
            store: store,
            canceller: canceller,
            isRoot: true,
            now: Date(),
            issuedBy: "tester@host",
            storageAccess: storage
        )
        #expect(credentials.events.isEmpty)
        #expect(canceller.calls == 0)
    }
}

private func fixtureUser() -> BreakGlassRecoveryUser {
    BreakGlassRecoveryUser(
        uid: 501,
        gid: 20,
        name: "console",
        home: URL(fileURLWithPath: "/Users/console")
    )
}

private final class FakeRecoveryCredentials: BreakGlassCredentials {
    static let original = BreakGlassCredentialState(uid: 0, gid: 0, groups: [0, 20])
    var state = original
    var events: [String] = []
    var failOn: String?
    func capture() throws -> BreakGlassCredentialState {
        state
    }

    func setEffectiveUser(_ uid: uid_t) throws {
        try check("uid:\(uid)"); state.uid = uid
    }

    func setEffectiveGroup(_ gid: gid_t) throws {
        try check("gid:\(gid)"); state.gid = gid
    }

    func setGroups(_ groups: [gid_t]) throws {
        try check("groups:\(groups.map(String.init).joined(separator: ","))"); state
            .groups = groups
    }

    private func check(_ event: String) throws {
        events.append(event)
        if event == failOn {
            throw CocoaError(.fileWriteNoPermission)
        }
    }
}

private final class CredentialCheckingCanceller: PendingShutdownCanceling, @unchecked Sendable {
    let credentials: FakeRecoveryCredentials
    var calls = 0
    init(credentials: FakeRecoveryCredentials) {
        self.credentials = credentials
    }

    func cancelPendingShutdown() -> Bool {
        calls += 1
        #expect(credentials.state.uid == 0)
        return true
    }
}
