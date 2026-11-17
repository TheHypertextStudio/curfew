import Foundation

/// Every line Curfew says at its key moments, in one place, so a theme can
/// swap the voice without touching a view. Views read these lines; none of
/// them write the strings inline.
///
/// The default voice is the launch design's "Default voice" table. It is the
/// only voice for now; the theme editor will add more instances of this type.
/// Times are formatted by the locale, never as hard-coded strings.
public struct VoicePack: Equatable, Sendable, Identifiable {
    public let id: String

    // MARK: Today

    public let untilCurfewPrefix: String
    public let callItADay: String
    public let added: String
    public let noExtensionsLeft: String
    public let curfewOff: String
    public let curfewOffDetail: String

    // MARK: Warnings

    public let thirtyMinuteLine: String
    public let fifteenMinuteLine: String
    public let fiveMinuteLine: String
    public let lastMinuteLine: String
    public let presenceTitle: String
    public let presenceBody: String

    // MARK: Locked

    public let lockedHeadline: String
    public let overrideEntry: String
    public let overrideQuestion: String
    public let overrideHolding: String
    public let noOverridesLeft: String
    public let released: String
    public let unlockPassed: String
    public let unlockUnknown: String
    public let uninstallWhileLocked: String

    // MARK: Evening close-out

    public let closeOutTitle: String
    public let closeOutSubtitle: String
    public let closeOutSave: String
    public let closeOutSkip: String
    public let oneThingQuestion: String
    public let oneThingYes: String
    public let oneThingNo: String
    public let noQuestionsTitle: String
    public let noQuestionsDetail: String

    // MARK: Sunrise

    public let leadInHeadline: String
    public let gateHeadline: String
    public let gateQuestion: String
    public let gateAction: String
    public let lastNightPrefix: String

    /// The default voice: dry, firm and short.
    public static let standard = VoicePack(
        id: "default",
        untilCurfewPrefix: "until curfew at",
        callItADay: "Call it a day",
        added: "Added",
        noExtensionsLeft: "No extensions left",
        curfewOff: "Curfew is off.",
        curfewOffDetail: "Nothing locks until you turn it back on.",
        thirtyMinuteLine: "Decide what gets finished and what waits.",
        fifteenMinuteLine: "Finish what you're in. Don't start anything.",
        fiveMinuteLine: "Save everything.",
        lastMinuteLine: "Last call.",
        presenceTitle: "Still with it?",
        presenceBody: "You're at this Mac but haven't touched it in a while. "
            + "Back to work, or call it a break.",
        lockedHeadline: "That's the day.",
        overrideEntry: "Need to get back in?",
        overrideQuestion: "What can't wait?",
        overrideHolding: "Keep holding.",
        noOverridesLeft: "No overrides left this week",
        released: "Curfew's over. Welcome back.",
        unlockPassed: "The unlock time has passed. This Mac is still locked.",
        unlockUnknown: "This Mac stays locked until the schedule lifts.",
        uninstallWhileLocked: "Uninstall is available once curfew lifts.",
        closeOutTitle: "Close out the day",
        closeOutSubtitle: "Two minutes now, a head start tomorrow.",
        closeOutSave: "Save and close",
        closeOutSkip: "Skip",
        oneThingQuestion: "Did you do the one thing?",
        oneThingYes: "Yes",
        oneThingNo: "No",
        noQuestionsTitle: "No questions tonight.",
        noQuestionsDetail: "Add some in Journal once you're back.",
        leadInHeadline: "Nearly morning.",
        gateHeadline: "Morning.",
        gateQuestion: "What is today for?",
        gateAction: "Start the day",
        lastNightPrefix: "Last night you left:"
    )

    /// Every voice Curfew ships. The default is the only one for now.
    public static let all = [standard]

    // MARK: Composed lines

    /// The line under the warning countdown for `stage`; nil outside warnings.
    public func stageLine(_ stage: WarningStage) -> String? {
        switch stage {
        case .thirtyMinutes: thirtyMinuteLine
        case .fifteenMinutes: fifteenMinuteLine
        case .fiveMinutes, .twoMinutes: fiveMinuteLine
        case .oneMinute: lastMinuteLine
        case .none, .lockout: nil
        }
    }

    /// The notification title: "30 minutes to curfew".
    public func warningTitle(minutes: Int) -> String {
        "\(Self.minutes(max(1, minutes))) to curfew"
    }

    /// Today, under the countdown: "until curfew at 6:00 PM".
    public func untilCurfew(
        _ curfew: Date, locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        "\(untilCurfewPrefix) \(Self.time(curfew, locale: locale, timeZone: timeZone))"
    }

    /// The lock's line: "Unlocks at 7:00 AM".
    public func unlocksAt(
        _ unlock: Date, locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        "Unlocks at \(Self.time(unlock, locale: locale, timeZone: timeZone))"
    }

    /// What VoiceOver hears as the lock appears: "This Mac is locked until 7:00 AM."
    public func lockedSummary(
        until unlock: Date, locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        "This Mac is locked until \(Self.time(unlock, locale: locale, timeZone: timeZone))."
    }

    /// What VoiceOver hears in the lead-in: "This Mac unlocks in 12 minutes."
    public func leadInSummary(minutes: Int) -> String {
        "This Mac unlocks in \(Self.minutes(max(1, minutes)))."
    }

    /// The Sunrise lead-in's line: "Unlocks in 12 minutes". Never "0 minutes".
    public func unlocksIn(minutes: Int) -> String {
        "Unlocks in \(Self.minutes(max(1, minutes)))"
    }

    /// More time on Today, and the notification's quick action.
    public func moreTime(minutes: Int) -> String {
        minutes == 1 ? "1 more minute" : "\(minutes) more minutes"
    }

    /// While holding for more time: "Keep holding. 2 left this week".
    public func holdingWithRemaining(_ remaining: Int) -> String {
        "Keep holding. \(remaining) left this week"
    }

    public func lastNight(_ note: String) -> String {
        "\(lastNightPrefix) \(note)"
    }

    /// Progress toward the override's minimum length: "32 of 50 characters".
    public func overrideProgress(count: Int, minimum: Int) -> String {
        "\(count) of \(minimum) characters"
    }

    /// While the override cools off: "You can unlock in 4:59".
    public func overrideCoolingOff(seconds: Int) -> String {
        let seconds = max(0, seconds)
        return String(format: "You can unlock in %d:%02d", seconds / 60, seconds % 60)
    }

    /// The override's hold to confirm: "Hold to unlock for 15 minutes".
    public func overrideHold(minutes: Int) -> String {
        "Hold to unlock for \(Self.minutes(minutes))"
    }

    /// Every line that takes no argument, for rule checks.
    public var everyFixedLine: [String] {
        [
            untilCurfewPrefix, callItADay, added, noExtensionsLeft, curfewOff, curfewOffDetail,
            thirtyMinuteLine, fifteenMinuteLine, fiveMinuteLine, lastMinuteLine, presenceTitle,
            presenceBody, lockedHeadline, overrideEntry, overrideQuestion, overrideHolding,
            noOverridesLeft, released, unlockPassed, unlockUnknown, uninstallWhileLocked,
            closeOutTitle, closeOutSubtitle, closeOutSave, closeOutSkip, oneThingQuestion,
            oneThingYes, oneThingNo, noQuestionsTitle, noQuestionsDetail, leadInHeadline,
            gateHeadline, gateQuestion, gateAction, lastNightPrefix
        ]
    }

    private static func minutes(_ count: Int) -> String {
        count == 1 ? "1 minute" : "\(count) minutes"
    }

    private static func time(_ date: Date, locale: Locale, timeZone: TimeZone) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }
}

/// The lock's headline under its old name, for the model code that sets it
/// when the lock begins. Every entry now comes from ``VoicePack``: the lock
/// says one thing, "That's the day.", instead of rotating status reports.
public enum EncouragementMessageCatalog {
    public static let messages = [VoicePack.standard.lockedHeadline]

    /// Shown after an override returns the Mac.
    public static let postOverride = VoicePack.standard.released

    public static func next(after _: String?) -> String {
        VoicePack.standard.lockedHeadline
    }
}
