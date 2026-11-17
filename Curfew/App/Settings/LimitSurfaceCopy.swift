import CurfewKit
import Foundation

/// Words for the weekly limits in Settings → Warnings and limits.
enum LimitSurfaceCopy {
    static let groupFooter =
        "Raising a limit takes 24 hours to apply. Lowering one applies right away."

    static func value(_ value: Int, of limit: WeeklyLimit) -> String {
        switch limit {
        case .extensionCount, .overrideCount: value.formatted()
        case .extensionMinutes, .overrideMinutes: String(localized: "\(value) min")
        }
    }

    static func waiting(_ raised: String, day: String, time: String, standing: String) -> String {
        "Goes up to \(raised) on \(day) at \(time). Until then, \(standing) stands."
    }

    static func waitingForUnlock(_ raised: String, standing: String) -> String {
        "Goes up to \(raised) once this Mac unlocks. Until then, \(standing) stands."
    }

    static func keep(_ standing: String) -> String {
        "Keep \(standing)"
    }

    static func keepAccessibility(_ title: String, standing: String) -> String {
        "Keep \(title.lowercased()) at \(standing)"
    }
}
