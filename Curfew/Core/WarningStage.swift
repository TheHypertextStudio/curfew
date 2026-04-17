import Foundation

struct WarningIntervals: Codable, Equatable {
    var thirtyMinutes: Int
    var fifteenMinutes: Int
    var fiveMinutes: Int
    var twoMinutes: Int
    var oneMinute: Int

    static let `default` = WarningIntervals(
        thirtyMinutes: 30,
        fifteenMinutes: 15,
        fiveMinutes: 5,
        twoMinutes: 2,
        oneMinute: 1
    )

    var normalized: WarningIntervals {
        var one = max(1, min(oneMinute, 30))
        var two = max(one + 1, min(twoMinutes, 45))
        var five = max(two + 1, min(fiveMinutes, 90))
        var fifteen = max(five + 1, min(fifteenMinutes, 180))
        let thirty = max(fifteen + 1, min(thirtyMinutes, 360))

        // Keep canonical lower stages when clamping higher ones.
        one = min(one, two - 1)
        two = min(two, five - 1)
        five = min(five, fifteen - 1)
        fifteen = min(fifteen, thirty - 1)

        return WarningIntervals(
            thirtyMinutes: thirty,
            fifteenMinutes: fifteen,
            fiveMinutes: five,
            twoMinutes: two,
            oneMinute: one
        )
    }
}

enum WarningStage: Equatable {
    case none
    case thirtyMinutes
    case fifteenMinutes
    case fiveMinutes
    case twoMinutes
    case oneMinute
    case lockout

    static func stage(
        forMinutesRemaining minutes: Int,
        intervals: WarningIntervals = .default
    ) -> WarningStage {
        let normalized = intervals.normalized
        if minutes <= 0 {
            return .lockout
        }
        if minutes <= normalized.oneMinute {
            return .oneMinute
        }
        if minutes <= normalized.twoMinutes {
            return .twoMinutes
        }
        if minutes <= normalized.fiveMinutes {
            return .fiveMinutes
        }
        if minutes <= normalized.fifteenMinutes {
            return .fifteenMinutes
        }
        if minutes <= normalized.thirtyMinutes {
            return .thirtyMinutes
        }
        return .none
    }

    var supportsSnooze: Bool {
        switch self {
        case .thirtyMinutes, .fifteenMinutes:
            true
        case .none, .fiveMinutes, .twoMinutes, .oneMinute, .lockout:
            false
        }
    }

    var showsFloatingTimer: Bool {
        switch self {
        case .fiveMinutes, .twoMinutes, .oneMinute:
            true
        case .none, .thirtyMinutes, .fifteenMinutes, .lockout:
            false
        }
    }

    var overlayOpacity: Double {
        switch self {
        case .none, .thirtyMinutes, .fifteenMinutes:
            0
        case .fiveMinutes:
            0.10
        case .twoMinutes:
            0.25
        case .oneMinute:
            0.40
        case .lockout:
            1.0
        }
    }
}
