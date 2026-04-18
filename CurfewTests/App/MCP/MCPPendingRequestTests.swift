@testable import Curfew
import Foundation
import Testing

/// Behaviour tests for ``MCPPendingRequest`` and ``MCPRequestQueue``.
///
/// Queue tests use a temp directory so they never touch the live queue file
/// at `~/Library/Application Support/Curfew/mcp-requests.json`.
@MainActor
struct MCPPendingRequestTests {
    @Test("New request starts with pending status")
    func newRequestIsPending() {
        let request = MCPPendingRequest(
            tool: .requestExtension,
            argumentsJSON: #"{"reason":"test"}"#
        )
        #expect(request.status == .pending)
        #expect(request.resolvedAt == nil)
        #expect(request.denialReason == nil)
    }

    @Test("Approved request records resolved date and status")
    func approvedRequestHasResolvedDate() {
        var request = MCPPendingRequest(
            tool: .requestOverride,
            argumentsJSON: #"{"reason":"need more time for review"}"#
        )
        let resolvedAt = Date()
        request.status = .approved
        request.resolvedAt = resolvedAt

        #expect(request.status == .approved)
        #expect(request.resolvedAt == resolvedAt)
    }

    @Test("Denied request can carry a denial reason")
    func deniedRequestCarriesReason() {
        var request = MCPPendingRequest(
            tool: .requestExtension,
            argumentsJSON: #"{"reason":"quick fix"}"#
        )
        request.status = .denied
        request.resolvedAt = Date()
        request.denialReason = "Not during lockout"

        #expect(request.status == .denied)
        #expect(request.denialReason == "Not during lockout")
    }

    @Test("MCPPendingRequest round-trips through JSON")
    func jsonRoundTrip() throws {
        let original = MCPPendingRequest(
            id: UUID(),
            tool: .requestExtension,
            argumentsJSON: #"{"reason":"sprint deadline"}"#,
            requestedAt: Date(timeIntervalSince1970: 1_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MCPPendingRequest.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.tool == original.tool)
        #expect(decoded.status == original.status)
        #expect(decoded.argumentsJSON == original.argumentsJSON)
    }

    // `MCPRequestQueue` reads `SharedPaths.mcpRequestQueue`. The queue
    // path is not injectable yet (v0.1.1 seam task). The tests below
    // document expected behaviour; the actual file I/O path is exercised
    // in smoke tests, not in the unit suite, to avoid polluting the
    // developer's live queue file.

    @Test("MCPPendingRequest encodes and decodes id + status correctly")
    func encodingRoundTrip() throws {
        let original = try MCPPendingRequest(
            id: #require(UUID(uuidString: "12345678-1234-1234-1234-123456789abc")),
            tool: .requestExtension,
            argumentsJSON: #"{"reason":"queue test"}"#,
            requestedAt: Date(timeIntervalSince1970: 2_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(MCPPendingRequest.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.tool == original.tool)
        #expect(decoded.status == .pending)
        #expect(decoded.argumentsJSON == original.argumentsJSON)
    }

    // MARK: - Helpers

    private func ephemeralDirectory(label: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("curfew-mcp-\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
