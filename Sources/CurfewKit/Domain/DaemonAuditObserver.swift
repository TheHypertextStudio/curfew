import Foundation

/// Writes the audit records for what one daemon tick *observed*, before
/// anything is decided or done about it.
///
/// Extracted from `main.swift` for the same reason
/// ``DaemonEnforcementDecision`` and ``DaemonEnforcementRuntime`` were: it was
/// a private function in a top-level script, no test could reach it, and a
/// defect duly shipped in it — break-glass recorded its start and never its
/// end, so an auditor could see protection begin over a lockout window and
/// never see it lift.
///
/// The division of labour across the daemon's three pieces is: this type
/// records what was *read*, ``DaemonEnforcementDecision`` decides what it
/// means, and ``DaemonEnforcementRuntime`` records and performs what was
/// *done*. No layer writes a fact it had to guess.
///
/// Every record is deduplicated on its value, because the loop runs every
/// fifteen seconds and a quiet night must not produce five thousand identical
/// lines. Each tracked dimension writes on its first observation, so the log
/// states its starting value rather than leaving a reader to infer it.
public struct DaemonAuditObserver {
    private let auditLog: AuditLog

    /// Creates an observer writing to `auditLog`.
    public init(auditLog: AuditLog = .shared) {
        self.auditLog = auditLog
    }

    /// Everything one tick read off disk.
    public struct Observation {
        /// Current clock time.
        public var now: Date
        /// The lockout window being enforced, or `nil` when there is none.
        public var deadline: LockoutDeadlineRecord?
        /// Whether the user-writable deadline file answered. `false` means the
        /// root-owned shadow did, which is to say the user-side record was
        /// gone.
        public var deadlineCameFromUserFile: Bool
        /// Seconds since the app last touched its heartbeat. `.infinity` when
        /// the file is missing.
        public var heartbeatAge: TimeInterval
        /// How stale the heartbeat must be before a shutdown is due.
        public var heartbeatTimeout: TimeInterval
        /// Whether any unexpired ``ProtectedWorkClaim`` exists.
        public var hasActiveProtectedWork: Bool
        /// The verified release covering this window, or `nil`.
        public var breakGlass: BreakGlassRelease?

        public init(
            now: Date,
            deadline: LockoutDeadlineRecord?,
            deadlineCameFromUserFile: Bool,
            heartbeatAge: TimeInterval,
            heartbeatTimeout: TimeInterval,
            hasActiveProtectedWork: Bool,
            breakGlass: BreakGlassRelease?
        ) {
            self.now = now
            self.deadline = deadline
            self.deadlineCameFromUserFile = deadlineCameFromUserFile
            self.heartbeatAge = heartbeatAge
            self.heartbeatTimeout = heartbeatTimeout
            self.hasActiveProtectedWork = hasActiveProtectedWork
            self.breakGlass = breakGlass
        }
    }

    /// Records this tick's readings.
    public func record(_ observation: Observation) {
        recordDeadline(observation)
        recordHeartbeat(observation)
        recordProtectedWork(observation)
        recordBreakGlass(observation)
    }

    private func recordDeadline(_ observation: Observation) {
        guard let deadline = observation.deadline else { return }
        auditLog.emitIfChanged(
            key: "deadline",
            to: String(deadline.scheduledUnlockAt.timeIntervalSince1970),
            event: .daemonDeadlineObserved,
            actor: .daemon,
            detail: [
                "lockoutStartedAt": .string(AuditTimestamp.string(from: deadline.lockoutStartedAt)),
                "scheduledUnlockAt": .string(
                    AuditTimestamp.string(from: deadline.scheduledUnlockAt)
                ),
                "kind": .string(deadline.kind.rawValue),
                // `shadow` means the user-writable file was gone and the
                // root-owned copy carried the window — someone deleted the
                // record mid-lockout.
                "source": .string(observation.deadlineCameFromUserFile ? "user" : "shadow")
            ],
            at: observation.now
        )
        guard observation.now >= deadline.scheduledUnlockAt else { return }
        auditLog.emitIfChanged(
            key: "deadlineElapsed",
            to: String(deadline.scheduledUnlockAt.timeIntervalSince1970),
            event: .daemonDeadlineElapsed,
            actor: .daemon,
            detail: [
                "scheduledUnlockAt": .string(
                    AuditTimestamp.string(from: deadline.scheduledUnlockAt)
                )
            ],
            at: observation.now
        )
    }

    private func recordHeartbeat(_ observation: Observation) {
        let isStale = observation.heartbeatAge > observation.heartbeatTimeout
        auditLog.emitIfChanged(
            key: "heartbeat",
            to: isStale ? "stale" : "fresh",
            event: isStale ? .daemonHeartbeatStale : .daemonHeartbeatRecovered,
            actor: .daemon,
            detail: [
                // A missing heartbeat file reads as infinite age; -1 keeps the
                // field an integer instead of a JSON `null` a parser would
                // have to special-case.
                "ageSeconds": .int(
                    observation.heartbeatAge.isFinite ? Int(observation.heartbeatAge) : -1
                ),
                "thresholdSeconds": .int(Int(observation.heartbeatTimeout)),
                "heartbeatPresent": .bool(observation.heartbeatAge.isFinite)
            ],
            at: observation.now
        )
    }

    private func recordProtectedWork(_ observation: Observation) {
        auditLog.emitIfChanged(
            key: "protectedWork",
            to: observation.hasActiveProtectedWork ? "active" : "none",
            event: observation.hasActiveProtectedWork
                ? .protectedWorkActive
                : .protectedWorkCleared,
            actor: .daemon,
            at: observation.now
        )
    }

    /// Records a release arriving *and* lifting.
    ///
    /// Both directions, symmetric with heartbeat and protected work above. A
    /// release expiring or being revoked is the moment enforcement re-arms;
    /// recording only the start would leave an auditor able to see protection
    /// begin over a lockout window and unable to bound when it ended.
    private func recordBreakGlass(_ observation: Observation) {
        var detail: [String: AuditValue] = [:]
        if let release = observation.breakGlass {
            detail["releaseId"] = .string(release.id.uuidString)
            detail["issuedAt"] = .string(AuditTimestamp.string(from: release.issuedAt))
        }
        auditLog.emitIfChanged(
            key: "breakGlass",
            to: observation.breakGlass?.id.uuidString ?? "none",
            event: observation.breakGlass == nil ? .breakGlassCleared : .breakGlassObserved,
            actor: .daemon,
            detail: detail,
            at: observation.now
        )
    }
}
