import AppIntents
import CurfewKit

/// Weekday choices for ``SetScheduleIntent``, presented as a Shortcuts picker.
///
/// The raw values are the lowercase day names the MCP `curfew_set_schedule`
/// tool advertises in its JSON schema, so the queued `argumentsJSON` is
/// byte-for-byte what the app-side dispatcher (`applyMCPScheduleUpdate`)
/// already parses — no second arguments contract.
enum ScheduleWeekday: String, AppEnum {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Weekday")

    static var caseDisplayRepresentations: [ScheduleWeekday: DisplayRepresentation] = [
        .monday: "Monday",
        .tuesday: "Tuesday",
        .wednesday: "Wednesday",
        .thursday: "Thursday",
        .friday: "Friday",
        .saturday: "Saturday",
        .sunday: "Sunday"
    ]

    /// The MCP-facing token stored verbatim in the queued request arguments.
    var mcpName: String {
        rawValue
    }
}
