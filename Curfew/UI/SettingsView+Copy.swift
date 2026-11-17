import CurfewKit
import Foundation

/// Settings sentences that are built from values, kept here so they can be
/// tested and read in one place.
enum SettingsCopy {
    static let shutdownPermissionReason = "Curfew shuts this Mac down through System Events, "
        + "so macOS asks for permission when you turn this on."
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

/// Words for the questions editor. Morning questions belong to Sunrise;
/// evening questions are asked at curfew.
enum ReflectionPromptsCopy {
    static let gatesTitle = "Questions"
    static let gatesSubtitle = "Curfew asks at Sunrise and again at curfew. You can skip either."
    static let askAtSunrise = "Ask at Sunrise"
    static let askAtCurfew = "Ask at curfew"
    static let sunriseTitle = "Sunrise questions"
    static let sunriseSubtitle = "Asked before the day starts."
    static let curfewTitle = "Curfew questions"
    static let curfewSubtitle = "Asked when this Mac locks."
    static let defaultsTitle = "Default questions"
    static let defaultsSubtitle = "Start over with the questions Curfew comes with."
    static let restoreButton = "Restore defaults…"
    static let restoreTitle = "Replace your questions with the defaults?"
    static let restoreMessage = "Every question you wrote or changed is replaced, "
        + "and both switches turn back on. This can't be undone."
    static let restoreConfirm = "Replace questions"
}
