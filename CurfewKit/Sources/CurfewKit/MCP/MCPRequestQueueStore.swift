import Foundation

/// The app uses an injected queue so tests and previews never write the user's requests.
public final class MCPRequestQueueStore {
    public let recordURL: URL?
    private var memoryRequests: [MCPPendingRequest] = []
    private let beforeAcknowledgement: (() throws -> Void)?

    public init(recordURL: URL? = nil, beforeAcknowledgement: (() throws -> Void)? = nil) {
        self.recordURL = recordURL
        self.beforeAcknowledgement = beforeAcknowledgement
    }

    public static func production() -> MCPRequestQueueStore {
        MCPRequestQueueStore(recordURL: SharedPaths.mcpRequestQueue)
    }

    public func load() throws -> [MCPPendingRequest] {
        if let recordURL {
            return try MCPRequestQueue.loadChecked(from: recordURL)
        }
        return memoryRequests
    }

    public func append(_ request: MCPPendingRequest) throws {
        if let recordURL {
            return try MCPRequestQueue.append(request, to: recordURL)
        }
        if let existing = memoryRequests.first(where: { $0.id == request.id }) {
            guard existing.tool == request.tool,
                  existing.argumentsJSON == request.argumentsJSON else {
                throw MCPRequestQueueError.conflictingIdentity
            }
            return
        }
        memoryRequests.append(request)
    }

    @discardableResult
    public func acknowledge(_ request: MCPPendingRequest) throws -> Bool {
        try beforeAcknowledgement?()
        if let recordURL {
            return try MCPRequestQueue.update(request, to: recordURL)
        }
        guard let index = memoryRequests.firstIndex(where: { $0.id == request.id })
        else { return false }
        guard memoryRequests[index].tool == request.tool,
              memoryRequests[index].argumentsJSON == request.argumentsJSON else {
            throw MCPRequestQueueError.conflictingIdentity
        }
        memoryRequests[index] = request
        return true
    }
}

public enum MCPRequestQueueError: Error, LocalizedError {
    case conflictingIdentity
    case full

    public var errorDescription: String? {
        switch self {
        case .conflictingIdentity: "Request ID already belongs to a different action."
        case .full: "Request queue is full. Resolve pending requests before submitting more."
        }
    }
}
