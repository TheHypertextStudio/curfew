@testable import CurfewKit
import Darwin
import Foundation
import Testing

/// Prepared filesystem contracts; no native wake API or privileged location.
/// Runtime RED is deliberately pending the authorized execution gate.
struct SunriseWakeJournalTests {
    private let owner = "studio.hypertext.curfew.dev.sunrise"

    private func record(owner: String? = nil, phase: SunriseWakeScheduler.Record.Phase = .pending)
        -> SunriseWakeScheduler.Record {
        .init(plan: .init(
            owner: owner ?? self.owner,
            occurrenceID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            wakeAt: Date(timeIntervalSince1970: 2_000_000_000),
            holdUntil: Date(timeIntervalSince1970: 2_000_003_900),
            allowsBattery: false
        ), phase: phase)
    }

    private func isolated(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SunriseJournalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory.appendingPathComponent("sunrise.json"))
    }

    private func journal(_ url: URL, requiredOwnerUserID: uid_t = geteuid()) -> SunriseWakeJournal {
        SunriseWakeJournal(url: url, owner: owner, requiredOwnerUserID: requiredOwnerUserID)
    }

    @Test("Missing journal loads nil and repeated clear is harmless")
    func missingJournal() throws {
        try isolated { url in
            #expect(try journal(url).load() == nil)
            try journal(url).save(nil)
            try journal(url).save(nil)
            #expect(!FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test("Both phases survive reconstruction from actual bounded Codable bytes")
    func survivesRecreation() throws {
        try isolated { url in
            for phase in [SunriseWakeScheduler.Record.Phase.pending, .scheduled] {
                let expected = record(phase: phase)
                try journal(url).save(expected)
                let bytes = try Data(contentsOf: url)
                #expect(bytes.count <= 4096)
                #expect(try JSONDecoder()
                    .decode(SunriseWakeScheduler.Record.self, from: bytes) == expected)
                #expect(try journal(url).load() == expected)
                var metadata = stat()
                #expect(lstat(url.path, &metadata) == 0)
                #expect(metadata.st_uid == geteuid())
                #expect(metadata.st_mode & 0o777 == 0o600)
            }
        }
    }

    @Test("Replacement publishes a new inode without truncating the previous open file")
    func atomicReplacement() throws {
        try isolated { url in
            let initial = record()
            let bytes = try JSONEncoder().encode(initial)
            try bytes.write(to: url)
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            let replacement = record(phase: .scheduled)
            try journal(url).save(replacement)
            #expect(try handle.readToEnd() == bytes)
            #expect(try journal(url).load() == replacement)
            #expect(try FileManager.default
                .contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
                == [url.lastPathComponent])
        }
    }

    @Test("Clear removes only its valid owned record and preserves sibling files")
    func clearsOnlyOwnJournal() throws {
        try isolated { url in
            let sibling = url.deletingLastPathComponent().appendingPathComponent("other.json")
            let sentinel = Data("unrelated".utf8)
            try sentinel.write(to: sibling)
            try journal(url).save(record())
            try journal(url).save(nil)
            #expect(try journal(url).load() == nil)
            #expect(try Data(contentsOf: sibling) == sentinel)
        }
    }

    @Test("Corrupt and oversized bytes are rejected and never erased or replaced")
    func rejectsMalformedBytes() throws {
        try isolated { url in
            for bytes in [Data("{".utf8), Data(repeating: 0x20, count: 4097)] {
                try bytes.write(to: url)
                #expect(throws: (any Error).self) { try journal(url).load() }
                #expect(throws: (any Error).self) { try journal(url).save(nil) }
                #expect(throws: (any Error).self) { try journal(url).save(record()) }
                #expect(try Data(contentsOf: url) == bytes)
            }
        }
    }

    @Test("Foreign event owner cannot be loaded, cleared or overwritten")
    func rejectsForeignRecord() throws {
        try isolated { url in
            let bytes = try JSONEncoder().encode(record(owner: "other.application"))
            try bytes.write(to: url)
            #expect(throws: (any Error).self) { try journal(url).load() }
            #expect(throws: (any Error).self) { try journal(url).save(nil) }
            #expect(throws: (any Error).self) { try journal(url).save(record()) }
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test("Foreign input cannot overwrite a valid recovery identity")
    func rejectedSavePreservesPreviousRecord() throws {
        try isolated { url in
            let bytes = try JSONEncoder().encode(record())
            try bytes.write(to: url)
            #expect(throws: (any Error).self) {
                try journal(url).save(record(owner: "other.application"))
            }
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test("Filesystem ownership mismatch rejects even a matching decoded owner")
    func rejectsFilesystemOwnerMismatch() throws {
        try isolated { url in
            let bytes = try JSONEncoder().encode(record())
            try bytes.write(to: url)
            let wrongUID: uid_t = geteuid() == 0 ? 1 : 0
            let subject = journal(url, requiredOwnerUserID: wrongUID)
            #expect(throws: (any Error).self) { try subject.load() }
            #expect(throws: (any Error).self) { try subject.save(nil) }
            #expect(throws: (any Error).self) { try subject.save(record()) }
            #expect(try Data(contentsOf: url) == bytes)
        }
    }

    @Test("Symlink leaf never grants read, replacement or deletion authority")
    func rejectsSymlinkLeaf() throws {
        try isolated { url in
            let target = url.deletingLastPathComponent().appendingPathComponent("target.json")
            let bytes = try JSONEncoder().encode(record())
            try bytes.write(to: target)
            try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
            #expect(throws: (any Error).self) { try journal(url).load() }
            #expect(throws: (any Error).self) { try journal(url).save(nil) }
            #expect(throws: (any Error).self) { try journal(url).save(record()) }
            #expect(try Data(contentsOf: target) == bytes)
            #expect(try FileManager.default.destinationOfSymbolicLink(atPath: url.path) == target
                .path)
        }
    }

    @Test("Directory entries are rejected without mutation")
    func rejectsNonregularEntries() throws {
        try isolated { url in
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            #expect(throws: (any Error).self) { try journal(url).load() }
            #expect(throws: (any Error).self) { try journal(url).save(nil) }
            #expect(throws: (any Error).self) { try journal(url).save(record()) }
            var metadata = stat()
            #expect(lstat(url.path, &metadata) == 0)
            #expect(metadata.st_mode & S_IFMT == S_IFDIR)
        }
    }

    @Test("Hard-linked recovery identity is never accepted or unlinked")
    func rejectsHardLinks() throws {
        try isolated { url in
            let bytes = try JSONEncoder().encode(record())
            try bytes.write(to: url)
            let alias = url.deletingLastPathComponent().appendingPathComponent("alias.json")
            try FileManager.default.linkItem(at: url, to: alias)
            #expect(throws: (any Error).self) { try journal(url).load() }
            #expect(throws: (any Error).self) { try journal(url).save(nil) }
            #expect(throws: (any Error).self) { try journal(url).save(record()) }
            #expect(try Data(contentsOf: url) == bytes)
            #expect(try Data(contentsOf: alias) == bytes)
        }
    }
}
