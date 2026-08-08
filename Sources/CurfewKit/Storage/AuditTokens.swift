import CryptoKit
import Foundation

/// Stable wire tokens for the domain enums that appear in `from` / `to`.
///
/// These are the *stable* names. `EnforcementPhase` and `WarningStage` are
/// plain Swift enums with no raw values, so `String(describing:)` would tie
/// the on-disk format to Swift's case names and rename them silently on the
/// next refactor. The tokens below match the ones `CurfewAppModel` already
/// pushes to CloudKit (`working`, `day_off`, `T-30`), so a reader correlating
/// an audit line with a `LockoutState` record does not have to translate.
public enum AuditTokens {
    /// `working` | `warning` | `locked` | `day_off`.
    public static func phase(_ phase: EnforcementPhase) -> String {
        switch phase {
        case .working: "working"
        case .warning: "warning"
        case .locked: "locked"
        case .dayOff: "day_off"
        }
    }

    /// `none` | `T-30` | `T-15` | `T-5` | `T-2` | `T-1` | `lockout`.
    public static func warningStage(_ stage: WarningStage) -> String {
        switch stage {
        case .none: "none"
        case .thirtyMinutes: "T-30"
        case .fifteenMinutes: "T-15"
        case .fiveMinutes: "T-5"
        case .twoMinutes: "T-2"
        case .oneMinute: "T-1"
        case .lockout: "lockout"
        }
    }

    /// `granted` | `denied`, for permission states.
    public static func permission(_ granted: Bool) -> String {
        granted ? "granted" : "denied"
    }

    /// `idle` | `active`, for presence.
    public static func presence(isIdle: Bool) -> String {
        isIdle ? "idle" : "active"
    }

    /// `HH:MM` from minutes past midnight, for schedule rendering.
    public static func clock(minutes: Int) -> String {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }
}

/// Compact, stable renderings of a ``WeeklySchedule`` for the audit log.
///
/// A schedule change is the single most audit-relevant mutation in Curfew —
/// it is the thing the anti-bypass policy exists to slow down — so the log has
/// to say what actually moved. Writing the whole schedule as JSON on every
/// change would bloat the line and still leave the reader diffing by eye, so
/// each record carries three things instead: a digest that identifies the
/// schedule exactly, a one-line human rendering, and the list of weekdays
/// whose rule differs.
public enum AuditScheduleSummary {
    /// Canonical text for `schedule`, one segment per weekday in fixed
    /// Monday-first order. This is the string the digest is taken over, so
    /// its format is part of the on-disk contract.
    ///
    /// Example: `mon=09:00-17:00/time;tue=off;wed=09:00-17:00/hours:480;…`
    public static func canonical(_ schedule: WeeklySchedule) -> String {
        orderedWeekdays
            .map { "\(shortToken(for: $0))=\(canonical(schedule.rule(for: $0)))" }
            .joined(separator: ";")
    }

    /// 16 hex characters of SHA-256 over ``canonical(_:)``. Two records
    /// carrying the same digest describe the same schedule; a digest is
    /// enough to prove a proposed change was or was not the one applied.
    public static func digest(_ schedule: WeeklySchedule) -> String {
        let full = SHA256.hash(data: Data(canonical(schedule).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return String(full.prefix(16))
    }

    /// Comma-separated short names of the weekdays whose rule differs, in
    /// Monday-first order. Empty string when the two schedules match.
    public static func changedDays(
        from current: WeeklySchedule,
        to proposed: WeeklySchedule
    ) -> String {
        orderedWeekdays
            .filter { current.rule(for: $0) != proposed.rule(for: $0) }
            .map { shortToken(for: $0) }
            .joined(separator: ",")
    }

    /// The ``detail`` entries describing a single day's rule, prefixed so two
    /// rules can sit in one record (`todayLock`, `todayUnlock`, …).
    public static func ruleDetail(
        _ rule: DayRule,
        prefix: String
    ) -> [String: AuditValue] {
        var detail: [String: AuditValue] = [
            prefix + "DayOff": .bool(rule.isDayOff),
            prefix + "Lock": .string(AuditTokens.clock(minutes: rule.lockMinutes)),
            prefix + "Unlock": .string(AuditTokens.clock(minutes: rule.unlockMinutes)),
            prefix + "Mode": .string(rule.mode.rawValue)
        ]
        if let limit = rule.hoursLimitMinutes {
            detail[prefix + "HoursLimitMinutes"] = .int(limit)
        }
        return detail
    }

    /// Weekdays in Monday-first order. `Weekday`'s raw values follow the
    /// Gregorian calendar (Sunday = 1), which would put Sunday first and make
    /// the canonical string read oddly for a work schedule.
    private static let orderedWeekdays: [Weekday] = [
        .monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday
    ]

    private static func shortToken(for weekday: Weekday) -> String {
        weekday.shortName.lowercased()
    }

    private static func canonical(_ rule: DayRule) -> String {
        guard !rule.isDayOff else { return "off" }
        var text = "\(AuditTokens.clock(minutes: rule.lockMinutes))"
            + "-\(AuditTokens.clock(minutes: rule.unlockMinutes))"
            + "/\(rule.mode.rawValue)"
        if let limit = rule.hoursLimitMinutes {
            text += ":\(limit)"
        }
        if rule.exception != nil {
            text += "+exc"
        }
        return text
    }
}
