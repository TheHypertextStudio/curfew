import Foundation

public enum PrivilegedDaemonConstants {
    public static let machServiceName = "studio.hypertext.curfew.daemon"
    public static let expectedTeamIdentifier = "39AB9DY3K8"
    public static let expectedBundleIdentifier = "studio.hypertext.curfew"
    public static let clientSigningRequirement = "anchor apple generic and "
        + "certificate leaf[subject.OU] = \"\(expectedTeamIdentifier)\" and "
        + "identifier \"\(expectedBundleIdentifier)\""
    public static let heartbeatTimeout: TimeInterval = 90
}

/// Data envelopes keep the local XPC contract stable without exposing Swift-only
/// value types to Objective-C's distributed-object bridge.
@objc public protocol CurfewDaemonXPCProtocol {
    func armLockout(_ request: Data, reply: @escaping (Data?, NSError?) -> Void)
    func heartbeat(_ request: Data, reply: @escaping (Data?, NSError?) -> Void)
    func completeLockout(_ request: Data, reason: String, reply: @escaping (Data?, NSError?) -> Void)
    func status(reply: @escaping (Data?, NSError?) -> Void)
    func prepareForUninstall(reply: @escaping (Data?, NSError?) -> Void)
}

public enum PrivilegedCompletionReason: String, Codable, Equatable, Sendable {
    case naturalExpiry = "natural_expiry"
    case approvedOverride = "approved_override"
}

public struct PrivilegedHeartbeatRequest: Codable, Equatable, Sendable {
    public let lockoutID: UUID

    public init(lockoutID: UUID) {
        self.lockoutID = lockoutID
    }
}

public struct PrivilegedDaemonStatus: Codable, Equatable, Sendable {
    public var activeRecord: LockoutDeadlineRecord?
    public var lastHeartbeatAt: Date?
    public var shutdownIssued: Bool

    public init(
        activeRecord: LockoutDeadlineRecord?,
        lastHeartbeatAt: Date?,
        shutdownIssued: Bool
    ) {
        self.activeRecord = activeRecord
        self.lastHeartbeatAt = lastHeartbeatAt
        self.shutdownIssued = shutdownIssued
    }
}

public enum PrivilegedEnforcementAction: Equatable, Sendable {
    case none
    case shutdown
}

public enum PrivilegedEnforcementError: String, Error, Equatable, Sendable {
    case activeLockout
    case invalidDeadline
    case lockoutMismatch
    case noActiveLockout
}

public struct PrivilegedEnforcementStateMachine: Sendable {
    public private(set) var status: PrivilegedDaemonStatus
    private var startedAt: Date

    public init(startedAt: Date) {
        self.startedAt = startedAt
        status = PrivilegedDaemonStatus(
            activeRecord: nil,
            lastHeartbeatAt: nil,
            shutdownIssued: false
        )
    }

    public init(record: LockoutDeadlineRecord, startedAt: Date) {
        self.startedAt = startedAt
        status = PrivilegedDaemonStatus(
            activeRecord: record,
            lastHeartbeatAt: nil,
            shutdownIssued: false
        )
    }

    public init(status: PrivilegedDaemonStatus, startedAt: Date) {
        self.startedAt = startedAt
        self.status = status
    }

    public mutating func arm(_ record: LockoutDeadlineRecord, now: Date) throws {
        guard record.scheduledUnlockAt > now,
              record.lockoutStartedAt <= record.scheduledUnlockAt
        else {
            throw PrivilegedEnforcementError.invalidDeadline
        }

        if let activeRecord = status.activeRecord,
           activeRecord.lockoutID != record.lockoutID,
           activeRecord.scheduledUnlockAt > now {
            throw PrivilegedEnforcementError.activeLockout
        }

        status = PrivilegedDaemonStatus(
            activeRecord: record,
            lastHeartbeatAt: now,
            shutdownIssued: false
        )
    }

    public mutating func heartbeat(lockoutID: UUID, now: Date) throws {
        let record = try matchingRecord(lockoutID: lockoutID)
        guard now < record.scheduledUnlockAt else {
            throw PrivilegedEnforcementError.noActiveLockout
        }
        status.lastHeartbeatAt = now
    }

    public mutating func evaluate(
        now: Date,
        heartbeatTimeout: TimeInterval = PrivilegedDaemonConstants.heartbeatTimeout
    ) -> PrivilegedEnforcementAction {
        guard let record = status.activeRecord,
              now < record.scheduledUnlockAt,
              !status.shutdownIssued
        else {
            return .none
        }

        let heartbeatReference = status.lastHeartbeatAt ?? startedAt
        guard now.timeIntervalSince(heartbeatReference) > heartbeatTimeout else {
            return .none
        }

        status.shutdownIssued = true
        return .shutdown
    }

    public mutating func complete(
        lockoutID: UUID,
        reason: PrivilegedCompletionReason,
        now: Date
    ) throws {
        let record = try matchingRecord(lockoutID: lockoutID)
        if reason == .naturalExpiry, now < record.scheduledUnlockAt {
            throw PrivilegedEnforcementError.activeLockout
        }
        status = PrivilegedDaemonStatus(
            activeRecord: nil,
            lastHeartbeatAt: nil,
            shutdownIssued: false
        )
    }

    public func prepareForUninstall(now: Date) throws {
        if let record = status.activeRecord, now < record.scheduledUnlockAt {
            throw PrivilegedEnforcementError.activeLockout
        }
    }

    private func matchingRecord(lockoutID: UUID) throws -> LockoutDeadlineRecord {
        guard let record = status.activeRecord else {
            throw PrivilegedEnforcementError.noActiveLockout
        }
        guard record.lockoutID == lockoutID else {
            throw PrivilegedEnforcementError.lockoutMismatch
        }
        return record
    }
}

public struct DaemonClientIdentityPolicy: Equatable, Sendable {
    public let expectedTeamIdentifier: String
    public let expectedBundleIdentifier: String

    public init(expectedTeamIdentifier: String, expectedBundleIdentifier: String) {
        self.expectedTeamIdentifier = expectedTeamIdentifier
        self.expectedBundleIdentifier = expectedBundleIdentifier
    }

    public func accepts(teamIdentifier: String?, bundleIdentifier: String?) -> Bool {
        teamIdentifier == expectedTeamIdentifier && bundleIdentifier == expectedBundleIdentifier
    }
}
