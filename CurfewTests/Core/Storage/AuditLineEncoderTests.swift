@testable import Curfew
import Foundation
import Testing

/// Byte-format tests for the audit line encoder.
///
/// These lock down the on-disk contract in `Documentation/audit-log.md`. A
/// failure here means an existing parser breaks, so treat any change that
/// needs these edited as a schema-version bump, not a fix.
struct AuditLineEncoderTests {
    private let fixedDate = Date(timeIntervalSince1970: 1_764_000_000)

    private func record(
        event: AuditEventType = .phaseChanged,
        actor: AuditActor = .app,
        priorState: String? = nil,
        newState: String? = nil,
        detail: [String: AuditValue] = [:],
        sequence: Int = 1
    ) -> AuditRecord {
        AuditRecord(
            stream: .app,
            timestamp: fixedDate,
            sequence: sequence,
            actor: actor,
            event: event,
            from: priorState,
            to: newState,
            detail: detail
        )
    }

    @Test("A record serializes to exactly one newline-terminated line")
    func singleLine() throws {
        let encoded = try AuditLineEncoder.encode(
            record(priorState: "warning", newState: "locked", detail: ["trigger": .string("time")]),
            previousHash: auditGenesisHash,
            timeZone: #require(TimeZone(secondsFromGMT: 0))
        )
        #expect(encoded.line.hasSuffix("\n"))
        #expect(encoded.line.dropLast().contains("\n") == false)
    }

    @Test("Envelope carries schema version, timestamp, sequence, stream, actor, event")
    func envelopeFields() throws {
        let encoded = try AuditLineEncoder.encode(
            record(
                actor: .mcp(client: "claude-desktop"),
                priorState: "working",
                newState: "warning"
            ),
            previousHash: auditGenesisHash,
            timeZone: #require(TimeZone(secondsFromGMT: 0))
        )
        let parsed = try #require(AuditTestSupport.parse(encoded.line))
        #expect(parsed["v"] as? Int == auditSchemaVersion)
        #expect(parsed["ts"] as? String == "2025-11-24T16:00:00.000+00:00")
        #expect(parsed["seq"] as? Int == 1)
        #expect(parsed["stream"] as? String == "app")
        #expect(parsed["actor"] as? String == "mcp:claude-desktop")
        #expect(parsed["event"] as? String == "enforcement.phase_changed")
        #expect(parsed["from"] as? String == "working")
        #expect(parsed["to"] as? String == "warning")
        #expect(parsed["prev"] as? String == auditGenesisHash)
    }

    @Test("The timestamp carries an explicit offset rather than normalising to UTC")
    func timestampKeepsOffset() throws {
        let encoded = AuditLineEncoder.encode(
            record(),
            previousHash: auditGenesisHash,
            timeZone: TimeZone(secondsFromGMT: -5 * 3600)!
        )
        let parsed = try #require(AuditTestSupport.parse(encoded.line))
        #expect(parsed["ts"] as? String == "2025-11-24T11:00:00.000-05:00")
    }

    @Test("Absent transition fields and empty detail are omitted, not written as null")
    func omitsEmptyFields() throws {
        let encoded = AuditLineEncoder.encode(
            record(event: .appLaunched),
            previousHash: auditGenesisHash
        )
        let parsed = try #require(AuditTestSupport.parse(encoded.line))
        #expect(parsed["from"] == nil)
        #expect(parsed["to"] == nil)
        #expect(parsed["detail"] == nil)
    }

    @Test("Detail keys are emitted in sorted order so two identical records match byte for byte")
    func detailIsDeterministic() throws {
        let detail: [String: AuditValue] = [
            "zulu": .string("z"),
            "alpha": .int(1),
            "mike": .bool(true)
        ]
        let first = try AuditLineEncoder.encode(
            record(detail: detail),
            previousHash: auditGenesisHash,
            timeZone: #require(TimeZone(secondsFromGMT: 0))
        )
        let second = try AuditLineEncoder.encode(
            record(detail: detail),
            previousHash: auditGenesisHash,
            timeZone: #require(TimeZone(secondsFromGMT: 0))
        )
        #expect(first.line == second.line)
        let alpha = try #require(first.line.range(of: "\"alpha\""))
        let mike = try #require(first.line.range(of: "\"mike\""))
        let zulu = try #require(first.line.range(of: "\"zulu\""))
        #expect(alpha.lowerBound < mike.lowerBound)
        #expect(mike.lowerBound < zulu.lowerBound)
    }

    @Test("Quotes, backslashes, and newlines in a value are escaped")
    func escapesControlCharacters() throws {
        let encoded = AuditLineEncoder.encode(
            record(detail: ["reason": .string("say \"hi\"\nback\\slash")]),
            previousHash: auditGenesisHash
        )
        #expect(encoded.line.dropLast().contains("\n") == false)
        let parsed = try #require(AuditTestSupport.parse(encoded.line))
        let detail = try #require(parsed["detail"] as? [String: Any])
        #expect(detail["reason"] as? String == "say \"hi\"\nback\\slash")
    }

    @Test("An MCP client identifier cannot forge a different actor class")
    func actorTokenIsSanitised() {
        #expect(AuditActor.mcp(client: "app\nuser").token == "mcp:app_user")
        #expect(AuditActor.mcp(client: "").token == "mcp")
        #expect(AuditActor.mcp(client: nil).token == "mcp")
        #expect(AuditActor.mcp(client: "claude-desktop_1.2").token == "mcp:claude-desktop_1.2")
    }

    // MARK: - Hash chain

    @Test("A written line verifies against its own hash")
    func lineVerifies() {
        let encoded = AuditLineEncoder.encode(
            record(priorState: "working", newState: "locked"),
            previousHash: auditGenesisHash
        )
        #expect(AuditLineEncoder.verify(line: encoded.line))
    }

    @Test("Editing any field of a written line breaks verification")
    func tamperingBreaksVerification() {
        let encoded = AuditLineEncoder.encode(
            record(priorState: "working", newState: "locked", detail: ["minutes": .int(15)]),
            previousHash: auditGenesisHash
        )
        let tampered = encoded.line.replacingOccurrences(
            of: "\"minutes\":15",
            with: "\"minutes\":99"
        )
        #expect(tampered != encoded.line)
        #expect(AuditLineEncoder.verify(line: tampered) == false)
    }

    @Test("A truncated line reads as a chain break rather than as valid")
    func truncatedLineFailsVerification() {
        let encoded = AuditLineEncoder.encode(record(), previousHash: auditGenesisHash)
        let truncated = String(encoded.line.dropLast(20))
        #expect(AuditLineEncoder.verify(line: truncated) == false)
    }

    @Test("Each record's hash becomes the next record's prev")
    func chainLinks() throws {
        let first = AuditLineEncoder.encode(
            record(sequence: 1),
            previousHash: auditGenesisHash
        )
        let second = AuditLineEncoder.encode(
            record(sequence: 2),
            previousHash: first.hash
        )
        let parsed = try #require(AuditTestSupport.parse(second.line))
        #expect(parsed["prev"] as? String == first.hash)
        #expect(AuditLineEncoder.hash(inLine: first.line) == first.hash)
    }

    @Test("The hash covers prev, so re-pointing a record at a different parent breaks it")
    func chainCoversPrev() {
        let original = AuditLineEncoder.encode(record(), previousHash: auditGenesisHash)
        let repointed = original.line.replacingOccurrences(
            of: auditGenesisHash,
            with: String(repeating: "1", count: 64)
        )
        #expect(AuditLineEncoder.verify(line: repointed) == false)
    }
}
