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
    /// schedule (later lock, earlier unlock, enforcement turned off)
    /// immediately returns ``ScheduleChangeClassification/weaker``; otherwise
    /// a day that tightens the schedule sets a `.stricter` flag. Returns
    /// ``ScheduleChangeClassification/noChange`` when every day is unchanged.
    public func classifyChange(
        from current: WeeklySchedule,
        to proposed: WeeklySchedule
    ) -> ScheduleChangeClassification {
        var hasStricterSignal = false

        for weekday in Weekday.allCases {
            let currentRule = current.rule(for: weekday)
            let proposedRule = proposed.rule(for: weekday)

            if !currentRule.isDayOff, proposedRule.isDayOff {
                return .weaker
            }
            if currentRule.isDayOff, !proposedRule.isDayOff {
                hasStricterSignal = true
                continue
            }
            if currentRule.isDayOff, proposedRule.isDayOff {
                continue
            }

            if proposedRule.lockMinutes > currentRule.lockMinutes {
                return .weaker
            }
            if proposedRule.lockMinutes < currentRule.lockMinutes {
                hasStricterSignal = true
            }

            if proposedRule.unlockMinutes < currentRule.unlockMinutes {
                return .weaker
            }
            if proposedRule.unlockMinutes > currentRule.unlockMinutes {
                hasStricterSignal = true
            }
        }

        return hasStricterSignal ? .stricter : .noChange
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
