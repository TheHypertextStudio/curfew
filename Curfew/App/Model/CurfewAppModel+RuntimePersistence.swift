import CurfewKit
import Foundation

@MainActor
extension CurfewAppModel {
    static func restoreRuntimeState(
        settings: CurfewSettings,
        store: EnforcementRuntimeStateStore,
        overrides: [OverrideEvent],
        recorder: any ActivityRecording,
        now: Date
    ) -> (state: EnforcementRuntimeState, error: String?) {
        do {
            if let stored = try store.load() {
                return (stored, nil)
            }
            let migrated = migrateRuntimeState(
                settings: settings, overrides: overrides, recorder: recorder, now: now
            )
            try store.save(migrated)
            return (migrated, nil)
        } catch {
            return (
                EnforcementRuntimeState(
                    dayToken: dayToken(for: now),
                    extensionUses: settings.extensionWeeklyLimit,
                    overrideUses: settings.overrideWeeklyLimit,
                    extensionResetBoundary: now,
                    overrideResetBoundary: now
                ),
                runtimeStorageFailure(error)
            )
        }
    }

    static func runtimeBudgetTrackers(
        settings: CurfewSettings, state: EnforcementRuntimeState, now: Date
    ) -> (extension: ExtensionBudgetTracker, override: ExtensionBudgetTracker) {
        let extensions = ExtensionBudgetTracker(
            weeklyLimit: settings.extensionWeeklyLimit,
            extensionMinutes: settings.extensionDurationMinutes,
            resetWeekday: settings.resetWeekday,
            seedLastResetBoundary: state.extensionResetBoundary,
            seedUsedCount: state.extensionUses
        )
        let overrides = ExtensionBudgetTracker(
            weeklyLimit: settings.overrideWeeklyLimit,
            extensionMinutes: settings.overrideDurationMinutes,
            resetWeekday: settings.resetWeekday,
            seedLastResetBoundary: state.overrideResetBoundary,
            seedUsedCount: state.overrideUses
        )
        extensions.resetIfNeeded(at: now)
        overrides.resetIfNeeded(at: now)
        return (extensions, overrides)
    }

    func runtimeStateSnapshot() -> EnforcementRuntimeState {
        EnforcementRuntimeState(
            dayToken: currentDayToken,
            extensionMinutes: extensionMinutesGrantedToday,
            snoozeMinutes: snoozeMinutesGrantedToday,
            extensionUses: extensionTracker.usedCount,
            overrideUses: overrideTracker.usedCount,
            extensionResetBoundary: extensionTracker.lastResetBoundary,
            overrideResetBoundary: overrideTracker.lastResetBoundary,
            overrideUntil: overrideUntil
        )
    }

    @discardableResult
    func persistRuntimeState(_ snapshot: EnforcementRuntimeState? = nil) -> Bool {
        guard runtimePersistenceError == nil else { return false }
        do {
            try runtimeStateStore.save(snapshot ?? runtimeStateSnapshot())
            return true
        } catch {
            runtimePersistenceError = Self.runtimeStorageFailure(error)
            return false
        }
    }

    func grantPersistentExtension() -> Bool {
        guard runtimePersistenceError == nil else { return false }
        let tracker = copiedTracker(extensionTracker)
        guard tracker.requestExtension(at: currentTime) else { return false }
        var snapshot = runtimeStateSnapshot()
        snapshot.extensionUses = tracker.usedCount
        snapshot.extensionResetBoundary = tracker.lastResetBoundary
        snapshot.extensionMinutes += settings.extensionDurationMinutes
        guard persistRuntimeState(snapshot) else { return false }
        extensionTracker = tracker
        extensionMinutesGrantedToday = snapshot.extensionMinutes
        extensionsRemaining = tracker.remaining
        return true
    }

    func grantPersistentSnooze() -> Bool {
        var snapshot = runtimeStateSnapshot()
        snapshot.snoozeMinutes += 1
        guard persistRuntimeState(snapshot) else { return false }
        snoozeMinutesGrantedToday = snapshot.snoozeMinutes
        return true
    }

    func grantPersistentOverride() -> Bool {
        guard runtimePersistenceError == nil else { return false }
        let tracker = copiedTracker(overrideTracker)
        guard tracker.requestExtension(at: currentTime) else { return false }
        var snapshot = runtimeStateSnapshot()
        snapshot.overrideUses = tracker.usedCount
        snapshot.overrideResetBoundary = tracker.lastResetBoundary
        snapshot.overrideUntil = currentTime.addingTimeInterval(
            TimeInterval(settings.overrideDurationMinutes * 60)
        )
        guard persistRuntimeState(snapshot) else { return false }
        overrideTracker = tracker
        overridesRemaining = tracker.remaining
        overrideUntil = snapshot.overrideUntil
        return true
    }

    func resetPersistentWeeklyBudgetsIfNeeded() {
        guard runtimePersistenceError == nil else { return }
        let priorExtensionBoundary = extensionTracker.lastResetBoundary
        let priorOverrideBoundary = overrideTracker.lastResetBoundary
        extensionTracker.resetIfNeeded(at: currentTime)
        overrideTracker.resetIfNeeded(at: currentTime)
        if extensionTracker.lastResetBoundary != priorExtensionBoundary
            || overrideTracker.lastResetBoundary != priorOverrideBoundary {
            persistRuntimeState()
        }
    }

    func rebasedRuntimeTracker(
        _ prior: ExtensionBudgetTracker, weeklyLimit: Int, minutes: Int
    ) -> ExtensionBudgetTracker {
        let tracker = ExtensionBudgetTracker(
            weeklyLimit: weeklyLimit,
            extensionMinutes: minutes,
            resetWeekday: settings.resetWeekday,
            seedUsedCount: prior.usedCount
        )
        // A reset-weekday edit must keep consumed uses until the next new boundary.
        tracker.resetIfNeeded(at: currentTime)
        let boundaries = [prior.lastResetBoundary, tracker.lastResetBoundary].compactMap(\.self)
        return ExtensionBudgetTracker(
            weeklyLimit: weeklyLimit,
            extensionMinutes: minutes,
            resetWeekday: settings.resetWeekday,
            seedLastResetBoundary: boundaries.max(),
            seedUsedCount: prior.usedCount
        )
    }

    private func copiedTracker(_ prior: ExtensionBudgetTracker) -> ExtensionBudgetTracker {
        ExtensionBudgetTracker(
            weeklyLimit: prior.weeklyLimit,
            extensionMinutes: prior.extensionMinutes,
            resetWeekday: prior.resetWeekday,
            seedLastResetBoundary: prior.lastResetBoundary,
            seedUsedCount: prior.usedCount
        )
    }

    private static func runtimeStorageFailure(_ error: any Error) -> String {
        "Curfew could not read or save grant history. Local grants are unavailable. "
            + error.localizedDescription
    }

    private static func migrateRuntimeState(
        settings: CurfewSettings,
        overrides: [OverrideEvent],
        recorder: any ActivityRecording,
        now: Date
    ) -> EnforcementRuntimeState {
        let trackers = makeBudgetTrackers(for: settings)
        trackers.extension.resetIfNeeded(at: now)
        trackers.override.resetIfNeeded(at: now)
        let boundary = trackers.extension.lastResetBoundary ?? now
        let events = recorder.events(in: boundary ... now).filter { $0.gateKind == GateKind.curfew }
        let extensions = events.filter { $0.kind == .extensionGranted }
        let localOverrides = overrides.filter { $0.timestamp >= boundary && $0.timestamp <= now }
        let today = Calendar.current.startOfDay(for: now)
        // Override activity duplicates the settings log; use one source for its weekly count.
        let overrideUses = localOverrides.isEmpty
            ? events.filter { $0.kind == .overrideGranted }.count : localOverrides.count
        let latestOverride = overrides.filter { $0.timestamp <= now }
            .max { $0.timestamp < $1.timestamp }
        let overrideUntil = latestOverride.map {
            $0.timestamp.addingTimeInterval(TimeInterval($0.grantedDurationMinutes * 60))
        }
        return EnforcementRuntimeState(
            dayToken: dayToken(for: now),
            extensionMinutes: extensions.filter { $0.timestamp >= today }
                .reduce(0) { $0 + max(0, $1.minutesValue ?? 0) },
            extensionUses: extensions.count,
            overrideUses: overrideUses,
            extensionResetBoundary: trackers.extension.lastResetBoundary,
            overrideResetBoundary: trackers.override.lastResetBoundary,
            overrideUntil: overrideUntil
        )
    }
}
