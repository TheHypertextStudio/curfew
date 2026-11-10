@testable import CurfewAtmosphere
import CurfewKit
import Darwin
import Foundation
import Testing

struct RestPresentationFilesTests {
    @Test("Removing a publication slot preserves the other owned slots")
    func scopedRemoval() throws {
        try withDirectory { directory in
            let files = RestPresentationFiles(directory: directory)
            try files.write(.appearance, bytes: Data([1]))
            try files.write(.occurrence, bytes: Data([2]))
            try files.remove(.occurrence)
            let removed = try files.read(.occurrence, maximum: 8)
            let retained = try files.read(.appearance, maximum: 8)
            #expect(removed == nil)
            #expect(retained == Data([1]))
            try files.remove(.occurrence)
        }
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("CurfewPresentationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: root) }
        try body(root.appendingPathComponent("presentation"))
    }

    @Test("Independent publishers and read-only host instances exchange bounded slots")
    func independentInstances() throws {
        try withDirectory { directory in
            let writer = RestPresentationFiles(directory: directory)
            let reader = RestPresentationFiles(directory: directory)
            for slot in [
                RestCompanionPresentationStore.Slot.appearance,
                .occurrence,
                .readbackRequest
            ] {
                let bytes = Data("\(slot)".utf8)
                try writer.write(slot, bytes: bytes)
                let received = try reader.read(slot, maximum: 4096)
                #expect(received == bytes)
            }
        }
    }

    @Test("Presentation directory and files remain private to their owning user")
    func privatePermissions() throws {
        try withDirectory { directory in
            try RestPresentationFiles(directory: directory).write(.appearance, bytes: Data([1]))
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
            for file in try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            ) {
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: file.path)
                #expect((fileAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            }
        }
    }

    @Test("Appearance remains unchanged when only occurrence or readback data changes")
    func independentAppearance() throws {
        try withDirectory { directory in
            let files = RestPresentationFiles(directory: directory)
            let image = Data(repeating: 7, count: 4096)
            try files.write(.appearance, bytes: image)
            let before = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
            let appearance = try #require(before.first)
            let inode = try FileManager.default
                .attributesOfItem(atPath: appearance.path)[.systemFileNumber] as? NSNumber
            try files.write(.occurrence, bytes: Data([2]))
            try files.write(.readbackRequest, bytes: Data([3]))
            let received = try files.read(.appearance, maximum: 4096)
            #expect(received == image)
            let after = try FileManager.default
                .attributesOfItem(atPath: appearance.path)[.systemFileNumber] as? NSNumber
            #expect(inode == after)
        }
    }

    @Test("Oversized writes preserve prior content and bounded reads reject excess bytes")
    func sizeLimits() throws {
        try withDirectory { directory in
            let files = RestPresentationFiles(directory: directory)
            try files.write(.occurrence, bytes: Data([1]))
            #expect(throws: (any Error).self) {
                try files.write(.occurrence, bytes: Data(repeating: 2, count: 4097))
            }
            let received = try files.read(.occurrence, maximum: 1)
            #expect(received == Data([1]))
            #expect(throws: (any Error).self) { try files.read(.occurrence, maximum: 0) }
        }
    }

    @Test("Missing publications stay absent without creating a host-side directory")
    func readDoesNotCreate() throws {
        try withDirectory { directory in
            let received = try RestPresentationFiles(directory: directory).read(
                .appearance,
                maximum: 8
            )
            #expect(received == nil)
            #expect(!FileManager.default.fileExists(atPath: directory.path))
        }
    }

    @Test("A symbolic-link publication directory cannot redirect a write")
    func rejectsDirectoryLink() throws {
        try withDirectory { directory in
            let target = directory.deletingLastPathComponent().appendingPathComponent("other")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            try FileManager.default.createSymbolicLink(at: directory, withDestinationURL: target)
            #expect(throws: (any Error).self) {
                try RestPresentationFiles(directory: directory).write(.occurrence, bytes: Data([1]))
            }
            let entries = try FileManager.default.contentsOfDirectory(atPath: target.path)
            #expect(entries.isEmpty)
        }
    }
}
