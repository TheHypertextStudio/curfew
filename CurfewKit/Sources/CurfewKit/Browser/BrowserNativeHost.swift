import Foundation

public nonisolated struct BrowserNativeHost: Sendable {
    private let store: BrowserNativeStore
    private let callerOrigin: String
    private let reviewTimeout: TimeInterval
    private let policyWaitTimeout: TimeInterval

    public init(
        store: BrowserNativeStore,
        callerOrigin: String,
        reviewTimeout: TimeInterval = 55,
        policyWaitTimeout: TimeInterval = 25
    ) {
        self.store = store
        self.callerOrigin = callerOrigin
        self.reviewTimeout = min(55, max(0, reviewTimeout))
        self.policyWaitTimeout = min(25, max(0, policyWaitTimeout))
    }

    public func handle(_ request: BrowserNativeRequest) async -> BrowserNativeResponse {
        var response = BrowserNativeResponse(requestID: request.requestID, type: request.type)
        do {
            switch request.type {
            case .getPolicy:
                guard var record = try store.readPolicy() else {
                    response.error = "policy_unavailable"
                    return response
                }
                if let revision = request.knownPolicyRevision, record.revision == revision {
                    guard let changed = try await store.waitForPolicyChange(
                        after: revision,
                        timeout: policyWaitTimeout
                    ) else {
                        response.error = "policy_unavailable"
                        return response
                    }
                    record = changed
                }
                response.policy = record.policy
                response.policyRevision = record.revision
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
                        let record = try store.readPolicy()
                        response.policy = record?.policy
                        response.policyRevision = record?.revision
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
