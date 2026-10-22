@testable import CurfewKit
import Darwin
import Foundation
import Testing

/// Filesystem-only contracts: canonical temporary fixtures, never a privileged path.
/// The preparation API remains inert pending actual failing-first execution.
struct SunriseWakeDirectoryTests {
    private let namespace = "studio.hypertext.curfew.test.sunrise"

    private func isolated(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("SunriseDirectoryTests-\(UUID().uuidString)", isDirectory: true)
        try directory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root)
    }

    private func directory(_ url: URL, mode: Int = 0o700) throws {
        try FileManager.default.createDirectory(
            at: url, withIntermediateDirectories: false, attributes: [.posixPermissions: mode]
        )
        try #require(chmod(url.path, mode_t(mode)) == 0)
    }

    private func metadata(_ url: URL) throws -> stat {
        var result = stat()
        try #require(lstat(url.path, &result) == 0)
        return result
    }

    private func prepare(_ base: URL, namespace: String? = nil) throws -> URL {
        try SunriseWakeJournal.prepareDirectory(
            in: base, namespace: namespace ?? self.namespace, requiredOwnerUserID: geteuid()
        )
    }

    @Test("Preparing a helper namespace creates only a private owned directory")
    func createsPrivateNamespace() throws {
        try isolated { base in
            let url = try prepare(base)
            let expected = base.appendingPathComponent(namespace, isDirectory: true)
                .appendingPathComponent("sunrise.json")
            #expect(url.path == expected.path)
            #expect(!FileManager.default.fileExists(atPath: url.path))
            #expect(try FileManager.default.contentsOfDirectory(atPath: base.path) == [namespace])
            let created = try metadata(url.deletingLastPathComponent())
            #expect(created.st_uid == geteuid())
            #expect(created.st_mode & S_IFMT == S_IFDIR)
            #expect(created.st_mode & 0o777 == 0o700)
        }
    }

    @Test("Repeated preparation preserves existing journal and sibling bytes")
    func idempotentAndNondestructive() throws {
        try isolated { base in
            let url = try prepare(base)
            let bytes = Data("existing recovery identity".utf8)
            let sibling = base.appendingPathComponent("unrelated.json")
            let siblingBytes = Data("unrelated".utf8)
            try bytes.write(to: url)
            try siblingBytes.write(to: sibling)
            let original = try metadata(url.deletingLastPathComponent())
            #expect(try prepare(base).path == url.path)
            #expect(try prepare(base).path == url.path)
            #expect(try Data(contentsOf: url) == bytes)
            #expect(try Data(contentsOf: sibling) == siblingBytes)
            let retained = try metadata(url.deletingLastPathComponent())
            #expect(retained.st_ino == original.st_ino)
            #expect(retained.st_mode == original.st_mode)
        }
    }

    @Test("Unsafe namespace names cannot create or escape a directory", arguments: [
        "", ".", "..", "../escape", "nested/name", "nested\\name", "studio..curfew",
        " curfew", "curfew\0suffix", "curfew/", "curfew.\u{202E}", String(
            repeating: "a",
            count: 256
        )
    ])
    func invalidNamespace(name: String) throws {
        try isolated { base in
            #expect(throws: SunriseWakeJournal.Failure.unavailable) {
                try prepare(base, namespace: name)
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: base.path).isEmpty)
        }
    }

    @Test("A symbolic-link base is rejected without writing through it")
    func rejectsLinkedBase() throws {
        try isolated { root in
            let real = root.appendingPathComponent("real", isDirectory: true)
            let link = root.appendingPathComponent("link", isDirectory: true)
            try directory(real)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            #expect(throws: SunriseWakeJournal.Failure.unavailable) { try prepare(link) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: real.path).isEmpty)
            #expect(try metadata(link).st_mode & S_IFMT == S_IFLNK)
        }
    }

    @Test("A symbolic-link ancestor cannot redirect an otherwise private base")
    func rejectsLinkedAncestor() throws {
        try isolated { root in
            let real = root.appendingPathComponent("real", isDirectory: true)
            let realBase = real.appendingPathComponent("base", isDirectory: true)
            let link = root.appendingPathComponent("link", isDirectory: true)
            try directory(real)
            try directory(realBase)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
            let indirectBase = link.appendingPathComponent("base", isDirectory: true)
            #expect(throws: SunriseWakeJournal.Failure.unavailable) { try prepare(indirectBase) }
            #expect(try FileManager.default.contentsOfDirectory(atPath: realBase.path).isEmpty)
            #expect(try metadata(link).st_mode & S_IFMT == S_IFLNK)
        }
    }

    @Test("Writable base and ancestor permissions are rejected rather than repaired")
    func rejectsWritableDirectories() throws {
        try isolated { root in
            let writable = root.appendingPathComponent("writable", isDirectory: true)
            let privateBase = writable.appendingPathComponent("base", isDirectory: true)
            try directory(writable, mode: 0o777)
            try directory(privateBase)
            #expect(throws: SunriseWakeJournal.Failure.unavailable) { try prepare(writable) }
            #expect(throws: SunriseWakeJournal.Failure.unavailable) { try prepare(privateBase) }
            #expect(try metadata(writable).st_mode & 0o777 == 0o777)
            #expect(try metadata(privateBase).st_mode & 0o777 == 0o700)
            #expect(try FileManager.default.contentsOfDirectory(atPath: privateBase.path).isEmpty)
        }
    }

    @Test("A required owner mismatch cannot create or adopt the journal directory")
    func rejectsOwnerMismatch() throws {
        try isolated { base in
            let wrongUID: uid_t = geteuid() == 0 ? 1 : 0
            #expect(throws: SunriseWakeJournal.Failure.unavailable) {
                try SunriseWakeJournal.prepareDirectory(
                    in: base, namespace: namespace, requiredOwnerUserID: wrongUID
                )
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: base.path).isEmpty)
        }
    }

    @Test("An existing symbolic-link namespace remains untouched")
    func rejectsLinkedNamespace() throws {
        try isolated { root in
            let base = root.appendingPathComponent("base", isDirectory: true)
            let target = root.appendingPathComponent("target", isDirectory: true)
            try directory(base)
            try directory(target)
            let link = base.appendingPathComponent(namespace, isDirectory: true)
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
            #expect(throws: SunriseWakeJournal.Failure.unavailable) { try prepare(base) }
            #expect(try metadata(link).st_mode & S_IFMT == S_IFLNK)
            #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).isEmpty)
        }
    }

    @Test("A file occupying the namespace is never overwritten or removed")
    func rejectsNonDirectoryNamespace() throws {
        try isolated { base in
            let occupied = base.appendingPathComponent(namespace)
            let bytes = Data("unrelated file".utf8)
            try bytes.write(to: occupied)
            #expect(throws: SunriseWakeJournal.Failure.unavailable) { try prepare(base) }
            #expect(try Data(contentsOf: occupied) == bytes)
        }
    }

    @Test("An existing nonprivate namespace is rejected without permission changes")
    func rejectsWritableNamespace() throws {
        try isolated { base in
            let existing = base.appendingPathComponent(namespace, isDirectory: true)
            try directory(existing, mode: 0o755)
            #expect(throws: SunriseWakeJournal.Failure.unavailable) { try prepare(base) }
            #expect(try metadata(existing).st_mode & 0o777 == 0o755)
            #expect(try FileManager.default.contentsOfDirectory(atPath: existing.path).isEmpty)
        }
    }
}
