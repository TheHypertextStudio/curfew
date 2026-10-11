import CurfewKit
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
    static let privilegedHeartbeatInterval: TimeInterval = 30

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

    /// Sends the active lockout identifier over the authenticated XPC channel.
    func touchAppHeartbeat() {
        guard featureFlags.privilegedHelperEnabled else {
            lastPrivilegedHeartbeatAt = nil
            return
        }
        guard let record = lockoutDeadlineStore.load(),
              currentTime < record.scheduledUnlockAt
        else {
            lastPrivilegedHeartbeatAt = nil
            return
        }
        if let lastPrivilegedHeartbeatAt,
           currentTime.timeIntervalSince(lastPrivilegedHeartbeatAt)
           < Self.privilegedHeartbeatInterval {
            return
        }
        lastPrivilegedHeartbeatAt = currentTime
        Task { await privilegedHelperManager.heartbeat(lockoutID: record.lockoutID) }
    }

    /// Stamps the durable deadline record at the moment lockout begins so
    /// a force-shutdown / crash mid-lockout still leaves the next launch
    /// enforced.
    func writeDurableDeadlineIfEnteringLockout(previousPhase: EnforcementPhase) {
        guard previousPhase != .locked,
              state.phase == .locked,
              let unlock = state.unlockDate
        else { return }
        if let existing = lockoutDeadlineStore.load(),
           currentTime < existing.scheduledUnlockAt {
            return
        }
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
        if featureFlags.privilegedHelperEnabled {
            lastPrivilegedHeartbeatAt = currentTime
            Task { await privilegedHelperManager.armLockout(record) }
        }
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

    /// Mirrors a proof-bound account release into a separately signed local
    /// record so the privileged daemon honors the same exact expiry if the app
    /// stops heartbeating. Revocation clears only this remote record and never
    /// the user's independent emergency break-glass release.
    func acceptAccountRemoteOverride(_ override: AccountRemoteOverride?) {
        accountRemoteOverride = override
        guard let override,
              let expiresAt = activeAccountRemoteOverrideUntil()
        else {
            remoteOverrideReleaseStore.clear()
            reconcileDurableLockoutDeadline()
            return
        }
        do {
            try remoteOverrideReleaseStore.issue(
                reason: "Remote MCP authorized a bounded direct unlock.",
                issuedBy: "remote-mcp@curfew",
                now: override.startsAt,
                expiresAt: expiresAt
            )
        } catch {
            accountRemoteOverride = nil
            remoteOverrideReleaseStore.clear()
            accountSyncEngine.reject("Could not authorize remote unlock on this Mac.")
        }
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
            lockoutID: existing.lockoutID,
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
        // A coordinator override suspends enforcement only for its bounded
        // lifetime. Keep the wake record so expiry or revocation restores the
        // same campaign instead of silently turning the grant permanent.
        if activeAccountRemoteOverrideUntil() != nil {
            enforceDurableDeadlineIfActive()
            return true
        }
        let decision = WakeReleaseEngine().decision(
            at: currentTime,
            deadline: record,
            wakeStatus: accountWakeLedger.current,
            remoteOverride: nil,
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

    /// Projects either a current account override or a terminal wake release
    /// into the enforcement engine. Remote overrides apply to every Curfew
    /// lock source; terminal wake state remains specific to wake campaigns.
    func accountReleaseOverrideUntil() -> Date? {
        if let remoteOverrideUntil = activeAccountRemoteOverrideUntil() {
            return remoteOverrideUntil
        }
        guard settings.accountSync.usesWakeCampaign else { return nil }
        let wake = accountWakeLedger.current
        let terminal = wake?.state.isTerminal == true
        guard terminal else { return nil }
        return currentTime
    }

    private func activeAccountRemoteOverrideUntil() -> Date? {
        guard let localDeviceID = settings.accountSync.enrollment?.deviceID,
              let override = accountRemoteOverride,
              override.authorizes(deviceID: localDeviceID, at: currentTime)
        else { return nil }
        return override.startsAt.addingTimeInterval(
            TimeInterval(override.durationMinutes * 60)
        )
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
        lastPrivilegedHeartbeatAt = nil
        if featureFlags.privilegedHelperEnabled {
            Task {
                await privilegedHelperManager.completeLockout(
                    lockoutID: record.lockoutID,
                    reason: .naturalExpiry
                )
            }
        }
    }

    /// Reconciles app-owned presentation state from the daemon's authoritative record.
    func reconcilePrivilegedDaemonState() async {
        guard featureFlags.privilegedHelperEnabled else { return }
        guard let daemonStatus = await privilegedHelperManager.reconcileDaemonStatus() else {
            return
        }
        if let authoritative = daemonStatus.activeRecord,
           currentTime < authoritative.scheduledUnlockAt {
            let local = lockoutDeadlineStore.load()
            if local == nil || local!.scheduledUnlockAt < authoritative.scheduledUnlockAt {
                lockoutDeadlineStore.save(authoritative)
            }
            enforceDurableDeadlineIfActive()
            await privilegedHelperManager.heartbeat(lockoutID: authoritative.lockoutID)
            lastPrivilegedHeartbeatAt = currentTime
        } else if let local = lockoutDeadlineStore.load(),
                  currentTime < local.scheduledUnlockAt {
            await privilegedHelperManager.armLockout(local)
            lastPrivilegedHeartbeatAt = currentTime
        }
    }

    /// Overrides the engine's evaluation back to `.locked` when the
    /// durable record's deadline hasn't passed. Honors an active
    /// override (`overrideUntil`) so the user's "Convince Me" grant still
    /// suspends enforcement until it expires; once the override ends and
    /// the deadline hasn't passed, lockout resumes.
    func enforceDurableDeadlineIfActive() {
        guard let record = lockoutDeadlineStore.load() else { return }
        guard currentTime < record.scheduledUnlockAt else { return }
        if activeAccountRemoteOverrideUntil() != nil {
            return
        }
        if record.kind != .remoteCommand,
           let overrideUntil,
           currentTime < overrideUntil {
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
