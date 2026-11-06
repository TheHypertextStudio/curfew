import CryptoKit
import Foundation

/// An already committed local action with a queue acknowledgement pending.
public struct MCPGrantReceipt: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let tool: String
    public let argumentsSHA256: String
    public let appliedAt: Date

    public init(request: MCPPendingRequest, appliedAt: Date) {
        self.requestID = request.id
        self.tool = request.tool.rawValue
        self.argumentsSHA256 = Self.digest(request.argumentsJSON)
        self.appliedAt = appliedAt
    }

    public func matches(_ request: MCPPendingRequest) -> Bool {
        requestID == request.id && tool == request.tool.rawValue &&
            argumentsSHA256 == Self.digest(request.argumentsJSON)
    }

    public var isValid: Bool {
        isValid(for: .requestExtension)
    }

    func isValid(for expectedTool: MCPWriteTool) -> Bool {
        tool == expectedTool.rawValue && appliedAt.timeIntervalSince1970
            .isFinite &&
            argumentsSHA256.count == 64 && argumentsSHA256
            .allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum MCPGrantReceiptError: Error, LocalizedError {
    case conflictingIdentity
    case unsupportedRequest
    case legacyRequest
    case invalidGrant

    public var errorDescription: String? {
        switch self {
        case .conflictingIdentity:
            "This request ID already belongs to a different committed action."
        case .unsupportedRequest: "Only extension requests can create an extension grant receipt."
        case .legacyRequest:
            "This request predates reliable grant tracking. Submit a new request ID."
        case .invalidGrant:
            "The extension grant contains an invalid duration or budget count."
        }
    }
}

public enum MCPGrantPreparation {
    case replay(MCPGrantReceipt)
    case prepared(EnforcementRuntimeState)
}

public struct MCPGrantProposal {
    public let minutes: Int
    public let usedCount: Int
    public let resetBoundary: Date?

    public init(minutes: Int, usedCount: Int, resetBoundary: Date?) {
        self.minutes = minutes
        self.usedCount = usedCount
        self.resetBoundary = resetBoundary
    }
}

public enum MCPGrantJournal {
    public static func receipt(
        for request: MCPPendingRequest, in state: EnforcementRuntimeState
    ) throws -> MCPGrantReceipt? {
        guard let receipt = state.mcpGrantReceipts?.first(where: { $0.requestID == request.id })
        else { return nil }
        guard receipt.matches(request) else { throw MCPGrantReceiptError.conflictingIdentity }
        return receipt
    }

    public static func prepareExtension(
        _ request: MCPPendingRequest,
        state: EnforcementRuntimeState,
        proposal: MCPGrantProposal,
        appliedAt: Date
    ) throws -> MCPGrantPreparation {
        guard request.tool == .requestExtension
        else { throw MCPGrantReceiptError.unsupportedRequest }
        guard state.legacyMCPGrantRequestIDs?.contains(request.id) != true else {
            throw MCPGrantReceiptError.legacyRequest
        }
        if let existing = try receipt(for: request, in: state) {
            return .replay(existing)
        }
        let (total, overflow) = state.extensionMinutes.addingReportingOverflow(proposal.minutes)
        guard proposal.minutes > 0, !overflow, (0 ... 1_000_000).contains(total),
              (1 ... 1_000_000).contains(proposal.usedCount),
              appliedAt.timeIntervalSince1970.isFinite else {
            throw MCPGrantReceiptError.invalidGrant
        }
        var updated = state
        updated.extensionMinutes = total
        updated.extensionUses = proposal.usedCount
        updated.extensionResetBoundary = proposal.resetBoundary
        updated.mcpGrantReceipts = (state.mcpGrantReceipts ?? []) + [
            MCPGrantReceipt(request: request, appliedAt: appliedAt)
        ]
        return .prepared(updated)
    }
}
