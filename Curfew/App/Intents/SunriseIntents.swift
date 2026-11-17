import AppIntents
import CurfewKit
import Foundation

/// Reads today's Sunrise from the local reflection log, read-only, the same
/// way `curfew-ctl reflections` does. A missing or unreadable log reads as no
/// answer yet, never as an error the automation has to handle.
nonisolated enum SunriseIntentSupport {
    struct Today: Equatable {
        let oneThing: String?
        let isComplete: Bool
    }

    static func today(
        in reflections: [Reflection], now: Date = Date(), calendar: Calendar = .current
    ) -> Today {
        Today(
            oneThing: SunriseDay.oneThing(in: reflections, now: now, calendar: calendar),
            isComplete: SunriseDay.isComplete(in: reflections, now: now, calendar: calendar)
        )
    }

    static func loadToday(
        now: Date = Date(), calendar: Calendar = .current,
        databaseURL: URL = SharedPaths.reflectionDatabase
    ) -> Today {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now
        guard FileManager.default.fileExists(atPath: databaseURL.path),
              let store = try? ReflectionStore(databaseURL: databaseURL, readOnly: true),
              let reflections = try? store.reflections(in: start ... end)
        else { return today(in: [], now: now, calendar: calendar) }
        return today(in: reflections, now: now, calendar: calendar)
    }
}

/// Today's one thing, as answered at Sunrise, for Shortcuts automations.
/// Returns empty text until Sunrise is answered.
struct GetTodaysOneThingIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Today's One Thing"

    static var description = IntentDescription(
        "Returns what you said today is for at Sunrise. Empty until you answer.",
        categoryName: "Sunrise"
    )

    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let oneThing = SunriseIntentSupport.loadToday().oneThing ?? ""
        let dialog: IntentDialog = oneThing.isEmpty
            ? "Nothing is named for today yet."
            : IntentDialog(stringLiteral: "Today is for: \(oneThing)")
        return .result(value: oneThing, dialog: dialog)
    }
}

/// Whether Sunrise was completed today, for Shortcuts automations to branch on.
struct IsSunriseCompleteIntent: AppIntent {
    static var title: LocalizedStringResource = "Is Sunrise Complete"

    static var description = IntentDescription(
        "Returns whether you started the day at Sunrise today.",
        categoryName: "Sunrise"
    )

    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Bool> {
        let complete = SunriseIntentSupport.loadToday().isComplete
        let dialog: IntentDialog = complete
            ? "Sunrise is done for today."
            : "Sunrise isn't done yet today."
        return .result(value: complete, dialog: dialog)
    }
}
