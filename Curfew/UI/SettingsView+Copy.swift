import CurfewKit
import Foundation

/// Settings sentences that are built from values, kept here so they can be
/// tested and read in one place.
enum SettingsCopy {
    static let shutdownPermissionReason =
        "Curfew shuts this Mac down through System Events, so macOS asks for permission when you turn this on."
    static let shutdownPermissionDenied =
        "macOS won't let Curfew shut this Mac down yet."

    /// "Curfew warns you 30, 15, 5, 2 and 1 minutes before curfew."
    static func warningSummary(_ intervals: WarningIntervals) -> String {
        let minutes = [
            intervals.thirtyMinutes, intervals.fifteenMinutes, intervals.fiveMinutes,
            intervals.twoMinutes, intervals.oneMinute
        ].map(String.init)
        let list = minutes.dropLast().joined(separator: ", ") + " and " + (minutes.last ?? "")
        return "Curfew warns you \(list) minutes before curfew."
    }
}

/// Ports, poll times and raw identifiers are for whoever is building Curfew,
/// not for the person using it. They appear in the development flavor, or
/// in any build launched with `CURFEW_DIAGNOSTICS=1`.
enum SettingsDeveloperDetail {
    static let isVisible = resolve(
        flavor: .current, environment: ProcessInfo.processInfo.environment
    )

    static func resolve(flavor: CurfewFlavor, environment: [String: String]) -> Bool {
        flavor == .development || environment["CURFEW_DIAGNOSTICS"] == "1"
    }
}
