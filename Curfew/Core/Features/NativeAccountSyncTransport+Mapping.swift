import CurfewProtocols
import Foundation

extension NativeAccountSyncTransport {
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
}
