import CurfewKit
import CurfewProtocols
import Foundation

public enum ProtocolV2BridgeError: Error, Equatable, Sendable {
    case invalidDate(String)
    case invalidIdentifier(String)
    case invalidRemoteOverride
    case unsupportedDSTResolution
}

/// The one conversion boundary between generated v2 wire values and Curfew's
/// app-domain values. Wire Codable behavior remains owned by CurfewProtocols.
public enum ProtocolV2Bridge {
    public static func releasePolicy(
        _ value: CurfewProtocols.ReleasePolicy
    ) throws -> MorningReleasePolicy {
        guard value.dstResolution.gap == .firstValidInstant,
              value.dstResolution.overlap == .firstOccurrence
        else {
            throw ProtocolV2BridgeError.unsupportedDSTResolution
        }
        switch value.kind {
        case .fixedUnlock:
            guard let localUnlockTime = value.localUnlockTime else {
                throw MorningReleasePolicyError.conflictingAuthority
            }
            return try .fixedUnlock(
                timeZone: value.timeZone,
                localUnlockTime: localUnlockTime
            )
        case .wakeCampaign:
            guard let campaignTemplateID = uuid(
                value.campaignTemplateID,
                field: "campaignTemplateId"
            ), let localStartTime = value.localStartTime
            else {
                throw MorningReleasePolicyError.conflictingAuthority
            }
            return try .wakeCampaign(
                campaignTemplateID: campaignTemplateID,
                timeZone: value.timeZone,
                localStartTime: localStartTime
            )
        }
    }

    public static func wakeStatus(
        _ value: CurfewProtocols.WakeStatus
    ) throws -> AccountWakeStatusUpdate {
        guard let campaignID = uuid(value.campaignID, field: "campaignId") else {
            throw ProtocolV2BridgeError.invalidIdentifier("campaignId")
        }
        let selectedDeviceIDs = try value.selectedDeviceIDS.map { identifier in
            guard let value = uuid(identifier, field: "selectedDeviceIds") else {
                throw ProtocolV2BridgeError.invalidIdentifier("selectedDeviceIds")
            }
            return value
        }
        return try AccountWakeStatusUpdate(
            campaignID: campaignID,
            state: wakeState(value.state),
            attemptNumber: value.attemptNumber,
            maximumAttempts: value.maximumAttempts,
            selectedDeviceIDs: selectedDeviceIDs,
            finalDeadlineAt: date(value.finalDeadlineAt, field: "finalDeadlineAt"),
            statusVersion: value.statusVersion,
            updatedAt: date(value.updatedAt, field: "updatedAt")
        )
    }

    public static func remoteOverride(
        _ value: CurfewProtocols.RemoteOverride
    ) throws -> AccountRemoteOverride {
        guard let overrideID = uuid(value.overrideID, field: "overrideId"),
              let requestID = uuid(value.requestID, field: "requestId"),
              (5 ... 60).contains(value.durationMinutes),
              !value.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ProtocolV2BridgeError.invalidRemoteOverride
        }
        let targetDeviceIDs = try value.targetDeviceIDS.map { identifier in
            guard let value = uuid(identifier, field: "targetDeviceIds") else {
                throw ProtocolV2BridgeError.invalidIdentifier("targetDeviceIds")
            }
            return value
        }
        guard !targetDeviceIDs.isEmpty,
              Set(targetDeviceIDs).count == targetDeviceIDs.count
        else {
            throw ProtocolV2BridgeError.invalidRemoteOverride
        }
        return try AccountRemoteOverride(
            overrideID: overrideID,
            requestID: requestID,
            targetDeviceIDs: targetDeviceIDs,
            reason: value.reason,
            durationMinutes: value.durationMinutes,
            startsAt: date(value.startsAt, field: "startsAt"),
            authorizedBy: authorization(value.authorizedBy),
            status: overrideStatus(value.status)
        )
    }

    private static func wakeState(
        _ value: CurfewProtocols.WakeCampaignState
    ) -> AccountWakeCampaignState {
        switch value {
        case .scheduled: .scheduled
        case .ringingAttempt: .ringingAttempt
        case .quietInterval: .quietInterval
        case .satisfied: .satisfied
        case .exhausted: .exhausted
        case .overridden: .overridden
        }
    }

    private static func authorization(
        _ value: CurfewProtocols.AuthorizedBy
    ) -> AccountRemoteOverride.AuthorizedBy {
        switch value {
        case .freshWebAal2: .freshWebAAL2
        case .mcpUserApproval: .mcpUserApproval
        case .mcpPreauthorizedClient: .mcpPreauthorizedClient
        }
    }

    private static func overrideStatus(
        _ value: CurfewProtocols.OverrideStatus
    ) -> AccountRemoteOverride.Status {
        switch value {
        case .active: .active
        case .expired: .expired
        case .cancelled: .cancelled
        }
    }

    private static func uuid(_ value: String?, field _: String) -> UUID? {
        value.flatMap(UUID.init(uuidString:))
    }

    private static func date(_ value: String, field: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: value) {
            return result
        }
        formatter.formatOptions = [.withInternetDateTime]
        guard let result = formatter.date(from: value) else {
            throw ProtocolV2BridgeError.invalidDate(field)
        }
        return result
    }
}
