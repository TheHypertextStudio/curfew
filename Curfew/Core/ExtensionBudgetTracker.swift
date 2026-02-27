import Foundation

final class ExtensionBudgetTracker: @unchecked Sendable {
    let weeklyLimit: Int
    let extensionMinutes: Int
    let resetWeekday: Weekday

    private let calendar: Calendar
    private(set) var remaining: Int
    private var lastResetBoundary: Date?

    init(
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

    @discardableResult
    func requestExtension(at date: Date) -> Bool {
        resetIfNeeded(at: date)

        guard remaining > 0 else {
            return false
        }

        remaining -= 1
        return true
    }

    func resetIfNeeded(at date: Date) {
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

        for dayOffset in 0...6 {
            guard let candidate = calendar.date(byAdding: .day, value: -dayOffset, to: startOfToday) else {
                continue
            }
            if calendar.component(.weekday, from: candidate) == targetWeekday {
                return candidate
            }
        }

        return startOfToday
    }
}
