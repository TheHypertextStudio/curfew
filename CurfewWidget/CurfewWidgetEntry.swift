import Foundation
import WidgetKit

/// One moment of the widget's timeline: the phase, the time left, and the
/// two times the widget can name.
struct CurfewWidgetEntry: TimelineEntry {
    let date: Date
    /// `working`, `warning`, `locked` or `day_off`.
    let phase: String
    /// Whole minutes until curfew; never negative.
    let minutesRemaining: Int
    /// Today's curfew, or `nil` on a day off.
    let lockDate: Date?
    /// When this Mac unlocks, or `nil` on a day off.
    let unlockDate: Date?

    static var placeholder: CurfewWidgetEntry {
        let now = Date()
        return CurfewWidgetEntry(
            date: now,
            phase: "working",
            minutesRemaining: 150,
            lockDate: now.addingTimeInterval(150 * 60),
            unlockDate: nil
        )
    }
}
