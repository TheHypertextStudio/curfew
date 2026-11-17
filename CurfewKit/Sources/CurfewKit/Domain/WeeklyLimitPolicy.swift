import Foundation

/// Pure rules for changing the weekly extension and override limits.
///
/// Mirrors the schedule's anti-bypass policy and reuses its engine: raising a
/// limit is a ``ScheduleChangeClassification/weaker`` change and waits until
/// ``SchedulePolicyEngine/earliestEffectiveDate(for:requestedAt:)`` says a
/// weaker schedule change could apply; a due raise is held while this Mac is
/// locked, exactly as `applyPendingScheduleIfNeeded` holds a looser schedule.
/// Lowering a limit applies at once, because asking for less can never help
/// anyone get past curfew.
///
/// Two places are deliberately stricter than the schedule. A raise waits even
/// while the weekly schedule is off once setup is done, because extensions and
/// overrides still matter for locks that come from elsewhere; and a raise that
/// arrives through sync is stamped with this Mac's own clock rather than the
/// sender's, so another device cannot hand over an already-due raise.
public struct WeeklyLimitPolicy {
    private let engine: SchedulePolicyEngine

    public init(engine: SchedulePolicyEngine = SchedulePolicyEngine()) {
        self.engine = engine
    }

    /// Classifies a limit edit with the schedule's vocabulary.
    public func classify(from current: Int, to proposed: Int) -> ScheduleChangeClassification {
        if proposed > current {
            return .weaker
        }
        if proposed < current {
            return .stricter
        }
        return .noChange
    }

    /// Returns `settings` after the person asks for `value` on `limit` at `now`.
    ///
    /// - At or below the value in force: applies at once and clears any
    ///   waiting raise for that limit (setting it back cancels).
    /// - Above it: becomes the waiting raise. A larger raise than the one
    ///   waiting starts the wait again; a smaller one keeps the original time,
    ///   since it asks for less than was already on the way.
    /// - Before setup is finished nothing is enforced yet, so the value
    ///   applies at once, as a schedule edit does.
    public func request(
        _ limit: WeeklyLimit,
        value requested: Int,
        in settings: CurfewSettings,
        at now: Date
    ) -> CurfewSettings {
        var next = settings
        let value = max(0, requested)
        let existing = settings.pendingLimitChange(for: limit)
        next.pendingLimitChanges.removeAll { $0.limit == limit }

        guard settings.hasCompletedInitialSetup,
              classify(from: settings[limit], to: value) == .weaker else {
            next[limit] = value
            return next
        }

        let change = if let existing, value <= existing.value {
            PendingLimitChange(
                limit: limit, value: value,
                requestedAt: existing.requestedAt, effectiveAt: existing.effectiveAt
            )
        } else {
            PendingLimitChange(
                limit: limit, value: value, requestedAt: now,
                effectiveAt: engine.earliestEffectiveDate(for: .weaker, requestedAt: now)
            )
        }
        let others = next
        next.pendingLimitChanges = WeeklyLimit.allCases.compactMap { kind in
            kind == limit ? change : others.pendingLimitChange(for: kind)
        }
        return next
    }

    /// Applies every waiting raise whose time has arrived. Called once per
    /// tick, right after the schedule's own pending swap.
    ///
    /// While `isLocked` nothing applies: the cooldown alone would let a raise
    /// requested the evening before land in the middle of tonight's lock.
    /// Entries that are no longer raises (the value in force caught up, or a
    /// stored payload was edited by hand) are dropped, never applied.
    public func applyDue(
        in settings: CurfewSettings,
        at now: Date,
        isLocked: Bool
    ) -> (settings: CurfewSettings, applied: [PendingLimitChange]) {
        var next = settings
        var applied: [PendingLimitChange] = []
        var waiting: [PendingLimitChange] = []
        var seen = Set<WeeklyLimit>()
        for change in settings.pendingLimitChanges where seen.insert(change.limit).inserted {
            guard change.value > settings[change.limit] else { continue }
            if now >= change.effectiveAt, !isLocked {
                next[change.limit] = change.value
                applied.append(change)
            } else {
                waiting.append(change)
            }
        }
        next.pendingLimitChanges = waiting
        return (next, applied)
    }

    /// Takes a settings payload received from another Mac and replaces its
    /// limits with what this Mac allows: the local values in force, lowered at
    /// once where the remote asks for less, and raised only through a waiting
    /// change timed by this Mac's clock. A raise identical to one already
    /// waiting here keeps the local time, so a sync echo never restarts it.
    public func gateRemote(
        _ remote: CurfewSettings,
        local: CurfewSettings,
        at now: Date
    ) -> CurfewSettings {
        var gated = local
        for limit in WeeklyLimit.allCases {
            if remote[limit] < gated[limit] {
                gated = request(limit, value: remote[limit], in: gated, at: now)
            }
            let target = remote.requestedLimit(limit)
            if target == gated.requestedLimit(limit) {
                continue
            }
            gated = request(limit, value: target, in: gated, at: now)
        }
        var merged = remote
        for limit in WeeklyLimit.allCases {
            merged[limit] = gated[limit]
        }
        merged.pendingLimitChanges = gated.pendingLimitChanges
        return merged
    }
}
