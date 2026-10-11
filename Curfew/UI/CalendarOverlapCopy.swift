import Foundation

enum CalendarOverlapCopy {
    static func body(
        eventTitle: String, startTime: String, lockTime: String,
        canRequestExtension: Bool
    ) -> String {
        let timing = "\(eventTitle) starts at \(startTime). Your Mac is scheduled to lock at \(lockTime)."
        return canRequestExtension ? timing + " You can request an extension in Curfew." : timing
    }
}
