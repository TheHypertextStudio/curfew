@testable import curfew_ctl
import CurfewKit
import Darwin
import Foundation
import Testing

struct BreakGlassOwnershipRepairTests {
    @Test("Ownership validation is repeatable and preserves existing signing bytes")
    func repeatedValidation() throws {
        try withOwnershipFixture { user in
            let store = user.store(flavor: .production)
            try FileManager.default.createDirectory(
                at: store.recordURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let secret = Data(repeating: 42, count: 32)
            try secret.write(to: store.secretURL)
            try Data("retained record".utf8).write(to: store.recordURL)
            try BreakGlassOwnershipRepair.repair(user: user, flavor: .production)
            try BreakGlassOwnershipRepair.repair(user: user, flavor: .production)
            #expect(try Data(contentsOf: store.secretURL) == secret)
            #expect(try Data(contentsOf: store.recordURL) == Data("retained record".utf8))
        }
    }

    @Test("Ownership repair rejects a secret symlink without changing its target")
    func rejectsSecretSymlink() throws {
        try withOwnershipFixture { user in
            let store = user.store(flavor: .production)
            try FileManager.default.createDirectory(
                at: store.secretURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let target = user.home.appendingPathComponent("outside")
            let bytes = Data(repeating: 42, count: 32)
            try bytes.write(to: target)
            try FileManager.default.createSymbolicLink(
                at: store.secretURL,
                withDestinationURL: target
            )
            #expect(throws: (any Error).self) { try BreakGlassOwnershipRepair.repair(
                user: user,
                flavor: .production
            ) }
            #expect(try Data(contentsOf: target) == bytes)
            #expect(try FileManager.default
                .destinationOfSymbolicLink(atPath: store.secretURL.path) == target.path)
        }
    }

    @Test("Ownership repair rejects multiply linked files")
    func rejectsHardLink() throws {
        try withOwnershipFixture { user in
            let store = user.store(flavor: .production)
            try FileManager.default.createDirectory(
                at: store.secretURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let target = user.home.appendingPathComponent("outside")
            try Data(repeating: 42, count: 32).write(to: target)
            #expect(link(target.path, store.secretURL.path) == 0)
            #expect(throws: (any Error).self) { try BreakGlassOwnershipRepair.repair(
                user: user,
                flavor: .production
            ) }
        }
    }

    @Test("Ownership repair rejects a redirected support-directory component")
    func rejectsDirectorySymlink() throws {
        try withOwnershipFixture { user in
            let outside = user.home.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(
                at: user.home.appendingPathComponent("Library"),
                withDestinationURL: outside
            )
            #expect(throws: (any Error).self) { try BreakGlassOwnershipRepair.repair(
                user: user,
                flavor: .production
            ) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
        }
    }
}

private func withOwnershipFixture(_ body: (BreakGlassRecoveryUser) throws -> Void) throws {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: home) }
    try body(BreakGlassRecoveryUser(uid: getuid(), gid: getgid(), name: "fixture", home: home))
}
