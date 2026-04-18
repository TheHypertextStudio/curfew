import Foundation

/// The curfew rule for a single calendar day.
///
/// All time values are stored as **minutes from midnight** (0 = 00:00,
/// 1080 = 18:00, 480 = 08:00) rather than as `Date` or `DateComponents`
/// to keep `WeeklySchedule` timezone-independent. The absolute `Date`
/// values needed for enforcement are resolved by
/// ``WeeklySchedule/scheduleWindow(for:extensionMinutesGrantedToday:calendar:)``
/// at evaluation time using the device's current calendar.
///
/// Lives in its own file (split out of `ScheduleModels.swift` once mode
/// and exception support arrived) so the line-count stays inside the lint
/// budget and callers can grep for `DayRule` by filename.
public struct DayRule: Equatable, Codable {
    /// When `true` no enforcement window is active on this day. The user
    /// can still store `lockMinutes` / `unlockMinutes` so switching a day
    /// back on retains the previous times.
    public var isDayOff: Bool

    /// Minutes past midnight when the device locks. 1080 = 18:00 (6 pm).
    public var lockMinutes: Int

    /// Minutes past midnight when the device unlocks the following morning.
    /// Values ≤ `lockMinutes` are interpreted as next-day (e.g. 480 = 08:00
    /// the next calendar day).
    public var unlockMinutes: Int

    /// How the day's curfew triggers — by time, accumulated work hours, or
    /// both. Defaults to `.time` for back-compat with v0.1 schedules.
    public var mode: CurfewMode

    /// When `mode` is `.hours` or `.combined`, lock after this many minutes
    /// of active work. `nil` in `.time` mode; typical values are 480 (8 h)
    /// and 600 (10 h). Idle time (5-min threshold) is excluded by the
    /// aggregator before the engine sees this number.
    public var hoursLimitMinutes: Int?

    /// Reserved for future per-day overrides — holiday pickers, one-off
    /// "this Friday only" exceptions, calendar-driven day-off promotions.
    /// Currently always `nil`; exists as a Codable seam so adding the
    /// feature later does not require a CKRecord schema migration or a
    /// breaking change to any call site already branching on it.
    public var exception: DayRuleException?

    /// Standard workday defaults: Mon–Fri 18:00 lock / 08:00 unlock.
    public static let weekdayDefault = DayRule(
        isDayOff: false,
        lockMinutes: 18 * 60,
        unlockMinutes: 8 * 60
    )

    /// Default for Saturday and Sunday: day-off with the same times stored
    /// so the user gets sensible values if they re-enable a weekend day.
    public static let weekendDefault = DayRule(
        isDayOff: true,
        lockMinutes: 18 * 60,
        unlockMinutes: 8 * 60
    )

    /// Memberwise initialiser. Defaults keep `.time` mode, no hours
    /// limit, and no per-day exception so v0.1 call sites and legacy
    /// persisted payloads keep compiling without the new v0.2 fields.
    public init(
        isDayOff: Bool,
        lockMinutes: Int,
        unlockMinutes: Int,
        mode: CurfewMode = .time,
        hoursLimitMinutes: Int? = nil,
        exception: DayRuleException? = nil
    ) {
        self.isDayOff = isDayOff
        self.lockMinutes = lockMinutes
        self.unlockMinutes = unlockMinutes
        self.mode = mode
        self.hoursLimitMinutes = hoursLimitMinutes
        self.exception = exception
    }

    /// Custom decoder so pre-existing persisted rules (which never stored
    /// `exception`, `mode`, or `hoursLimitMinutes`) still load cleanly.
    /// Synthesized decode would throw `keyNotFound` on upgrade;
    /// `decodeIfPresent` keeps the upgrade path one-way-safe.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isDayOff = try container.decode(Bool.self, forKey: .isDayOff)
        self.lockMinutes = try container.decode(Int.self, forKey: .lockMinutes)
        self.unlockMinutes = try container.decode(Int.self, forKey: .unlockMinutes)
        self.mode = try container.decodeIfPresent(
            CurfewMode.self,
            forKey: .mode
        ) ?? .time
        self.hoursLimitMinutes = try container.decodeIfPresent(
            Int.self,
            forKey: .hoursLimitMinutes
        )
        self.exception = try container.decodeIfPresent(
            DayRuleException.self,
            forKey: .exception
        )
    }

    private enum CodingKeys: String, CodingKey {
        case isDayOff
        case lockMinutes
        case unlockMinutes
        case mode
        case hoursLimitMinutes
        case exception
    }
}

/// How a day's curfew is triggered.
///
/// `.time` — v0.1 behaviour; lock fires at `lockMinutes`.
/// `.hours` — lock fires once the user has accumulated `hoursLimitMinutes`
/// of active work today (across devices when sync is on).
/// `.combined` — locks at whichever comes first.
public enum CurfewMode: String, Codable, CaseIterable {
    case time
    case hours
    case combined

    /// Short label used in the schedule editor toggle.
    public var shortName: String {
        switch self {
        case .time: "Time"
        case .hours: "Hours"
        case .combined: "Both"
        }
    }
}

/// Placeholder for per-day schedule exceptions. The struct is empty
/// today — `rule.exception != nil` is always false — but the type
/// exists so the schedule editor and enforcement engine can start
/// referring to it before the v0.2 feature ships. When per-day
/// exceptions land they gain fields here (date range, one-off
/// `lockMinutes`/`unlockMinutes` override, "holiday" label) without
/// changing any of the enclosing APIs.
public struct DayRuleException: Equatable, Codable {
    /// Empty initialiser. The struct carries no fields today; kept
    /// explicit so adding them later is an additive change only.
    public init() {}
}
