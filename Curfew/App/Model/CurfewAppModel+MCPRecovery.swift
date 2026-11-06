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
    var scheduleError: String?

    init(
        queue: MCPRequestQueueStore,
        state: EnforcementRuntimeState,
        scheduleError: String? = nil
    ) {
        self.queue = queue
        self.scheduleError = scheduleError
        self.receipts = state.mcpGrantReceipts ?? []
        self.legacyIDs = state.legacyMCPGrantRequestIDs ?? []
        self.trackingStartedAt = state.mcpReceiptTrackingStartedAt
    }
}

@MainActor
extension CurfewAppModel {
    var schedulePersistenceError: String? {
        get { mcpGrantRecovery.scheduleError }
        set { mcpGrantRecovery.scheduleError = newValue }
    }

    static func loadSchedule(
        _ store: CurfewSettingsStore, _ queue: MCPRequestQueueStore
    ) -> (CurfewSettings, String?) {
        do {
            try store.prepareScheduleRecovery(queue: queue)
            return try (store.loadChecked(), nil)
        } catch {
            return (store.load(), error.localizedDescription)
        }
    }

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

    func recoverMCPScheduleIfNeeded(_ request: MCPPendingRequest) -> Bool {
        guard request.tool == .setSchedule else { return false }
        guard schedulePersistenceError == nil else { return true }
        do {
            guard let outcome = try settingsStore.recoverScheduleOutcome(
                for: request, now: currentTime
            ) else { return false }
            if writeMCPQueueUpdate(outcome) {
                try settingsStore.acknowledgeScheduleOutcome(outcome)
            }
            pendingMCPRequests.removeAll { $0.id == request.id }
        } catch {
            logMCPRecoveryFailure(error)
        }
        return true
    }

    func retryMCPGrantAcknowledgementsIfDue() {
        guard !isDemoSession, !privilegedHelperManager.maintenancePaused,
              !isResolvingMCPRequest,
              currentTime >= nextMCPGrantAcknowledgementAttemptAt else { return }
        nextMCPGrantAcknowledgementAttemptAt = currentTime.addingTimeInterval(15)
        retryMCPGrantAcknowledgements()
    }

    func retryMCPGrantAcknowledgements() {
        do {
            let scheduleIDs = (try? settingsStore.scheduleRecoveryIDs()) ?? []
            let grantIDs = runtimePersistenceError == nil
                ? Set(mcpGrantReceipts.map(\.requestID) + legacyMCPGrantRequestIDs) : []
            guard !scheduleIDs.isEmpty || !grantIDs.isEmpty else { return }
            let requests = try mcpRequestQueueStore.load()
            for request in requests {
                if scheduleIDs.contains(request.id) {
                    _ = recoverMCPScheduleIfNeeded(request)
                } else if grantIDs.contains(request.id) {
                    _ = recoverMCPGrantIfNeeded(request)
                }
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
