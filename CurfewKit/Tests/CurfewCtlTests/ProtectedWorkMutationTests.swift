@testable import curfew_ctl
import CurfewKit
import Foundation
import Testing

struct ProtectedWorkMutationTests {
    @Test("Claim fails without overwriting a malformed protected-work file")
    func claimRejectsCorruptStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("claims.json")
        let original = Data("not valid JSON".utf8)
        try original.write(to: url)
        let store = ProtectedWorkStore(recordURL: url)
        #expect(throws: (any Error).self) {
            try store.claim(label: "build release", source: .cli, now: Date(), policy: .default)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test("Release fails without overwriting a malformed protected-work file")
    func releaseRejectsCorruptStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("claims.json")
        let original = Data("not valid JSON".utf8)
        try original.write(to: url)
        let store = ProtectedWorkStore(recordURL: url)
        #expect(throws: (any Error).self) {
            try store.release(id: UUID())
        }
        #expect(try Data(contentsOf: url) == original)
    }
}
