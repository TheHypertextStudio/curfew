import Foundation
import OSLog

private let durableLockoutLogger = Logger(
    subsystem: "studio.hypertext.curfew",
    category: "durable-lockout"
)

/// Hooks that keep the on-disk ``LockoutDeadlineRecord`` aligned with the
/// model's live phase and that enforce the durable deadline during
/// schedule re-evaluation. Closes M5 ("reboot-to-bypass") and A1 ("four
/// sources of truth for am-I-locked") in the v0.1 enforcement audit.
///
/// Three responsibilities, all called from the tick loop:
///
/// - ``writeDurableDeadlineIfEnteringLockout`` — on `.locked` entry, stamp
///   the durable record with the engine's `unlockDate`.
/// - ``enforceDurableDeadline`` — if the engine drops `.locked` early
///   (schedule changed, clock skew, time-zone surprise) and the durable
///   record's deadline hasn't passed, swap the evaluation back to
///   `.locked` using the record's dates.
/// - ``clearDurableDeadlineIfNaturalUnlock`` — once `Date() >=
///   scheduledUnlockAt`, delete the record so the schedule resumes
///   driving phase normally.
@MainActor
extension CurfewAppModel {
    /// Single entry point the tick loop calls to keep the durable record
    /// aligned. Combines the two checks (enforce / clear-on-natural-unlock)
    /// so the tick body stays inside its lint-enforced length budget.
    func reconcileDurableLockoutDeadline() {
        enforceDurableDeadlineIfActive()
        clearDurableDeadlineIfNaturalUnlock()
    }

    /// Touches the app-heartbeat file with the current timestamp. The
    /// daemon reads this file's mtime to decide whether the app is still
    /// running; a stale heartbeat plus an active lockout deadline is the
    /// signal the daemon uses to force a shutdown.
    func touchAppHeartbeat() {
        let url = SharedPaths.appHeartbeat
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data().write(to: url, options: .atomic)
            try FileManager.default.setAttributes(
                [.modificationDate: currentTime],
                ofItemAtPath: url.path
            )
        } catch {
            durableLockoutLogger.error(
                "failed to touch app heartbeat: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    /// Stamps the durable deadline record at the moment lockout begins so
    /// a force-shutdown / crash mid-lockout still leaves the next launch
    /// enforced.
    func writeDurableDeadlineIfEnteringLockout(previousPhase: EnforcementPhase) {
        guard previousPhase != .locked,
              state.phase == .locked,
              let unlock = state.unlockDate
        else { return }
        let record = LockoutDeadlineRecord(
            lockoutStartedAt: currentTime,
            scheduledUnlockAt: unlock,
            kind: state.trigger == .hours ? .scheduledHours : .scheduledTime
        )
        lockoutDeadlineStore.save(record)
    }

    /// Clears the record once the natural unlock time has arrived. Called
    /// from the tick loop so the schedule resumes driving phase the
    /// moment `Date() >= scheduledUnlockAt`.
    func clearDurableDeadlineIfNaturalUnlock() {
        guard let record = lockoutDeadlineStore.load() else { return }
        guard currentTime >= record.scheduledUnlockAt else { return }
        lockoutDeadlineStore.clear()
    }

    /// Overrides the engine's evaluation back to `.locked` when the
    /// durable record's deadline hasn't passed. Honors an active
    /// override (`overrideUntil`) so the user's "Convince Me" grant still
    /// suspends enforcement until it expires; once the override ends and
    /// the deadline hasn't passed, lockout resumes.
    func enforceDurableDeadlineIfActive() {
        guard let record = lockoutDeadlineStore.load() else { return }
        guard currentTime < record.scheduledUnlockAt else { return }
        if let overrideUntil, currentTime < overrideUntil {
            return
        }
        guard state.phase != .locked else { return }
        let deadline = record.scheduledUnlockAt
        durableLockoutLogger.info(
            "engine dropped lockout early; durable record holds until \(deadline, privacy: .public)"
        )
        state = .locked(
            lockDate: record.lockoutStartedAt,
            unlockDate: record.scheduledUnlockAt,
            trigger: record.kind == .scheduledHours ? .hours : .time
        )
    }
}
