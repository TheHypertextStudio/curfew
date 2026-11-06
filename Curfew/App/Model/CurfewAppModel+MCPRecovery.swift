import CurfewKit
import Foundation
import OSLog

struct MCPGrantRecoveryState {
    let queue: MCPRequestQueueStore
    var receipts: [MCPGrantReceipt]
    var legacyIDs: [UUID]
    var trackingStartedAt: Date?
    var nextAttemptAt = Date.distantPast
    var isResolving = false

    init(queue: MCPRequestQueueStore, state: EnforcementRuntimeState) {
        self.queue = queue
        self.receipts = state.mcpGrantReceipts ?? []
        self.legacyIDs = state.legacyMCPGrantRequestIDs ?? []
        self.trackingStartedAt = state.mcpReceiptTrackingStartedAt
    }
}

@MainActor
extension CurfewAppModel {
    var mcpRequestQueueStore: MCPRequestQueueStore {
        mcpGrantRecovery.queue
    }

    var mcpGrantReceipts: [MCPGrantReceipt] {
        get { mcpGrantRecovery.receipts }
        set { mcpGrantRecovery.receipts = newValue }
    }

    var legacyMCPGrantRequestIDs: [UUID] {
        get { mcpGrantRecovery.legacyIDs }
        set { mcpGrantRecovery.legacyIDs = newValue }
    }

    var mcpReceiptTrackingStartedAt: Date? {
        get { mcpGrantRecovery.trackingStartedAt }
        set { mcpGrantRecovery.trackingStartedAt = newValue }
    }

    var nextMCPGrantAcknowledgementAttemptAt: Date {
        get { mcpGrantRecovery.nextAttemptAt }
        set { mcpGrantRecovery.nextAttemptAt = newValue }
    }

    var isResolvingMCPRequest: Bool {
        get { mcpGrantRecovery.isResolving }
        set { mcpGrantRecovery.isResolving = newValue }
    }

    static func queueStore(forDemo demo: Bool) -> MCPRequestQueueStore {
        RuntimeEnvironment.isUnitTestHost || demo ? MCPRequestQueueStore() : .production()
    }

    /// Recover a committed effect before today's policy or phase can reclassify the old decision.
    func recoverMCPGrantIfNeeded(_ request: MCPPendingRequest) -> Bool {
        if request.tool == .requestExtension, legacyMCPGrantRequestIDs.contains(request.id) {
            var denied = request
            denied.status = .denied
            denied.resolvedAt = currentTime
            denied.denialReason = "This request predates reliable grant tracking. " +
                "Submit a new request ID."
            if writeMCPQueueUpdate(denied) {
                acknowledgeMCPGrantReceipt(denied)
            }
            pendingMCPRequests.removeAll { $0.id == request.id }
            return true
        }
        if let receipt = mcpGrantReceipts.first(where: { $0.requestID == request.id }) {
            guard receipt.matches(request) else {
                logMCPRecoveryFailure(MCPGrantReceiptError.conflictingIdentity)
                return true
            }
            var approved = request
            approved.status = .approved
            approved.resolvedAt = receipt.appliedAt
            approved.denialReason = nil
            if writeMCPQueueUpdate(approved) {
                acknowledgeMCPGrantReceipt(approved)
            }
            pendingMCPRequests.removeAll { $0.id == request.id }
            return true
        }
        do {
            if let existing = try mcpRequestQueueStore.load()
                .first(where: { $0.id == request.id }) {
                guard existing.tool == request.tool,
                      existing.argumentsJSON == request.argumentsJSON else {
                    logMCPRecoveryFailure(MCPRequestQueueError.conflictingIdentity)
                    return true
                }
                if existing.status != .pending {
                    pendingMCPRequests.removeAll { $0.id == request.id }
                    return true
                }
            }
        } catch {
            logMCPRecoveryFailure(error)
            return true
        }
        return false
    }

    func acknowledgeMCPGrantReceipt(_ outcome: MCPPendingRequest) {
        guard runtimePersistenceError == nil else { return }
        var snapshot = runtimeStateSnapshot()
        if outcome.status == .approved {
            snapshot.mcpGrantReceipts = snapshot.mcpGrantReceipts?.filter { !$0.matches(outcome) }
        }
        if outcome.status == .denied {
            snapshot.legacyMCPGrantRequestIDs = snapshot.legacyMCPGrantRequestIDs?
                .filter { $0 != outcome.id }
        }
        if snapshot.mcpGrantReceipts?.isEmpty == true {
            snapshot.mcpGrantReceipts = nil
        }
        if snapshot.legacyMCPGrantRequestIDs?
            .isEmpty == true {
            snapshot.legacyMCPGrantRequestIDs = nil
        }
        if snapshot != runtimeStateSnapshot() {
            persistRuntimeState(snapshot)
        }
    }

    func retryMCPGrantAcknowledgementsIfDue() {
        guard !isDemoSession, !privilegedHelperManager.maintenancePaused,
              !isResolvingMCPRequest,
              runtimePersistenceError == nil,
              !mcpGrantReceipts.isEmpty || !legacyMCPGrantRequestIDs.isEmpty,
              currentTime >= nextMCPGrantAcknowledgementAttemptAt else { return }
        nextMCPGrantAcknowledgementAttemptAt = currentTime.addingTimeInterval(15)
        retryMCPGrantAcknowledgements()
    }

    func retryMCPGrantAcknowledgements() {
        do {
            let requests = try mcpRequestQueueStore.load()
            let ids = Set(mcpGrantReceipts.map(\.requestID) + legacyMCPGrantRequestIDs)
            for request in requests where ids.contains(request.id) {
                _ = recoverMCPGrantIfNeeded(request)
            }
        } catch { logMCPRecoveryFailure(error) }
    }

    private func logMCPRecoveryFailure(_ error: any Error) {
        let logger = Logger(subsystem: "studio.hypertext.curfew", category: "mcp-queue")
        logger
            .error(
                "Could not reconcile a local request: \(error.localizedDescription, privacy: .public)"
            )
    }
}
