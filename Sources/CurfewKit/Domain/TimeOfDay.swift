import Foundation

/// The four phases of the day the Curfew app icon tracks — the same
/// sunrise → day → sundown → night arc as the Curfew Flow. Drives the runtime
/// Dock icon so the app's presence shifts with the time of day.
///
/// Pure and testable; the AppKit glue that actually swaps the Dock image lives
/// in `DockIconController`.
public enum TimeOfDay: String, CaseIterable, Equatable {
    /// 5am–9am — sunrise.
    case dawn
    /// 9am–5pm — daylight.
    case day
    /// 5pm–9pm — sundown (the brand's signature, and the static app icon).
    case dusk
    /// 9pm–5am — night.
    case night

    /// The phase for a 24-hour `hour` (0…23). Boundaries are inclusive of the
    /// start hour: dawn `[5,9)`, day `[9,17)`, dusk `[17,21)`, night otherwise.
    public static func at(hour: Int) -> TimeOfDay {
        switch hour {
        case 5 ..< 9: .dawn
        case 9 ..< 17: .day
        case 17 ..< 21: .dusk
        default: .night
        }
    }

    /// The phase for `date` in `calendar`.
    public static func at(_ date: Date, calendar: Calendar = .current) -> TimeOfDay {
        at(hour: calendar.component(.hour, from: date))
    }

    /// Name of the asset-catalog image set holding this phase's Dock icon.
    public var dockIconAssetName: String {
        switch self {
        case .dawn: "DockIconDawn"
        case .day: "DockIconDay"
        case .dusk: "DockIconDusk"
        case .night: "DockIconNight"
        }
    }
}
