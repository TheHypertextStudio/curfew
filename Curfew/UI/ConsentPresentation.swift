import CurfewKit
import Foundation

/// A preview of the action the app will apply, using current settings rather
/// than trusting an assistant's description or requested duration.
struct ConsentPresentation {
    let summary: String
    let detail: String
    let canApprove: Bool

    init(
        request: MCPPendingRequest,
        schedule: WeeklySchedule,
        extensionMinutes: Int,
        canRequestExtension: Bool,
        extensionsRemaining: Int,
        pendingScheduleChange: PendingScheduleChange? = nil
    ) {
        guard request.status == .pending,
              let data = request.argumentsJSON.data(using: .utf8),
              let args = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            self = .unavailable
            return
        }
        switch request.tool {
        case .requestExtension:
            self.summary = "Extend this session by \(extensionMinutes) minutes."
            if extensionsRemaining <= 0 {
                self.detail = "No extensions left this week."
            } else {
                self.detail = canRequestExtension
                    ? "Uses one of your remaining weekly extensions."
                    : "An extension is no longer available for this session."
            }
            self.canApprove = canRequestExtension && extensionsRemaining > 0
        case .requestOverride:
            self.summary = "Overrides need your confirmation in Curfew."
            self.detail = "Open the lockout screen to request an override."
            self.canApprove = false
        case .setSchedule:
            self = Self.schedulePreview(args, schedule: schedule, pending: pendingScheduleChange)
        }
    }

    private static let unavailable = ConsentPresentation(
        summary: "This request can't be reviewed.",
        detail: "Deny it and ask the assistant to send a new request.",
        canApprove: false
    )

    private init(summary: String, detail: String, canApprove: Bool) {
        self.summary = summary
        self.detail = detail
        self.canApprove = canApprove
    }

    private static func schedulePreview(
        _ args: [String: Any], schedule: WeeklySchedule, pending: PendingScheduleChange?
    ) -> ConsentPresentation {
        let weekdays: [String: Weekday] = [
            "monday": .monday, "tuesday": .tuesday, "wednesday": .wednesday,
            "thursday": .thursday, "friday": .friday, "saturday": .saturday, "sunday": .sunday
        ]
        guard let name = args["weekday"] as? String,
              let weekday = weekdays[name.lowercased()],
              let lockText = args["lock_time"] as? String,
              let lock = minutes(lockText)
        else { return .unavailable }
        let current = schedule.rule(for: weekday)
        guard let rule = proposedRule(args, current: current, lock: lock)
        else { return .unavailable }
        var proposed = schedule
        proposed.rules[weekday] = rule
        let summary = rule.isDayOff ? "Make \(weekday.shortName) a day off."
            : "\(weekday.shortName): lock at \(clock(lock)); unlock at \(clock(rule.unlockMinutes))"
            + (rule.unlockMinutes <= lock ? " the next day." : ".")
        let classification = SchedulePolicyEngine().classifyChange(from: schedule, to: proposed)
        var detail = switch classification {
        case .weaker: "This change waits at least 24 hours and until any active lockout ends."
        case .stricter: "This change takes effect at the next midnight."
        case .noChange: "This matches your current schedule."
        }
        detail += pendingDetail(
            pending,
            schedule: schedule,
            proposed: proposed,
            classification: classification
        )
        if current.mode != .time, !rule.isDayOff {
            detail = "Switches this day to a time-based curfew. " + detail
        }
        return ConsentPresentation(summary: summary, detail: detail, canApprove: true)
    }

    private static func proposedRule(
        _ args: [String: Any],
        current: DayRule,
        lock: Int
    ) -> DayRule? {
        let unlock: Int
        if let value = args["unlock_time"] {
            guard let text = value as? String,
                  let parsed = minutes(text) else { return nil }
            unlock = parsed
        } else {
            unlock = current.unlockMinutes
        }
        let isDayOff: Bool
        if let value = args["is_day_off"] {
            if let flag = value as? Bool {
                isDayOff = flag
            } else if let text = value as? String, ["true", "false"].contains(text.lowercased()) {
                isDayOff = (text as NSString).boolValue
            } else {
                return nil
            }
        } else {
            isDayOff = current.isDayOff
        }
        return DayRule(
            isDayOff: isDayOff, lockMinutes: lock, unlockMinutes: unlock,
            exception: current.exception
        )
    }

    private static func pendingDetail(
        _ pending: PendingScheduleChange?, schedule: WeeklySchedule,
        proposed: WeeklySchedule, classification: ScheduleChangeClassification
    ) -> String {
        guard let pending else { return "" }
        let discarded = Weekday.allCases.filter {
            pending.proposedSchedule.rule(for: $0) != schedule.rule(for: $0)
                && pending.proposedSchedule.rule(for: $0) != proposed.rule(for: $0)
        }.map(\.shortName).joined(separator: ", ")
        var detail = classification == .noChange
            ? " Cancels your pending schedule change."
            : " Replaces your pending schedule change and restarts its waiting period."
        if !discarded.isEmpty {
            detail += " Discards pending edits for \(discarded)."
        }
        return detail
    }

    private static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0 ..< 24).contains(hour), (0 ..< 60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    private static func clock(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}
