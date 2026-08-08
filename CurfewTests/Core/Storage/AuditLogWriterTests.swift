@testable import Curfew
import Foundation
import Testing

/// Filesystem behaviour of ``AuditLogWriter``: append semantics, rotation,
/// retention, chain continuity across restarts, and the separation that lets
/// the app and the root daemon both record during one lockout.
struct AuditLogWriterTests {
    private func record(
        _ event: AuditEventType = .phaseChanged,
        stream: AuditStream = .app,
        detail: [String: AuditValue] = [:]
    ) -> AuditRecord {
        AuditRecord(
            stream: stream,
            timestamp: Date(timeIntervalSince1970: 1_764_000_000),
            actor: .app,
            event: event,
            detail: detail
        )
    }

    // MARK: - Append

    @Test("Appending writes one line per record and never rewrites earlier ones")
    func appendIsAppendOnly() throws {
        let writer = try AuditTestSupport.makeWriter(label: "append")
        writer.append(record(.appLaunched))
        let afterFirst = try Data(contentsOf: writer.activeFileURL)
        writer.append(record(.phaseChanged))
        writer.append(record(.lockoutStarted))

        let final = try Data(contentsOf: writer.activeFileURL)
        #expect(final.prefix(afterFirst.count) == afterFirst)
        #expect(AuditTestSupport.lines(of: writer.activeFileURL).count == 3)
    }

    @Test("The writer assigns monotonic sequence numbers starting at 1")
    func sequenceIsMonotonic() throws {
        let writer = try AuditTestSupport.makeWriter(label: "seq")
        for _ in 0 ..< 4 {
            writer.append(record())
        }
        let sequences = AuditTestSupport.records(in: writer.activeFileURL)
            .compactMap { $0["seq"] as? Int }
        #expect(sequences == [1, 2, 3, 4])
    }

    @Test("The writer overrides a record's stream with its own")
    func writerOwnsStreamField() throws {
        let writer = try AuditTestSupport.makeWriter(label: "stream", stream: .app)
        writer.append(record(stream: .daemon))
        let parsed = try #require(
            AuditTestSupport.records(in: writer.activeFileURL).first
        )
        #expect(parsed["stream"] as? String == "app")
    }

    @Test("Every written line verifies and each links to the one before it")
    func chainIsIntactAcrossAppends() throws {
        let writer = try AuditTestSupport.makeWriter(label: "chain")
        for index in 0 ..< 5 {
            writer.append(record(detail: ["index": .int(index)]))
        }

        let lines = AuditTestSupport.lines(of: writer.activeFileURL)
        #expect(lines.count == 5)
        var expectedPrev = auditGenesisHash
        for line in lines {
            #expect(AuditLineEncoder.verify(line: line))
            let parsed = try #require(AuditTestSupport.parse(line))
            #expect(parsed["prev"] as? String == expectedPrev)
            expectedPrev = try #require(AuditLineEncoder.hash(inLine: line))
        }
        #expect(writer.currentChainHead == expectedPrev)
    }

    // MARK: - Restart

    @Test("A second writer over the same file continues the chain and the sequence")
    func chainSurvivesProcessRestart() throws {
        let directory = try AuditTestSupport.makeDirectory(label: "restart")
        let first = try AuditLogWriter(
            stream: .app,
            directory: directory,
            baseName: "curfew-restart",
            filePermissions: 0o600
        )
        first.append(record(.appLaunched))
        first.append(record(.phaseChanged))
        let headBeforeRestart = first.currentChainHead

        let second = try AuditLogWriter(
            stream: .app,
            directory: directory,
            baseName: "curfew-restart",
            filePermissions: 0o600
        )
        #expect(second.currentChainHead == headBeforeRestart)
        second.append(record(.appTerminating))

        let records = AuditTestSupport.records(in: second.activeFileURL)
        #expect(records.count == 3)
        #expect(records.last?["seq"] as? Int == 3)
        #expect(records.last?["prev"] as? String == headBeforeRestart)
    }

    @Test("The stream-opened marker reports whether the chain was recovered")
    func streamOpenedReportsChainRecovery() throws {
        let directory = try AuditTestSupport.makeDirectory(label: "opened")
        let first = try AuditLogWriter(
            stream: .app,
            directory: directory,
            baseName: "curfew-opened",
            filePermissions: 0o600
        )
        first.recordStreamOpened()

        let second = try AuditLogWriter(
            stream: .app,
            directory: directory,
            baseName: "curfew-opened",
            filePermissions: 0o600
        )
        second.recordStreamOpened()

        let markers = AuditTestSupport.records(in: second.activeFileURL)
            .filter { $0["event"] as? String == "audit.stream_opened" }
        #expect(markers.count == 2)
        let firstDetail = try #require(markers[0]["detail"] as? [String: Any])
        let secondDetail = try #require(markers[1]["detail"] as? [String: Any])
        #expect(firstDetail["chainRecovered"] as? Bool == false)
        #expect(secondDetail["chainRecovered"] as? Bool == true)
    }
}
