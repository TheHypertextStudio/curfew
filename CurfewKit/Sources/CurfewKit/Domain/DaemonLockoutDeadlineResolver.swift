import Foundation

/// Resolves all daemon-managed lockout sources with strengthening-only semantics.
public enum DaemonLockoutDeadlineResolver {
    public static func resolve(
        now: Date,
        user: LockoutDeadlineRecord?,
        shadow: LockoutDeadlineRecord?,
        remote: LockoutDeadlineRecord?
    ) -> LockoutDeadlineRecord? {
        let active = [user, shadow, remote]
            .compactMap(\.self)
            .filter { $0.scheduledUnlockAt > now }
        guard let strongest = active.max(by: {
            $0.scheduledUnlockAt < $1.scheduledUnlockAt
        }) else { return nil }

        return LockoutDeadlineRecord(
            lockoutStartedAt: active.map(\.lockoutStartedAt).min() ?? strongest.lockoutStartedAt,
            scheduledUnlockAt: strongest.scheduledUnlockAt,
            kind: strongest.kind,
            campaignID: strongest.campaignID
        )
    }
}

/// Projects only a daemon-authenticated successful result into the running
/// app's durable lockout view. Other devices and terminal failures are never
/// allowed to mutate local enforcement.
public enum RemoteCommandLockoutProjection {
    public static func resolve(
        result: RemoteCommandResult,
        enrolledDeviceID: UUID,
        now: Date,
        current: LockoutDeadlineRecord?
    ) -> LockoutDeadlineRecord? {
        guard result.deviceID == enrolledDeviceID,
              result.stage == .applied,
              result.rejectionCode == nil,
              let deadline = result.appliedDeadline,
              deadline > now,
              result.resolvedAt <= now.addingTimeInterval(60)
        else { return current }
        let remote = LockoutDeadlineRecord(
            lockoutStartedAt: min(result.resolvedAt, now),
            scheduledUnlockAt: deadline,
            kind: .remoteCommand
        )
        return DaemonLockoutDeadlineResolver.resolve(
            now: now,
            user: current,
            shadow: nil,
            remote: remote
        )
    }
}
