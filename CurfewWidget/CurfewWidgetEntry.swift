import Foundation
import WidgetKit

/// Snapshot of enforcement state passed to the widget view.
struct CurfewWidgetEntry: TimelineEntry {
    let date: Date
    let phase: String        // "working" | "warning" | "locked" | "day_off"
    let minutesRemaining: Int
    let lockTime: String?    // "HH:MM" of today's lock, nil on day-off/locked
    let unlockTime: String?  // "HH:MM" of today's unlock, nil on day-off
    let warningStage: String // "none" | "T-30" | "T-15" | "T-5" etc.

    static let placeholder = CurfewWidgetEntry(
        date: Date(),
        phase: "working",
        minutesRemaining: 120,
        lockTime: "22:00",
        unlockTime: "08:00",
        warningStage: "none"
    )
}
