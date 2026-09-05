import CurfewProtocols
import Foundation

extension NativeAccountSyncTransport {
    static func remoteCommandAcknowledgement(
        _ result: RemoteCommandResult
    ) throws -> CurfewProtocols.DAcknowledgement {
        guard result.sequence > 0, result.sequence <= Int64(Int.max) else {
            throw NativeAccountSyncError.invalidResponse
        }
        return CurfewProtocols.DAcknowledgement(
            acknowledgedAt: wireDate(result.resolvedAt),
            commandID: result.commandID.uuidString.lowercased(),
            deviceID: result.deviceID.uuidString.lowercased(),
            sequence: Int(result.sequence),
            stage: .delivered
        )
    }

    static func remoteCommandResult(
        _ result: RemoteCommandResult
    ) throws -> CurfewProtocols.RemoteCommandResult {
        guard result.sequence > 0, result.sequence <= Int64(Int.max) else {
            throw NativeAccountSyncError.invalidResponse
        }
        let (stage, rejection) = try remoteResultDisposition(result)
        return CurfewProtocols.RemoteCommandResult(
            appliedDeadline: result.appliedDeadline.map(wireDate),
            commandID: result.commandID.uuidString.lowercased(),
            deviceID: result.deviceID.uuidString.lowercased(),
            resolvedAt: wireDate(result.resolvedAt),
            sequence: Int(result.sequence),
            stage: stage,
            rejectionCode: rejection
        )
    }

    static func remoteCommandEnrollment(
        _ receipt: NativeDeviceEnrollmentReceipt
    ) throws -> RemoteCommandEnrollment {
        guard !receipt.userID.isEmpty,
              receipt.userID.count <= 128,
              let deviceID = UUID(uuidString: receipt.deviceID)
        else { throw NativeAccountSyncError.invalidResponse }
        return RemoteCommandEnrollment(userID: receipt.userID, deviceID: deviceID)
    }

    static func remoteCommandDeliveries(
        _ batch: RemoteCommandDeliveryBatch
    ) -> [PendingRemoteCommandDelivery] {
        batch.commands.map { delivery in
            PendingRemoteCommandDelivery(
                cursor: delivery.cursor,
                envelope: SignedRemoteLockoutCommandEnvelope(
                    compactJWS: delivery.commandEnvelope.compactJws
                )
            )
        }
    }

    static func wakeStatus(_ value: WakeStatus) throws -> AccountWakeStatusUpdate {
        guard let campaignID = UUID(uuidString: value.campaignID),
              let updatedAt = date(value.updatedAt)
        else { throw NativeAccountSyncError.invalidResponse }
        let selected = try value.selectedDeviceIDS.map { identifier in
            guard let value = UUID(uuidString: identifier) else {
                throw NativeAccountSyncError.invalidResponse
            }
            return value
        }
        let state: AccountWakeCampaignState = switch value.state {
        case .scheduled: .scheduled
        case .ringingAttempt: .ringingAttempt
        case .quietInterval: .quietInterval
        case .satisfied: .satisfied
        case .overridden: .overridden
        }
        return AccountWakeStatusUpdate(
            campaignID: campaignID,
            state: state,
            attemptNumber: value.attemptNumber,
            selectedDeviceIDs: selected,
            statusVersion: value.statusVersion,
            updatedAt: updatedAt
        )
    }

    static func remoteOverride(_ value: RemoteOverride) throws -> AccountRemoteOverride {
        guard let overrideID = UUID(uuidString: value.overrideID),
              let requestID = UUID(uuidString: value.requestID),
              let startsAt = date(value.startsAt)
        else { throw NativeAccountSyncError.invalidResponse }
        let targets = try value.targetDeviceIDS.map { identifier in
            guard let value = UUID(uuidString: identifier) else {
                throw NativeAccountSyncError.invalidResponse
            }
            return value
        }
        let authorization: AccountRemoteOverride.AuthorizedBy = switch value.authorizedBy {
        case .freshWebAal2: .freshWebAAL2
        case .mcpUserApproval: .mcpUserApproval
        case .mcpPreauthorizedClient: .mcpPreauthorizedClient
        }
        let status: AccountRemoteOverride.Status = switch value.status {
        case .active: .active
        case .cancelled: .cancelled
        case .expired: .expired
        }
        return AccountRemoteOverride(
            overrideID: overrideID,
            requestID: requestID,
            targetDeviceIDs: targets,
            reason: value.reason,
            durationMinutes: value.durationMinutes,
            startsAt: startsAt,
            authorizedBy: authorization,
            status: status
        )
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func remoteResultDisposition(
        _ result: RemoteCommandResult
    ) throws -> (
        CurfewProtocols.RemoteCommandResultStage,
        CurfewProtocols.RejectionCode?
    ) {
        switch result.stage {
        case .applied:
            try appliedDisposition(result)
        case .expired:
            try expiredDisposition(result)
        case .rejected:
            try rejectedDisposition(result)
        }
    }

    private static func appliedDisposition(
        _ result: RemoteCommandResult
    ) throws -> (CurfewProtocols.RemoteCommandResultStage, CurfewProtocols.RejectionCode?) {
        guard result.appliedDeadline != nil, result.rejectionCode == nil else {
            throw NativeAccountSyncError.invalidResponse
        }
        return (.applied, nil)
    }

    private static func expiredDisposition(
        _ result: RemoteCommandResult
    ) throws -> (CurfewProtocols.RemoteCommandResultStage, CurfewProtocols.RejectionCode?) {
        guard result.appliedDeadline == nil, result.rejectionCode == nil else {
            throw NativeAccountSyncError.invalidResponse
        }
        return (.expired, nil)
    }

    private static func rejectedDisposition(
        _ result: RemoteCommandResult
    ) throws -> (CurfewProtocols.RemoteCommandResultStage, CurfewProtocols.RejectionCode?) {
        guard result.appliedDeadline == nil, let code = result.rejectionCode else {
            throw NativeAccountSyncError.invalidResponse
        }
        let rejection: CurfewProtocols.RejectionCode = switch code {
        case .deviceUnavailable: .deviceUnavailable
        case .ineligible: .ineligible
        case .invalidDeadline: .invalidDeadline
        case .invalidSignature: .invalidSignature
        case .outOfOrder: .outOfOrder
        case .staleStatus: .staleStatus
        }
        return (.rejected, rejection)
    }

    private static func wireDate(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: value)
    }
}
