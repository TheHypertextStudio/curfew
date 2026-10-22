import Foundation

public extension SunriseWakePlanner {
    /// Resolves a local presentation occurrence without authorizing helper operations.
    ///
    /// Inert pending execution of the failing presentation contracts. The eventual
    /// resolver must preserve an occurrence through its unlock-plus-five-minute hold.
    func presentationPlan(
        schedule: WeeklySchedule,
        appearance: RestAppearancePreferences,
        at date: Date,
        calendar: Calendar
    ) -> SunriseWakePlan? {
        nil
    }
}
