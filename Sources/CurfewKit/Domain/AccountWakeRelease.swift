import Foundation

/// The v2 morning release authority stored in decrypted local settings.
///
/// This is an app-domain projection, not a second wire contract. The
/// `CurfewProtocolBridge` target is the only code that maps generated
/// `CurfewProtocols.ReleasePolicy` values into this type.
public struct MorningReleasePolicy: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case fixedUnlock = "fixed_unlock"
        case wakeCampaign = "wake_campaign"
    }

    public let kind: Kind
    public let timeZone: String
    public let localUnlockTime: String?
    public let campaignTemplateID: UUID?
    public let localStartTime: String?

    private enum CodingKeys: String, CodingKey {
        case kind
        case timeZone
        case localUnlockTime
        case campaignTemplateID
        case localStartTime
    }

    public init(
        kind: Kind,
        timeZone: String,
        localUnlockTime: String?,
        campaignTemplateID: UUID?,
        localStartTime: String?
    ) throws {
        guard TimeZone(identifier: timeZone) != nil,
              timeZone.contains("/")
        else {
            throw MorningReleasePolicyError.invalidTimeZone
        }
        switch kind {
        case .fixedUnlock:
            guard let localUnlockTime,
                  Self.isLocalTime(localUnlockTime),
                  campaignTemplateID == nil,
                  localStartTime == nil
            else {
                throw MorningReleasePolicyError.conflictingAuthority
            }
        case .wakeCampaign:
            guard localUnlockTime == nil,
                  campaignTemplateID != nil,
                  let localStartTime,
                  Self.isLocalTime(localStartTime)
            else {
                throw MorningReleasePolicyError.conflictingAuthority
            }
        }
        self.kind = kind
        self.timeZone = timeZone
        self.localUnlockTime = localUnlockTime
        self.campaignTemplateID = campaignTemplateID
        self.localStartTime = localStartTime
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            kind: values.decode(Kind.self, forKey: .kind),
            timeZone: values.decode(String.self, forKey: .timeZone),
            localUnlockTime: values.decodeIfPresent(String.self, forKey: .localUnlockTime),
            campaignTemplateID: values.decodeIfPresent(UUID.self, forKey: .campaignTemplateID),
            localStartTime: values.decodeIfPresent(String.self, forKey: .localStartTime)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        try values.encode(timeZone, forKey: .timeZone)
        try values.encodeIfPresent(localUnlockTime, forKey: .localUnlockTime)
        try values.encodeIfPresent(campaignTemplateID, forKey: .campaignTemplateID)
        try values.encodeIfPresent(localStartTime, forKey: .localStartTime)
    }

    public static func fixedUnlock(
        timeZone: String,
        localUnlockTime: String
    ) throws -> MorningReleasePolicy {
        try MorningReleasePolicy(
            kind: .fixedUnlock,
            timeZone: timeZone,
            localUnlockTime: localUnlockTime,
            campaignTemplateID: nil,
            localStartTime: nil
        )
    }

    public static func wakeCampaign(
        campaignTemplateID: UUID,
        timeZone: String,
        localStartTime: String
    ) throws -> MorningReleasePolicy {
        try MorningReleasePolicy(
            kind: .wakeCampaign,
            timeZone: timeZone,
            localUnlockTime: nil,
            campaignTemplateID: campaignTemplateID,
            localStartTime: localStartTime
        )
    }

    private static func isLocalTime(_ value: String) -> Bool {
        value.range(
            of: #"^([01][0-9]|2[0-3]):[0-5][0-9]$"#,
            options: .regularExpression
        ) != nil
    }
}

public enum MorningReleasePolicyError: Error, Equatable, Sendable {
    case invalidTimeZone
    case conflictingAuthority
}

/// Public enrollment metadata only. Private device keys and the account root
/// key live in Keychain through `AccountDeviceKeyStore`.
public struct AccountDeviceEnrollment: Codable, Equatable, Sendable {
    public let deviceID: UUID
    public let keyEpoch: Int
    public let enrolledAt: Date

    public init(deviceID: UUID, keyEpoch: Int, enrolledAt: Date) {
        self.deviceID = deviceID
        self.keyEpoch = keyEpoch
        self.enrolledAt = enrolledAt
    }
}

/// Optional account state. A missing enrollment preserves Curfew's existing
/// local/account-free behavior.
public struct AccountSyncConfiguration: Codable, Equatable, Sendable {
    public var enrollment: AccountDeviceEnrollment?
    public var releasePolicy: MorningReleasePolicy?

    public init(
        enrollment: AccountDeviceEnrollment?,
        releasePolicy: MorningReleasePolicy?
    ) {
        self.enrollment = enrollment
        self.releasePolicy = releasePolicy
    }

    public static let accountFree = AccountSyncConfiguration(
        enrollment: nil,
        releasePolicy: nil
    )

    public var isEnrolled: Bool {
        enrollment != nil
    }

    public var usesWakeCampaign: Bool {
        isEnrolled && releasePolicy?.kind == .wakeCampaign
    }
}

public enum SyncAuthority: Equatable, Sendable {
    case localOnly
    case curfewAccount
}

public enum SyncAuthorityResolver {
    public static func resolve(account: AccountSyncConfiguration) -> SyncAuthority {
        account.isEnrolled ? .curfewAccount : .localOnly
    }

    public static func allowsCloudKit(account: AccountSyncConfiguration) -> Bool {
        resolve(account: account) != .curfewAccount
    }
}

/// App-domain projection of the generated WakeStatus. The coordinator keeps
/// this privacy-minimal state server-readable so devices can converge and
/// release at the deterministic deadline without decrypting a settings record.
public struct AccountWakeStatusUpdate: Codable, Equatable, Sendable {
    public let campaignID: UUID
    public let state: AccountWakeCampaignState
    public let attemptNumber: Int
    public let maximumAttempts: Int
    public let selectedDeviceIDs: [UUID]
    public let finalDeadlineAt: Date
    public let statusVersion: Int
    public let updatedAt: Date

    public init(
        campaignID: UUID,
        state: AccountWakeCampaignState,
        attemptNumber: Int,
        maximumAttempts: Int,
        selectedDeviceIDs: [UUID],
        finalDeadlineAt: Date,
        statusVersion: Int,
        updatedAt: Date
    ) {
        self.campaignID = campaignID
        self.state = state
        self.attemptNumber = attemptNumber
        self.maximumAttempts = maximumAttempts
        self.selectedDeviceIDs = selectedDeviceIDs
        self.finalDeadlineAt = finalDeadlineAt
        self.statusVersion = statusVersion
        self.updatedAt = updatedAt
    }
}

public enum AccountWakeCampaignState: String, Codable, Equatable, Sendable {
    case scheduled
    case ringingAttempt = "ringing_attempt"
    case quietInterval = "quiet_interval"
    case satisfied
    case exhausted
    case overridden

    public var isTerminal: Bool {
        switch self {
        case .satisfied, .exhausted, .overridden:
            true
        case .scheduled, .ringingAttempt, .quietInterval:
            false
        }
    }
}

public enum AccountWakeLedgerError: Error, Equatable, Sendable {
    case invalidUpdate
    case staleCampaign
    case staleStatusVersion
    case deadlineChanged
    case terminalRollback
}

/// Defensive local replay/rollback gate for authenticated coordinator state.
/// A cached or reordered frame cannot weaken an active morning gate.
public struct AccountWakeLedger: Codable, Equatable, Sendable {
    public private(set) var current: AccountWakeStatusUpdate?

    public init(current: AccountWakeStatusUpdate? = nil) {
        self.current = current
    }

    public mutating func accept(_ update: AccountWakeStatusUpdate, now _: Date) throws {
        guard update.statusVersion >= 1,
              (1 ... 24).contains(update.maximumAttempts),
              (0 ... update.maximumAttempts).contains(update.attemptNumber),
              !update.selectedDeviceIDs.isEmpty,
              Set(update.selectedDeviceIDs).count == update.selectedDeviceIDs.count,
              update.finalDeadlineAt > update.updatedAt
        else {
            throw AccountWakeLedgerError.invalidUpdate
        }

        guard let current else {
            current = update
            return
        }
        guard current.campaignID == update.campaignID else {
            guard current.state.isTerminal,
                  update.finalDeadlineAt > current.finalDeadlineAt,
                  update.updatedAt > current.updatedAt
            else {
                throw AccountWakeLedgerError.staleCampaign
            }
            self.current = update
            return
        }
        guard update.statusVersion > current.statusVersion else {
            throw AccountWakeLedgerError.staleStatusVersion
        }
        guard update.finalDeadlineAt == current.finalDeadlineAt else {
            throw AccountWakeLedgerError.deadlineChanged
        }
        guard !current.state.isTerminal || update.state.isTerminal else {
            throw AccountWakeLedgerError.terminalRollback
        }
        self.current = update
    }
}

public struct AccountRemoteOverride: Codable, Equatable, Sendable {
    public enum AuthorizedBy: String, Codable, Sendable {
        case freshWebAAL2 = "fresh_web_aal2"
        case mcpUserApproval = "mcp_user_approval"
        case mcpPreauthorizedClient = "mcp_preauthorized_client"
    }

    public enum Status: String, Codable, Sendable {
        case active
        case expired
        case cancelled
    }

    public let overrideID: UUID
    public let requestID: UUID
    public let targetDeviceIDs: [UUID]
    public let reason: String
    public let durationMinutes: Int
    public let startsAt: Date
    public let authorizedBy: AuthorizedBy
    public let status: Status

    public init(
        overrideID: UUID,
        requestID: UUID,
        targetDeviceIDs: [UUID],
        reason: String,
        durationMinutes: Int,
        startsAt: Date,
        authorizedBy: AuthorizedBy,
        status: Status
    ) {
        self.overrideID = overrideID
        self.requestID = requestID
        self.targetDeviceIDs = targetDeviceIDs
        self.reason = reason
        self.durationMinutes = durationMinutes
        self.startsAt = startsAt
        self.authorizedBy = authorizedBy
        self.status = status
    }

    public func authorizes(deviceID: UUID, at date: Date) -> Bool {
        status == .active
            && (5 ... 60).contains(durationMinutes)
            && targetDeviceIDs.contains(deviceID)
            && date >= startsAt
            && date < startsAt.addingTimeInterval(TimeInterval(durationMinutes * 60))
    }
}

public enum WakeReleaseReason: Equatable, Sendable {
    case satisfied
    case exhausted
    case authorizedOverride
    case finalDeadline
}

public enum WakeReleaseDecision: Equatable, Sendable {
    case legacyFixedUnlock
    case hold(until: Date)
    case release(WakeReleaseReason)
}

/// Chooses the one durable morning release clock when an evening lock begins.
public enum WakeLockoutDeadlineResolver {
    public static func record(
        lockoutStartedAt: Date,
        scheduleUnlockAt: Date,
        account: AccountSyncConfiguration,
        wakeStatus: AccountWakeStatusUpdate?
    ) -> LockoutDeadlineRecord {
        guard account.usesWakeCampaign else {
            return LockoutDeadlineRecord(
                lockoutStartedAt: lockoutStartedAt,
                scheduledUnlockAt: scheduleUnlockAt,
                kind: .scheduledTime
            )
        }
        return LockoutDeadlineRecord(
            lockoutStartedAt: lockoutStartedAt,
            scheduledUnlockAt: wakeStatus?.finalDeadlineAt ?? scheduleUnlockAt,
            kind: .accountWakeCampaign,
            campaignID: wakeStatus?.campaignID
        )
    }
}

public struct WakeReleaseEngine {
    public init() {}

    public func decision(
        at date: Date,
        deadline: LockoutDeadlineRecord,
        wakeStatus: AccountWakeStatusUpdate?,
        remoteOverride: AccountRemoteOverride?,
        localDeviceID: UUID
    ) -> WakeReleaseDecision {
        guard deadline.kind == .accountWakeCampaign else {
            return .legacyFixedUnlock
        }
        if date >= deadline.scheduledUnlockAt {
            return .release(.finalDeadline)
        }
        if remoteOverride?.authorizes(deviceID: localDeviceID, at: date) == true {
            return .release(.authorizedOverride)
        }
        guard let wakeStatus,
              wakeStatus.campaignID == deadline.campaignID
        else {
            return .hold(until: deadline.scheduledUnlockAt)
        }
        switch wakeStatus.state {
        case .satisfied:
            return .release(.satisfied)
        case .exhausted:
            return .release(.exhausted)
        case .overridden:
            return .release(.authorizedOverride)
        case .scheduled, .ringingAttempt, .quietInterval:
            return .hold(until: deadline.scheduledUnlockAt)
        }
    }
}
