import CurfewKit
import Foundation

/// Words for the schedule editor and the countdown, in the product's
/// vocabulary: "curfew" for when work ends, "unlocks" for the morning.
enum ScheduleSurfaceCopy {
    static let countdownPrefix = "until curfew at"

    static let weeklyScheduleSubtitle =
        "Pick when curfew starts and when this Mac unlocks."

    static let workEndsLabel = "Curfew"
    static let workResumesLabel = "Unlocks"

    static let mainChecklistItem = weeklyScheduleSubtitle

    static let scheduleOffTitle = "Schedule is off"
    static let scheduleOffBody = "Nothing locks on its own until you turn the weekly schedule on."
    static let turnOnSchedule = "Turn on weekly schedule"
    static let pendingBeforeTurningOn = "A change is waiting to apply. Turn the schedule on after it does."

    static let immediateLockTitle = "Curfew starts right away"
    static let immediateLockBody =
        "Your schedule says work is already over, so this Mac locks as soon as you confirm."
    static let immediateLockConfirm = "Lock now"
    static let immediateLockCancel = "Not yet"

    static func lockedUntil(_ unlock: String) -> String {
        "This Mac is locked now. Unlocks at \(unlock)."
    }
}
