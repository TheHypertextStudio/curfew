import Foundation

/// Every line Curfew says at its key moments, in one place, so a theme can
/// swap the voice without touching a view. Views read these lines; none of
/// them write the strings inline.
///
/// A pack has two kinds of line. The lines that carry the voice (the warning
/// lines, the lock's headline, the questions, the greetings) are written per
/// pack. The vocabulary (control labels such as "Call it a day", status lines
/// such as "Curfew is off.") is the same in every pack, because the spec
/// gives one word per thing everywhere. Times are formatted by the locale,
/// never as hard-coded strings.
///
/// ``standard`` is the launch design's "Default voice" table. The person picks
/// a pack in Settings > Rest screen and can rewrite a handful of its lines in
/// their own words; ``applying(_:)`` lays those over the pack.
public struct VoicePack: Equatable, Sendable, Identifiable {
    /// The lines a person can rewrite in their own words: the ones that carry
    /// the voice at the moments people notice it.
    public enum Line: String, CaseIterable, Codable, Sendable {
        case lockedHeadline
        case thirtyMinutes
        case fifteenMinutes
        case fiveMinutes
        case lastMinute
        case sunriseGreeting
        case sunriseQuestion
        case overrideQuestion
    }

    public let id: String
    /// One plain word, as the editor lists it.
    public let name: String
    /// What the voice sounds like, in one short sentence.
    public let summary: String

    // MARK: Warnings

    public private(set) var thirtyMinuteLine: String
    public private(set) var fifteenMinuteLine: String
    public private(set) var fiveMinuteLine: String
    public private(set) var lastMinuteLine: String
    public let presenceTitle: String
    public let presenceBody: String

    // MARK: Locked

    public private(set) var lockedHeadline: String
    public private(set) var overrideQuestion: String
    public let released: String

    // MARK: Evening close-out

    public let closeOutTitle: String
    public let closeOutSubtitle: String
    public let oneThingQuestion: String
    public let noQuestionsTitle: String
    public let noQuestionsDetail: String

    // MARK: Sunrise

    public let leadInHeadline: String
    public private(set) var gateHeadline: String
    public private(set) var gateQuestion: String

    // MARK: The voices

    /// The default voice: dry, firm and short.
    public static let standard = VoicePack(
        id: "default",
        name: "Firm",
        summary: "Short and certain.",
        thirtyMinuteLine: "Decide what gets finished and what waits.",
        fifteenMinuteLine: "Finish what you're in. Don't start anything.",
        fiveMinuteLine: "Save everything.",
        lastMinuteLine: "Last call.",
        presenceTitle: "Still with it?",
        presenceBody: "You're at this Mac but haven't touched it in a while. "
            + "Back to work, or call it a break.",
        lockedHeadline: "That's the day.",
        overrideQuestion: "What can't wait?",
        released: "Curfew's over. Welcome back.",
        closeOutTitle: "Close out the day",
        closeOutSubtitle: "Two minutes now, a head start tomorrow.",
        oneThingQuestion: "Did you do the one thing?",
        noQuestionsTitle: "No questions tonight.",
        noQuestionsDetail: "Add some in Journal once you're back.",
        leadInHeadline: "Nearly morning.",
        gateHeadline: "Morning.",
        gateQuestion: "What is today for?"
    )

    /// Warm and unhurried, and just as certain about the stop.
    public static let gentle = VoicePack(
        id: "gentle",
        name: "Gentle",
        summary: "Warm and unhurried.",
        thirtyMinuteLine: "Choose what to finish. The rest can wait.",
        fifteenMinuteLine: "Find a good place to stop.",
        fiveMinuteLine: "Save your work.",
        lastMinuteLine: "Time to rest.",
        presenceTitle: "Still here?",
        presenceBody: "You're at this Mac but haven't touched it in a while. "
            + "Pick it back up, or take a proper break.",
        lockedHeadline: "That's enough for today.",
        overrideQuestion: "What needs you tonight?",
        released: "Curfew's over. Good to see you.",
        closeOutTitle: "Before you go",
        closeOutSubtitle: "A few minutes now make tomorrow easier.",
        oneThingQuestion: "Did you get to the one thing?",
        noQuestionsTitle: "Nothing to answer tonight.",
        noQuestionsDetail: "You can add questions in Journal later.",
        leadInHeadline: "Morning is close.",
        gateHeadline: "Good morning.",
        gateQuestion: "What matters most today?"
    )

    /// Wry, with a straight face. The joke is how sure it is.
    public static let playful = VoicePack(
        id: "playful",
        name: "Playful",
        summary: "Wry, with a straight face.",
        thirtyMinuteLine: "Half an hour. Pick your battles.",
        fifteenMinuteLine: "Land the plane. No new flights.",
        fiveMinuteLine: "Save it. Then save it again.",
        lastMinuteLine: "Pencils down.",
        presenceTitle: "Hello?",
        presenceBody: "You're at this Mac but haven't touched it in a while. "
            + "Back to it, or make the break official.",
        lockedHeadline: "Closed for the night.",
        overrideQuestion: "What's on fire?",
        released: "Curfew's over. This Mac is yours again.",
        closeOutTitle: "Before lights out",
        closeOutSubtitle: "Leave a note for tomorrow's you.",
        oneThingQuestion: "Did the one thing happen?",
        noQuestionsTitle: "No homework tonight.",
        noQuestionsDetail: "Add questions in Journal when you're back.",
        leadInHeadline: "Almost time.",
        gateHeadline: "New day.",
        gateQuestion: "What's the one thing today?"
    )

    /// Every voice Curfew ships, in the order the editor lists them.
    public static let all = [standard, gentle, playful]

    /// The voice a saved choice speaks in.
    public init(_ choice: RestAppearancePreferences.Voice) {
        switch choice {
        case .standard: self = .standard
        case .gentle: self = .gentle
        case .playful: self = .playful
        }
    }

    private init(
        id: String, name: String, summary: String,
        thirtyMinuteLine: String, fifteenMinuteLine: String, fiveMinuteLine: String,
        lastMinuteLine: String, presenceTitle: String, presenceBody: String,
        lockedHeadline: String, overrideQuestion: String, released: String,
        closeOutTitle: String, closeOutSubtitle: String, oneThingQuestion: String,
        noQuestionsTitle: String, noQuestionsDetail: String,
        leadInHeadline: String, gateHeadline: String, gateQuestion: String
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.thirtyMinuteLine = thirtyMinuteLine
        self.fifteenMinuteLine = fifteenMinuteLine
        self.fiveMinuteLine = fiveMinuteLine
        self.lastMinuteLine = lastMinuteLine
        self.presenceTitle = presenceTitle
        self.presenceBody = presenceBody
        self.lockedHeadline = lockedHeadline
        self.overrideQuestion = overrideQuestion
        self.released = released
        self.closeOutTitle = closeOutTitle
        self.closeOutSubtitle = closeOutSubtitle
        self.oneThingQuestion = oneThingQuestion
        self.noQuestionsTitle = noQuestionsTitle
        self.noQuestionsDetail = noQuestionsDetail
        self.leadInHeadline = leadInHeadline
        self.gateHeadline = gateHeadline
        self.gateQuestion = gateQuestion
    }

    // MARK: Your own words

    /// The pack's own words for a line the person can rewrite.
    public func line(_ line: Line) -> String {
        switch line {
        case .lockedHeadline: lockedHeadline
        case .thirtyMinutes: thirtyMinuteLine
        case .fifteenMinutes: fifteenMinuteLine
        case .fiveMinutes: fiveMinuteLine
        case .lastMinute: lastMinuteLine
        case .sunriseGreeting: gateHeadline
        case .sunriseQuestion: gateQuestion
        case .overrideQuestion: overrideQuestion
        }
    }

    /// This pack with the person's own words laid over it. A line they left
    /// empty keeps the pack's words.
    public func applying(_ custom: VoiceCustomLines) -> VoicePack {
        var pack = self
        for line in Line.allCases {
            guard let text = custom[line] else { continue }
            switch line {
            case .lockedHeadline: pack.lockedHeadline = text
            case .thirtyMinutes: pack.thirtyMinuteLine = text
            case .fifteenMinutes: pack.fifteenMinuteLine = text
            case .fiveMinutes: pack.fiveMinuteLine = text
            case .lastMinute: pack.lastMinuteLine = text
            case .sunriseGreeting: pack.gateHeadline = text
            case .sunriseQuestion: pack.gateQuestion = text
            case .overrideQuestion: pack.overrideQuestion = text
            }
        }
        return pack
    }

    // MARK: Shared vocabulary (the same in every voice)

    public var untilCurfewPrefix: String {
        "until curfew at"
    }

    public var callItADay: String {
        "Call it a day"
    }

    public var added: String {
        "Added"
    }

    public var noExtensionsLeft: String {
        "No extensions left"
    }

    public var curfewOff: String {
        "Curfew is off."
    }

    public var curfewOffDetail: String {
        "Nothing locks until you turn it back on."
    }

    public var noCurfewToday: String {
        "No curfew today."
    }

    public var turnOn: String {
        "Turn on Curfew"
    }

    public var keepHolding: String {
        "Keep holding."
    }

    public var overrideHolding: String {
        keepHolding
    }

    public var overrideEntry: String {
        "Need to get back in?"
    }

    public var noOverridesLeft: String {
        "No overrides left this week"
    }

    public var unlockPassed: String {
        "The unlock time has passed. This Mac is still locked."
    }

    public var unlockUnknown: String {
        "This Mac stays locked until the schedule lifts."
    }

    public var uninstallWhileLocked: String {
        "Uninstall is available once curfew lifts."
    }

    public var closeOutSave: String {
        "Save and close"
    }

    public var closeOutSkip: String {
        "Skip"
    }

    public var oneThingYes: String {
        "Yes"
    }

    public var oneThingNo: String {
        "No"
    }

    public var gateAction: String {
        "Start the day"
    }

    public var lastNightPrefix: String {
        "Last night you left:"
    }

    /// The menu bar's short statuses, without a closing full stop.
    public var menuCurfewOff: String {
        "Curfew is off"
    }

    public var menuNoCurfew: String {
        "No curfew today"
    }

    public var menuLocked: String {
        "Locked"
    }

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
        "\(keepHolding) \(remaining) left this week"
    }

    public func lastNight(_ note: String) -> String {
        "\(lastNightPrefix) \(note)"
    }

    /// The menu bar's status while working: "Curfew at 6:00 PM".
    public func curfewAt(_ time: String) -> String {
        "Curfew at \(time)"
    }

    /// The menu bar's status in the warning half hour: "Curfew in 5 minutes".
    public func curfewIn(minutes: Int) -> String {
        "Curfew in \(Self.minutes(max(1, minutes)))"
    }

    /// The menu bar's status while locked: "Locked until 7:00 AM".
    public func lockedUntil(_ time: String) -> String {
        "Locked until \(time)"
    }

    /// While an override holds the lock open: "Override until 9:30 PM".
    public func overrideUntil(_ time: String) -> String {
        "Override until \(time)"
    }

    public func laterCurfew(startingOn day: String) -> String {
        "Your later curfew starts \(day). Until then, the old one stands."
    }

    public func earlierCurfew(startingOn day: String) -> String {
        "Your earlier curfew starts \(day)."
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
            noCurfewToday, turnOn, keepHolding, menuCurfewOff, menuNoCurfew, menuLocked,
            thirtyMinuteLine, fifteenMinuteLine, fiveMinuteLine, lastMinuteLine, presenceTitle,
            presenceBody, lockedHeadline, overrideEntry, overrideQuestion, overrideHolding,
            noOverridesLeft, released, unlockPassed, unlockUnknown, uninstallWhileLocked,
            closeOutTitle, closeOutSubtitle, closeOutSave, closeOutSkip, oneThingQuestion,
            oneThingYes, oneThingNo, noQuestionsTitle, noQuestionsDetail, leadInHeadline,
            gateHeadline, gateQuestion, gateAction, lastNightPrefix
        ]
    }

    /// The lines written for this pack, as opposed to the shared vocabulary.
    public var voiceLines: [String] {
        [
            thirtyMinuteLine, fifteenMinuteLine, fiveMinuteLine, lastMinuteLine, presenceTitle,
            presenceBody, lockedHeadline, overrideQuestion, released, closeOutTitle,
            closeOutSubtitle, oneThingQuestion, noQuestionsTitle, noQuestionsDetail,
            leadInHeadline, gateHeadline, gateQuestion
        ]
    }

    // MARK: Formatting

    /// A clock time in the person's locale, e.g. "6:00 PM" or "18:00".
    public static func time(
        _ date: Date, locale: Locale = .autoupdatingCurrent,
        timeZone: TimeZone = .autoupdatingCurrent
    ) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.locale = locale
        style.timeZone = timeZone
        return date.formatted(style)
    }

    /// A duration as VoiceOver should say it, e.g. "2 hours, 30 minutes".
    public static func spokenDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute]
        let rounded = (max(interval, 60) / 60).rounded(.up) * 60
        return formatter.string(from: rounded) ?? ""
    }

    private static func minutes(_ count: Int) -> String {
        count == 1 ? "1 minute" : "\(count) minutes"
    }
}

/// The person's own words for the lines that carry the voice, kept with the
/// theme on this Mac. Every line is trimmed, held to one line and
/// ``maximumLength`` characters; an empty line means "use the pack's words".
public struct VoiceCustomLines: Equatable, Sendable {
    /// The longest a line may be, in characters.
    public static let maximumLength = 60

    private var storage: [VoicePack.Line: String]

    public init(_ lines: [VoicePack.Line: String] = [:]) {
        self.storage = lines.compactMapValues(Self.normalized)
    }

    /// The person's words for `line`, or nil to use the pack's.
    public subscript(line: VoicePack.Line) -> String? {
        storage[line]
    }

    /// A copy with `line` set to `text`; nil or empty text returns the line
    /// to the pack's words.
    public func setting(_ line: VoicePack.Line, to text: String?) -> VoiceCustomLines {
        var copy = self
        copy.storage[line] = text.flatMap(Self.normalized)
        return copy
    }

    public var isEmpty: Bool {
        storage.isEmpty
    }

    /// How many lines are in the person's words.
    public var count: Int {
        storage.count
    }

    /// Trimmed, on one line, at most ``maximumLength`` characters; nil when
    /// nothing is left.
    public static func normalized(_ text: String) -> String? {
        let oneLine = text.components(separatedBy: .newlines).joined(separator: " ")
        let trimmed = oneLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(maximumLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension VoiceCustomLines: Codable {
    /// Stored as an object keyed by line name. Unknown lines and values that
    /// are not text are dropped, so a damaged record keeps its good lines.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode([String: JSONText].self)) ?? [:]
        var lines: [VoicePack.Line: String] = [:]
        for (key, value) in raw {
            guard let line = VoicePack.Line(rawValue: key), let text = value.text else { continue }
            lines[line] = text
        }
        self.init(lines)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(Dictionary(uniqueKeysWithValues: storage.map {
            ($0.key.rawValue, $0.value)
        }))
    }

    /// A JSON value that is text, or anything else (read as nil).
    private struct JSONText: Decodable {
        let text: String?

        init(from decoder: Decoder) throws {
            self.text = try? decoder.singleValueContainer().decode(String.self)
        }
    }
}

/// The lock's headline under its old name, for the model code that sets it
/// when the lock begins. Every entry now comes from ``VoicePack``: the lock
/// says one thing, the active voice's headline, instead of rotating status
/// reports.
public enum EncouragementMessageCatalog {
    public static let messages = [VoicePack.standard.lockedHeadline]

    /// Shown after an override returns the Mac.
    public static let postOverride = VoicePack.standard.released

    public static func next(after _: String?, voice: VoicePack = .standard) -> String {
        voice.lockedHeadline
    }
}
