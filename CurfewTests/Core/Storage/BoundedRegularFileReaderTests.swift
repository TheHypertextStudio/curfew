@testable import Curfew
import Darwin
import Foundation
import Testing

struct BoundedRegularFileReaderTests {
    @Test("Reads a regular file without trusting its advertised size")
    func readsRegularFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("value.json")
        let expected = Data(#"{"safe":true}"#.utf8)
        try expected.write(to: file)

        #expect(try BoundedRegularFileReader.read(file, maximumBytes: 64) == expected)
    }

    @Test("Never opens a FIFO and returns without a writer")
    func rejectsFIFOWithoutBlocking() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fifo = root.appendingPathComponent("value.json")
        #expect(mkfifo(fifo.path, 0o600) == 0)

        #expect(throws: BoundedRegularFileReadError.unsafeEntry) {
            try BoundedRegularFileReader.read(fifo, maximumBytes: 64)
        }
    }

    @Test("Rejects symlinks and payloads larger than the explicit byte limit")
    func rejectsSymlinkAndOversizeFile() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent("target.json")
        try Data(repeating: 0x41, count: 65).write(to: target)
        let link = root.appendingPathComponent("link.json")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        #expect(throws: BoundedRegularFileReadError.tooLarge) {
            try BoundedRegularFileReader.read(target, maximumBytes: 64)
        }
        #expect(throws: BoundedRegularFileReadError.unsafeEntry) {
            try BoundedRegularFileReader.read(link, maximumBytes: 64)
        }
    }

    @Test("Every user-controlled daemon store fails safely on a FIFO")
    func daemonStoresRejectFIFO() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let deadline = root.appendingPathComponent("deadline")
        #expect(mkfifo(deadline.path, 0o600) == 0)
        #expect(LockoutDeadlineStore(recordURL: deadline).load() == nil)

        let breakGlass = root.appendingPathComponent("break-glass")
        #expect(mkfifo(breakGlass.path, 0o600) == 0)
        #expect(BreakGlassStore(
            recordURL: breakGlass,
            secretURL: root.appendingPathComponent("secret")
        )
        .activeRelease(now: Date()) == nil)

        let policy = root.appendingPathComponent("policy")
        #expect(mkfifo(policy.path, 0o600) == 0)
        #expect(ProtectedWorkPolicy.loadMirror(from: policy) == .default)

        let claims = root.appendingPathComponent("claims")
        #expect(mkfifo(claims.path, 0o600) == 0)
        #expect(ProtectedWorkStore(recordURL: claims).load().isEmpty)

        let enrollment = root.appendingPathComponent("enrollment")
        #expect(mkfifo(enrollment.path, 0o600) == 0)
        #expect(throws: BoundedRegularFileReadError.unsafeEntry) {
            try RemoteCommandEnrollmentStore(recordURL: enrollment).load()
        }
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
