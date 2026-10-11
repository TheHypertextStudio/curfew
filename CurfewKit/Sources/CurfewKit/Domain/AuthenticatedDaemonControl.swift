import Foundation

/// Authenticated local transport state. It never decides or executes shutdown;
/// the daemon combines its deadline with every other source before applying
/// the shared enforcement policy.
public struct AuthenticatedDaemonControl: Codable, Sendable {
    private var authenticatedHeartbeatLockoutID: UUID?
    private var releasedLocalDeadlines: [UUID: Date] = [:]

    public private(set) var localStatus: PrivilegedDaemonStatus

    public init(persisted: PrivilegedDaemonStatus? = nil) {
        self.localStatus = persisted ?? PrivilegedDaemonStatus(
            activeRecord: nil, lastHeartbeatAt: nil, shutdownIssued: false
        )
    }

    /// Once an authenticated client owns liveness, an untrusted file cannot
    /// keep that window alive. Legacy windows retain their upgrade fallback.
    public func usesAuthenticatedHeartbeat(
        for record: LockoutDeadlineRecord?, now: Date
    ) -> Bool {
        guard let record else { return false }
        if let local = localStatus.activeRecord, local.scheduledUnlockAt > now {
            return true
        }
        return authenticatedHeartbeatLockoutID == record.lockoutID
    }

    public func activeLocalCandidate(
        _ record: LockoutDeadlineRecord?,
        now: Date
    ) -> LockoutDeadlineRecord? {
        guard let record else { return nil }
        if record.kind != .remoteCommand,
           let releasedUntil = releasedLocalDeadlines[record.lockoutID], releasedUntil > now {
            return nil
        }
        return record
    }

    public mutating func arm(_ record: LockoutDeadlineRecord, now: Date) throws {
        guard activeLocalCandidate(record, now: now) != nil else {
            throw PrivilegedEnforcementError.noActiveLockout
        }
        guard record.kind != .remoteCommand,
              record.scheduledUnlockAt > now,
              record.lockoutStartedAt <= now,
              record.lockoutStartedAt <= record.scheduledUnlockAt
        else { throw PrivilegedEnforcementError.invalidDeadline }
        if let current = localStatus.activeRecord,
           current.scheduledUnlockAt > now,
           current.lockoutID != record.lockoutID {
            throw PrivilegedEnforcementError.activeLockout
        }
        localStatus.activeRecord = DaemonLockoutDeadlineResolver.resolve(
            now: now, user: localStatus.activeRecord, shadow: record, remote: nil
        )
        authenticatedHeartbeatLockoutID = record.lockoutID
        localStatus.lastHeartbeatAt = now
    }

    public mutating func heartbeat(
        lockoutID: UUID, external: LockoutDeadlineRecord?, now: Date
    ) throws {
        guard let effective = status(external: external, shutdownIssued: false, now: now)
            .activeRecord
        else { throw PrivilegedEnforcementError.noActiveLockout }
        guard effective.lockoutID == lockoutID
        else { throw PrivilegedEnforcementError.lockoutMismatch }
        authenticatedHeartbeatLockoutID = lockoutID
        localStatus.lastHeartbeatAt = now
    }

    public mutating func complete(
        lockoutID: UUID, reason: PrivilegedCompletionReason, now: Date,
        external: LockoutDeadlineRecord? = nil
    ) throws {
        if reason == .accountWakeRelease, releasedLocalDeadlines[lockoutID] != nil {
            return
        }
        guard let local = [localStatus.activeRecord, external].compactMap(\.self)
            .first(where: { $0.lockoutID == lockoutID })
        else { throw PrivilegedEnforcementError.lockoutMismatch }
        guard local.kind != .remoteCommand else { throw PrivilegedEnforcementError.activeLockout }
        let naturalExpiry = reason == .naturalExpiry && now >= local.scheduledUnlockAt
        let wakeRelease = reason == .accountWakeRelease && local.kind == .accountWakeCampaign
        guard naturalExpiry || wakeRelease
        else { throw PrivilegedEnforcementError.activeLockout }
        releasedLocalDeadlines = releasedLocalDeadlines.filter { $0.value > now }
        releasedLocalDeadlines[local.lockoutID] = local.scheduledUnlockAt
        if localStatus.activeRecord?.lockoutID == lockoutID {
            localStatus.activeRecord = nil
        }
    }

    public func prepareForUninstall(external: LockoutDeadlineRecord?, now: Date) throws {
        guard status(external: external, shutdownIssued: false, now: now).activeRecord == nil else {
            throw PrivilegedEnforcementError.activeLockout
        }
    }

    public func status(
        external: LockoutDeadlineRecord?, shutdownIssued: Bool, now: Date
    ) -> PrivilegedDaemonStatus {
        PrivilegedDaemonStatus(
            activeRecord: DaemonLockoutDeadlineResolver.resolve(
                now: now, user: localStatus.activeRecord, shadow: nil, remote: activeLocalCandidate(
                    external,
                    now: now
                )
            ),
            lastHeartbeatAt: localStatus.lastHeartbeatAt,
            shutdownIssued: shutdownIssued
        )
    }
}
