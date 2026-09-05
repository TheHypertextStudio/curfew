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
        if reconcileAccountWakeDeadline() {
            return
        }
        enforceDurableDeadlineIfActive()
        clearDurableDeadlineIfNaturalUnlock()
    }

    /// Touches the app-heartbeat file with the current timestamp. The
    /// daemon reads this file's mtime to decide whether the app is still
    /// running; a stale heartbeat plus an active lockout deadline is the
    /// signal the daemon uses to force a shutdown.
    func touchAppHeartbeat() {
        // Skip when running as a unit-test host: the heartbeat lives in the App
        // Group container, so writing it from the (re-signed each build) test
        // host raises the macOS "access data from other apps" prompt on every
        // run. No test asserts the heartbeat; production launches are unaffected.
        // Also skip in Debug builds where the daemon is not active: the
        // heartbeat is meaningless without the privileged helper reading it.
        guard !RuntimeEnvironment.isUnitTestHost,
              featureFlags.privilegedHelperEnabled else { return }
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
        let currentWakeStatus = accountWakeLedger.current
        let record: LockoutDeadlineRecord = if settings.accountSync.usesWakeCampaign {
            WakeLockoutDeadlineResolver.record(
                lockoutStartedAt: currentTime,
                scheduleUnlockAt: unlock,
                account: settings.accountSync,
                wakeStatus: currentWakeStatus
            )
        } else {
            LockoutDeadlineRecord(
                lockoutStartedAt: currentTime,
                scheduledUnlockAt: unlock,
                kind: state.trigger == .hours ? .scheduledHours : .scheduledTime
            )
        }
        lockoutDeadlineStore.save(record)
    }

    /// Accepts only monotonic, authenticated wake projections, then persists
    /// the new rollback gate before it may influence enforcement.
    func acceptAccountWakeStatus(_ update: AccountWakeStatusUpdate) {
        guard settings.accountSync.isEnrolled else { return }
        var candidate = accountWakeLedger
        do {
            try candidate.accept(update, now: currentTime)
            try accountWakeLedgerStore.save(candidate)
            accountWakeLedger = candidate
            alignActiveWakeDeadline(to: update)
            reconcileDurableLockoutDeadline()
            accountSyncEngine.markSynchronized(at: update.updatedAt)
        } catch {
            accountSyncEngine.reject("Rejected stale or invalid wake state.")
        }
    }

    /// Projects a command already authenticated and applied by the privileged
    /// daemon into the running app. The projection is device-bound and may
    /// only preserve or strengthen an active deadline, never shorten it.
    func acceptRemoteCommandResult(_ result: RemoteCommandResult) {
        guard let deviceID = settings.accountSync.enrollment?.deviceID else { return }
        let current = lockoutDeadlineStore.load()
        guard let projected = RemoteCommandLockoutProjection.resolve(
            result: result,
            enrolledDeviceID: deviceID,
            now: currentTime,
            current: current
        ), projected != current else { return }
        lockoutDeadlineStore.save(projected)
        reconcileDurableLockoutDeadline()
    }

    /// An early campaign can arrive before or after the evening boundary. The
    /// account record stores its campaign identifier but never a release clock.
    private func alignActiveWakeDeadline(to update: AccountWakeStatusUpdate) {
        guard let existing = lockoutDeadlineStore.load(),
              existing.kind == .accountWakeCampaign,
              existing.campaignID == nil || existing.campaignID == update.campaignID
        else { return }
        lockoutDeadlineStore.save(LockoutDeadlineRecord(
            lockoutStartedAt: existing.lockoutStartedAt,
            scheduledUnlockAt: .distantFuture,
            kind: .accountWakeCampaign,
            campaignID: update.campaignID
        ))
    }

    /// Returns true when an account-wake record owned reconciliation.
    private func reconcileAccountWakeDeadline() -> Bool {
        guard let record = lockoutDeadlineStore.load(),
              record.kind == .accountWakeCampaign,
              let localDeviceID = settings.accountSync.enrollment?.deviceID
        else { return false }
        let decision = WakeReleaseEngine().decision(
            at: currentTime,
            deadline: record,
            wakeStatus: accountWakeLedger.current,
            remoteOverride: accountRemoteOverride,
            localDeviceID: localDeviceID
        )
        switch decision {
        case .hold:
            enforceDurableDeadlineIfActive()
        case .release:
            releaseAccountWakeDeadline(record)
        case .legacyFixedUnlock:
            return false
        }
        return true
    }

    private func releaseAccountWakeDeadline(_ record: LockoutDeadlineRecord) {
        state = enforcementEngine.evaluate(
            at: currentTime,
            schedule: settings.schedule,
            extensionMinutesGrantedToday:
            extensionMinutesGrantedToday + snoozeMinutesGrantedToday,
            overrideUntil: currentTime,
            warningIntervals: settings.warningIntervals,
            workedMinutesToday: workedMinutesToday(at: currentTime)
        )
        lockoutDeadlineStore.clear()
        protectedWork.breakGlass.clear()
        try? protectedWork.claims.clear()
    }

    /// Re-derives terminal release after process death even when the durable
    /// record was already cleared. This prevents a satisfied campaign from
    /// being re-locked by a legacy schedule clock on relaunch.
    func accountWakeReleaseOverrideUntil(for baseline: CurfewEvaluation) -> Date? {
        guard settings.accountSync.usesWakeCampaign,
              let localDeviceID = settings.accountSync.enrollment?.deviceID
        else { return nil }
        let wake = accountWakeLedger.current
        let terminal = wake?.state.isTerminal == true
        let activeOverride = accountRemoteOverride?.authorizes(
            deviceID: localDeviceID,
            at: currentTime
        ) == true
        guard terminal || activeOverride else { return nil }
        if activeOverride, let override = accountRemoteOverride, !terminal {
            return override.startsAt.addingTimeInterval(
                TimeInterval(override.durationMinutes * 60)
            )
        }
        return currentTime
    }

    /// Clears the record once the natural unlock time has arrived. Called
    /// from the tick loop so the schedule resumes driving phase the
    /// moment `Date() >= scheduledUnlockAt`.
    func clearDurableDeadlineIfNaturalUnlock() {
        guard let record = lockoutDeadlineStore.load(),
              record.kind != .accountWakeCampaign
        else { return }
        guard currentTime >= record.scheduledUnlockAt else { return }
        lockoutDeadlineStore.clear()
        // A break-glass release covers one window only. Clearing it here — at
        // the same moment the deadline goes away — is what stops tonight's
        // emergency from silently disarming tomorrow's curfew.
        protectedWork.breakGlass.clear()
        try? protectedWork.claims.clear()
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
