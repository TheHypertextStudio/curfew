import Foundation

public nonisolated struct BrowserNativeHost: Sendable {
    private let store: BrowserNativeStore
    private let callerOrigin: String
    private let reviewTimeout: TimeInterval

    public init(store: BrowserNativeStore, callerOrigin: String, reviewTimeout: TimeInterval = 55) {
        self.store = store
        self.callerOrigin = callerOrigin
        self.reviewTimeout = min(55, max(0, reviewTimeout))
    }

    public func handle(_ request: BrowserNativeRequest) async -> BrowserNativeResponse {
        var response = BrowserNativeResponse(requestID: request.requestID, type: request.type)
        do {
            switch request.type {
            case .getPolicy:
                guard let record = try store.readPolicy() else {
                    response.error = "policy_unavailable"
                    return response
                }
                response.policy = record.policy
                response.generatedAt = record.generatedAt
            case .heartbeat:
                try store.recordHeartbeat(origin: callerOrigin, at: Date())
            case .reviewDestination:
                let id = try store.enqueue(request, at: Date())
                let deadline = ContinuousClock.now.advanced(by: .seconds(reviewTimeout))
                while ContinuousClock.now < deadline, !Task.isCancelled {
                    guard try store.isActive()
                    else { throw BrowserNativeError.inactiveInstallation }
                    if let entry = try store.response(id: id) {
                        response.result = entry.result
                        response.policy = try store.readPolicy()?.policy
                        return response
                    }
                    try await Task.sleep(for: .milliseconds(25))
                }
                try store.resolve(
                    id: id,
                    result: .init(decision: "deny", reason: "The review timed out."),
                    at: Date()
                )
                response.error = "review_timeout"
            }
        } catch {
            response.error = "host_unavailable"
        }
        return response
    }
}
