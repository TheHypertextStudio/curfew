import Foundation

/// Computes "active work minutes today" for hours-based curfew enforcement.
///
/// In single-device mode the aggregator simply counts minutes from
/// start-of-day to now, excluding stretches of ≥ 5 minutes of idle time
/// (the same threshold `IdleWatcher` uses). When CloudKit device records
/// ship in a later tier, the same aggregator folds heartbeats from other
/// devices into a cross-device total — the contract ("minutes active
/// today") stays stable.
///
/// The type is pure-function / struct-with-inputs by design: the engine
/// calls it once per tick with the current `Date`, the
/// `ActivityStore` events, and (future) `DeviceActivity` heartbeats, and
/// gets back an integer. That keeps `CurfewEnforcementEngine` free of
/// side effects and testable without a clock dependency.
public enum WorkTimeAggregator {
    /// Idle stretches at or above this threshold are excluded. Matches
    /// the default in `IdleWatcher.defaultIdleThresholdSeconds`.
    public static let idleThresholdSeconds: TimeInterval = 5 * 60

    /// Returns the number of active work minutes accumulated today up to
    /// `now`.
    ///
    /// - Parameters:
    ///   - now: The evaluation moment. Typically `Date()` at tick time.
    ///   - events: Activity events covering at least `[startOfDay, now]`.
    ///     The aggregator consumes lockout, session-ended, and extension
    ///     events to bound the active window.
    ///   - idleWindows: Half-open `[start, end)` ranges during which the
    ///     user was idle today. Consumed from `IdleWatcher` transitions
    ///     persisted by the caller; may be empty in which case only
    ///     start-of-day → now is used.
    ///   - calendar: The calendar used to compute start-of-day. Defaults
    ///     to `.current`; tests pin UTC for determinism.
    /// - Returns: Active minutes, clamped to `[0, 24 * 60]`. Negative
    ///   intermediate results are clamped so a clock skew or malformed
    ///   event history can't underflow the enforcement engine.
    public static func activeMinutesToday(
        now: Date,
        events: [ActivityEvent],
        idleWindows: [Range<Date>] = [],
        calendar: Calendar = .current
    ) -> Int {
        let startOfDay = calendar.startOfDay(for: now)
        guard now > startOfDay else {
            return 0
        }

        // Baseline: every second from start-of-day to now is "active"
        // unless subtracted below.
        var activeSeconds = now.timeIntervalSince(startOfDay)

        // Subtract idle windows clipped to today so a single idle range
        // spanning midnight (or the evaluation moment) doesn't over-subtract.
        for window in idleWindows {
            let clippedStart = max(window.lowerBound, startOfDay)
            let clippedEnd = min(window.upperBound, now)
            guard clippedEnd > clippedStart else { continue }
            let duration = clippedEnd.timeIntervalSince(clippedStart)
            if duration >= idleThresholdSeconds {
                activeSeconds -= duration
            }
        }

        // Subtract post-lockout dwell — if today's activity log includes
        // a `lockoutStarted` event, the time from that event to the
        // matching `lockoutEnded` (or now, if still locked) is not
        // "active work"; it's the enforcement window itself.
        let sorted = events
            .filter { $0.timestamp >= startOfDay && $0.timestamp <= now }
            .sorted { $0.timestamp < $1.timestamp }

        var lockoutStart: Date?
        for event in sorted {
            switch event.kind {
            case .lockoutStarted:
                lockoutStart = event.timestamp
            case .lockoutEnded:
                if let start = lockoutStart {
                    let duration = event.timestamp.timeIntervalSince(start)
                    activeSeconds -= max(0, duration)
                    lockoutStart = nil
                }
            default:
                break
            }
        }
        if let start = lockoutStart {
            let duration = now.timeIntervalSince(start)
            activeSeconds -= max(0, duration)
        }

        let minutes = Int(max(0, activeSeconds) / 60.0)
        return min(minutes, 24 * 60)
    }
}
