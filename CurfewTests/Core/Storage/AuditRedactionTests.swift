@testable import Curfew
import Foundation
import Testing

/// Guards the privacy line the audit log is not allowed to cross.
///
/// Curfew's whole pitch is that nothing leaves the machine and that the
/// reflection prose is the user's alone. A plain-text log in
/// `~/Library/Logs` is the file most likely to be copied into a support
/// thread, so anything a human typed has to be reduced to a length and a
/// digest before it reaches a line.
struct AuditRedactionTests {
    private let prose = """
    I need thirty more minutes because the deployment window closes at \
    midnight and the rollback script is only half written.
    """

    @Test("Redaction yields a length and a digest, and never the text")
    func redactionKeepsNoProse() {
        let detail = AuditRedaction.redactedDetail(prose, prefix: "reason")
        #expect(detail["reasonLength"] == .int(prose.count))
        #expect(detail["reasonDigest"] != nil)
        for value in detail.values {
            guard case .string(let text) = value else { continue }
            #expect(prose.contains(text) == false)
            #expect(text.count == 16)
        }
    }

    @Test("The digest is stable and 16 hex characters")
    func digestIsStable() throws {
        let first = try #require(AuditRedaction.digest(prose))
        let second = try #require(AuditRedaction.digest(prose))
        #expect(first == second)
        // One regex rather than a length check plus `allSatisfy`: the
        // rethrowing overload of `allSatisfy` does not survive `#expect`'s
        // autoclosure expansion, and this states the same contract anyway.
        #expect(first.range(of: "^[0-9a-f]{16}$", options: .regularExpression) != nil)
        #expect(AuditRedaction.digest("") == nil)
    }

    @Test("Different prose produces a different digest, so grants can be told apart")
    func digestDiscriminates() {
        #expect(AuditRedaction.digest(prose) != AuditRedaction.digest(prose + "."))
    }

    @Test("An encoded override record contains the length and digest but not the prose")
    func encodedOverrideLineIsClean() {
        var detail = AuditRedaction.redactedDetail(prose, prefix: "reason")
        detail["minutes"] = .int(20)
        let line = AuditLineEncoder.encode(
            AuditRecord(
                stream: .app,
                timestamp: Date(timeIntervalSince1970: 1_764_000_000),
                actor: .user,
                event: .overrideGranted,
                detail: detail
            ),
            previousHash: auditGenesisHash
        ).line

        #expect(line.contains("deployment window") == false)
        #expect(line.contains("rollback") == false)
        #expect(line.contains("\"reasonLength\":\(prose.count)"))
        #expect(line.contains("\"minutes\":20"))
    }

    @Test("MCP arguments are digested too, since the payload is untrusted external text")
    func mcpArgumentsAreRedacted() {
        let arguments = #"{"weekday":"monday","note":"tell nobody about project raincloud"}"#
        let detail = AuditRedaction.redactedDetail(arguments, prefix: "arguments")
        let line = AuditLineEncoder.encode(
            AuditRecord(
                stream: .app,
                timestamp: Date(timeIntervalSince1970: 1_764_000_000),
                actor: .mcp(client: nil),
                event: .mcpRequestReceived,
                detail: detail
            ),
            previousHash: auditGenesisHash
        ).line

        #expect(line.contains("raincloud") == false)
        #expect(line.contains("\"argumentsDigest\""))
    }
}
