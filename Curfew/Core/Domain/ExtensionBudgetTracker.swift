import Foundation

/// Tracks how many extension (or override) uses remain in the current weekly
/// budget and resets the count when the configured reset weekday rolls over.
///
/// `CurfewAppModel` holds two instances: one for extension requests and one
/// for override requests. Both are configured from ``CurfewSettings`` and are
/// replaced (with in-use count preserved) when the user changes the weekly
/// limit in Settings.
///
/// The class is `@unchecked Sendable` because `remaining` is mutated only on
/// the `@MainActor` model; the concurrency invariant is enforced at the call
/// site.
public final class ExtensionBudgetTracker: @unchecked Sendable {
    /// Maximum uses allowed per week. Clamped to ≥ 0 on init.
    public let weeklyLimit: Int

    /// Minutes added to the lock time per use. Clamped to ≥ 1 on init.
    public let extensionMinutes: Int

    /// The weekday on which the budget resets to `weeklyLimit`. Shared with
    /// the override tracker so both budgets reset on the same day.
    public let resetWeekday: Weekday

    private let calendar: Calendar
    /// Uses remaining this week. Decrements on ``requestExtension(at:)`` and
    /// resets to ``weeklyLimit`` when the reset boundary passes.
    public private(set) var remaining: Int
    private var lastResetBoundary: Date?

    public init(
        weeklyLimit: Int,
        extensionMinutes: Int,
        resetWeekday: Weekday,
        calendar: Calendar = .current
    ) {
        self.weeklyLimit = max(0, weeklyLimit)
        self.extensionMinutes = max(1, extensionMinutes)
        self.resetWeekday = resetWeekday
        self.calendar = calendar
        self.remaining = max(0, weeklyLimit)
    }

    /// Attempts to consume one use from the budget. Calls ``resetIfNeeded(at:)``
    /// first so a weekly rollover is never missed. Returns `true` and
    /// decrements `remaining` when budget is available; returns `false` when
    /// already exhausted.
    @discardableResult
    public func requestExtension(at date: Date) -> Bool {
        resetIfNeeded(at: date)

        guard remaining > 0 else {
            return false
        }

        remaining -= 1
        return true
    }

    /// Resets `remaining` to `weeklyLimit` when a new reset boundary has
    /// passed since the last recorded boundary. Called once per tick so the
    /// budget always resets at the start of the configured weekday even if no
    /// requests are made.
    public func resetIfNeeded(at date: Date) {
        let currentBoundary = mostRecentResetBoundary(for: date)
        if let lastResetBoundary {
            if currentBoundary > lastResetBoundary {
                remaining = weeklyLimit
                self.lastResetBoundary = currentBoundary
            }
        } else {
            lastResetBoundary = currentBoundary
        }
    }

    private func mostRecentResetBoundary(for date: Date) -> Date {
        let startOfToday = calendar.startOfDay(for: date)
        let targetWeekday = resetWeekday.rawValue

        for dayOffset in 0 ... 6 {
            guard let candidate = calendar
                .date(byAdding: .day, value: -dayOffset, to: startOfToday)
            else {
                continue
            }
            if calendar.component(.weekday, from: candidate) == targetWeekday {
                return candidate
            }
        }

        return startOfToday
    }
}
