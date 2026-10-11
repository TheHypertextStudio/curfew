import Foundation

/// Whether a proposed ``WeeklySchedule`` change is more permissive, more
/// restrictive, or identical to the current schedule.
///
/// The classification drives both the cooldown duration and the copy shown in
/// the pending-change banner: weaker changes require a 24-hour wall-clock
/// cooldown; stricter changes take effect at the next calendar midnight.
public enum ScheduleChangeClassification: String, Equatable, Codable {
    /// The proposed schedule allows more screen time on at least one day
    /// (later lock, earlier unlock, or a day turned off). Requires a 24-hour
    /// cooldown from the moment of the request.
    case weaker

    /// The proposed schedule restricts screen time on at least one day and
    /// does not loosen any other day. Effective at the next calendar midnight
    /// so the user cannot immediately escape a session by tightening rules.
    case stricter

    /// Schedules are identical — no cooldown, change applied immediately.
    case noChange = "no_change"
}

/// Pure-function engine that classifies proposed schedule mutations and
/// computes their effective dates.
///
/// The anti-bypass policy this engine implements is the primary structural
/// defence against "just loosen the schedule before curfew fires". By
/// delaying weaker changes 24 hours and stricter changes until midnight, the
/// engine ensures the user cannot trivially escape a session through Settings.
///
/// `CurfewAppModel` holds one instance and calls
/// ``classifyChange(from:to:)`` before persisting a ``PendingScheduleChange``.
public struct SchedulePolicyEngine {
    private let calendar: Calendar

    /// Creates a policy engine. `calendar` pins the reference clock for
    /// "next-day boundary" arithmetic; tests swap in a UTC calendar to
    /// keep DST and timezone drift out of the classification logic.
    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    /// Compares `current` and `proposed` day-by-day and returns the
    /// strictest applicable classification. Any single day that loosens the
    /// schedule (later lock, earlier unlock, enforcement turned off, mode
    /// change, or higher hours budget) immediately returns
    /// ``ScheduleChangeClassification/weaker``; otherwise a day that
    /// tightens the schedule sets a `.stricter` flag. Returns
    /// ``ScheduleChangeClassification/noChange`` when every day is unchanged.
    ///
    /// Mode and `hoursLimitMinutes` comparisons are intentionally
    /// conservative: any mode transition (`.time` ↔ `.hours`, either to or
    /// from `.combined`) defaults to `.weaker` even when the new mode is
    /// objectively stricter, because effective strictness depends on the
    /// runtime `worked` count which cannot be evaluated at classification
    /// time. The user can wait out the 24-hour cooldown for genuine
    /// strictness upgrades; the price of conservatism is preferable to a
    /// classifier that lets a mode-flip slip past the anti-bypass gate.
    public func classifyChange(
        from current: WeeklySchedule,
        to proposed: WeeklySchedule
    ) -> ScheduleChangeClassification {
        var hasStricterSignal = false

        for weekday in Weekday.allCases {
            switch classifyDay(
                current: current.rule(for: weekday),
                proposed: proposed.rule(for: weekday)
            ) {
            case .weaker:
                return .weaker
            case .stricter:
                hasStricterSignal = true
            case .noChange:
                continue
            }
        }

        return hasStricterSignal ? .stricter : .noChange
    }

    /// Returns the classification for a single day's rule pair. Folds the
    /// per-day comparisons (day-off toggle, lock/unlock minutes, mode,
    /// hours limit) into one function so the outer loop stays linear and
    /// the cyclomatic complexity per function stays within budget.
    private func classifyDay(
        current: DayRule,
        proposed: DayRule
    ) -> ScheduleChangeClassification {
        // Day-off toggling short-circuits the rest of the rule comparison.
        if !current.isDayOff, proposed.isDayOff {
            return .weaker
        }
        if current.isDayOff, !proposed.isDayOff {
            return .stricter
        }
        if current.isDayOff, proposed.isDayOff {
            return .noChange
        }

        if let clockSignal = classifyClockTimes(current: current, proposed: proposed) {
            return clockSignal
        }
        return classifyModeAndHours(current: current, proposed: proposed)
    }

    /// Per-day comparison of `lockMinutes` and `unlockMinutes`. Returns
    /// `.weaker` on any loosening, `.stricter` on any tightening (when no
    /// loosening also present), and `nil` when neither field changed so
    /// the caller can continue with mode/hours checks.
    private func classifyClockTimes(
        current: DayRule,
        proposed: DayRule
    ) -> ScheduleChangeClassification? {
        var stricter = false
        if proposed.lockMinutes > current.lockMinutes {
            return .weaker
        }
        if proposed.lockMinutes < current.lockMinutes {
            stricter = true
        }
        if proposed.unlockMinutes < current.unlockMinutes {
            return .weaker
        }
        if proposed.unlockMinutes > current.unlockMinutes {
            stricter = true
        }
        return stricter ? .stricter : nil
    }

    /// Per-day comparison of `mode` and `hoursLimitMinutes`. Any mode
    /// change is `.weaker` by default — see `classifyChange` docstring
    /// for the conservatism rationale. When mode is unchanged and uses
    /// the hours budget, the limit comparison decides.
    private func classifyModeAndHours(
        current: DayRule,
        proposed: DayRule
    ) -> ScheduleChangeClassification {
        if proposed.mode != current.mode {
            return .weaker
        }
        if proposed.mode == .time {
            return .noChange
        }
        let currentLimit = current.hoursLimitMinutes ?? 0
        let proposedLimit = proposed.hoursLimitMinutes ?? 0
        if proposedLimit > currentLimit {
            return .weaker
        }
        if proposedLimit < currentLimit {
            return .stricter
        }
        return .noChange
    }

    /// Returns the earliest `Date` at which `change` may be applied.
    ///
    /// - `.weaker`: 24 hours from `requestedAt` (wall-clock delay).
    /// - `.stricter`: start of the next calendar day in the device timezone.
    /// - `.noChange`: `requestedAt` (immediate; caller should skip queuing).
    public func earliestEffectiveDate(
        for change: ScheduleChangeClassification,
        requestedAt: Date
    ) -> Date {
        switch change {
        case .weaker:
            return requestedAt.addingTimeInterval(24 * 60 * 60)
        case .stricter:
            let todayStart = calendar.startOfDay(for: requestedAt)
            return calendar.date(byAdding: .day, value: 1, to: todayStart) ?? requestedAt
        case .noChange:
            return requestedAt
        }
    }
}
