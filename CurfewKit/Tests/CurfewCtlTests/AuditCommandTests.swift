@testable import curfew_ctl
import Foundation
import Testing

struct AuditCommandTests {
    @Test(
        "Damaged audit files report data failure instead of usage failure",
        arguments: [Data("bad record\n".utf8), Data([0xFF, 0xFE])]
    )
    func damagedDataClassification(bytes: Data) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("curfew-app.jsonl")
        try bytes.write(to: file)
        do {
            _ = try AuditCommand.records(
                directory: directory,
                stem: "curfew-app",
                since: .distantPast
            )
            Issue.record("Damaged audit data was accepted.")
        } catch {
            let failure = CLIError.classify(error, parsing: false)
            #expect(failure.code == "data.invalid_state")
            #expect(failure.exitStatus == 65)
        }
        #expect(try Data(contentsOf: file) == bytes)
    }

    @Test("Audit export includes rotated segments and filters by timestamp")
    func rotatedHistory() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let old = "{\"ts\":\"2026-11-01T12:00:00.000+00:00\",\"event\":\"lockout.started\"}\n"
        let recent = "{\"ts\":\"2026-11-03T12:00:00.000+00:00\",\"event\":\"lockout.ended\"}\n"
        try Data(old.utf8).write(to: directory.appendingPathComponent("curfew-app.1.jsonl"))
        try Data(recent.utf8).write(to: directory.appendingPathComponent("curfew-app.jsonl"))
        let since = try #require(ISO8601DateFormatter().date(from: "2026-11-02T00:00:00Z"))
        let records = try AuditCommand.records(
            directory: directory,
            stem: "curfew-app",
            since: since
        )
        #expect(records.count == 1)
        #expect(records.first?["event"] as? String == "lockout.ended")
        #expect(try AuditCommand.records(
            directory: directory,
            stem: "curfew-app",
            since: .distantPast
        ).count == 2)
    }

    @Test("Malformed audit data is an error instead of a missing event")
    func malformedAudit() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("bad record\n".utf8)
            .write(to: directory.appendingPathComponent("curfew-app.jsonl"))
        #expect(throws: (any Error).self) {
            _ = try AuditCommand.records(
                directory: directory,
                stem: "curfew-app",
                since: .distantPast
            )
        }
    }

    @Test("Audit rejects invalid date ranges and streams")
    func invalidArguments() {
        for args in [
            ["--days", "0"],
            ["--stream", "wrong"],
            ["--since", "yesterday"],
            ["--days", "3", "--since", "2026-11-02T00:00:00Z"]
        ] {
            #expect(throws: (any Error).self) { _ = try AuditCommand.parse(args) }
        }
    }
}
