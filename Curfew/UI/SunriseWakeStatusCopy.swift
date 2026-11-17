import CurfewKit
import Foundation

/// The one sentence under "Wake this Mac for Sunrise": when the Mac will wake,
/// or what stops it and where to fix that.
nonisolated struct SunriseWakeStatusCopy: Equatable {
    /// The Settings page that fixes a blocked wake.
    enum Fix: Equatable {
        case protection
        case shutdown
    }

    let sentence: String
    let fix: Fix?

    static func resolve(
        wakeEnabled: Bool,
        curfewOn: Bool,
        status: SunriseWakeCoordinator.Status,
        plan: SunriseWakePlan?,
        now: Date
    ) -> SunriseWakeStatusCopy {
        let calendar = Calendar.current
        guard wakeEnabled else {
            return .init(
                sentence: "Sunrise appears when you first use this Mac in the morning.",
                fix: nil
            )
        }
        guard curfewOn else {
            return .init(sentence: "Curfew is off, so this Mac won't wake for Sunrise.", fix: nil)
        }
        switch status {
        case .helperUnavailable:
            return .init(
                sentence: "This Mac can't wake without the Curfew helper. Set it up in Protection.",
                fix: .protection
            )
        case .requestRejected:
            return .init(
                sentence: "The Curfew helper didn't accept the wake. Repair it in Protection.",
                fix: .protection
            )
        case .batteryExcluded:
            return .init(
                sentence: "This Mac is on battery, so it won't wake. "
                    + "Connect power or allow Sunrise on battery.",
                fix: nil
            )
        case .dismissed:
            return .init(sentence: "Sunrise is done for this morning.", fix: nil)
        case .displayRequested:
            return .init(sentence: "Sunrise is on the screen now.", fix: nil)
        case .scheduled, .waitingForSchedule, .disabled:
            guard let plan else {
                return .init(
                    sentence: "No working morning is coming up, so this Mac won't wake.",
                    fix: nil
                )
            }
            let when = moment(plan.wakeAt, now: now, calendar: calendar)
            if status == .scheduled {
                return .init(sentence: "This Mac will wake at \(when).", fix: nil)
            }
            return .init(
                sentence: "Asking the Curfew helper to wake this Mac at \(when).",
                fix: nil
            )
        }
    }

    /// A shut-down Mac cannot wake itself, so auto-shutdown and Sunrise wake
    /// conflict. Shown only while wake is on.
    static func shutdownWarning(autoShutdownEnabled: Bool, wakeEnabled: Bool) -> String? {
        guard autoShutdownEnabled, wakeEnabled else { return nil }
        return "Auto-shutdown is on. A Mac that has shut down can't wake, "
            + "so Sunrise waits until you turn it on."
    }

    /// "6:30 AM today", "6:30 AM tomorrow" or "6:30 AM on Thursday", in the
    /// person's locale.
    private static func moment(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) {
            return "\(time) today"
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "\(time) tomorrow"
        }
        return "\(time) on \(date.formatted(.dateTime.weekday(.wide)))"
    }
}
