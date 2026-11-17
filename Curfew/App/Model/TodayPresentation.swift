import CurfewKit
import Foundation

/// What Curfew says on Today and in the menu bar. One value, so a voice pack
/// can replace every line at once; no view writes these strings inline.
/// Times are passed in already formatted by the locale (see ``time(_:)``).
struct TodayVoice: Equatable, Sendable {
    var thirtyMinutes = "Decide what gets finished and what waits."
    var fifteenMinutes = "Finish what you're in. Don't start anything."
    var fiveMinutes = "Save everything."
    var oneMinute = "Last call."
    var lockedHeadline = "That's the day."
    var curfewOff = "Curfew is off."
    var curfewOffLine = "Nothing locks until you turn it back on."
    var noCurfewToday = "No curfew today."
    var turnOn = "Turn on Curfew"
    var moreTime = "15 more minutes"
    var callItADay = "Call it a day"
    var keepHolding = "Keep holding."
    var added = "Added"
    var noExtensionsLeft = "No extensions left"
    var oneThingQuestion = "What is today for?"
    var menuCurfewOff = "Curfew is off"
    var menuNoCurfew = "No curfew today"
    var menuLocked = "Locked"

    static let standard = TodayVoice()

    func untilCurfew(at time: String) -> String {
        "until curfew at \(time)"
    }

    func unlocksAt(_ time: String) -> String {
        "Unlocks at \(time)"
    }

    func curfewAt(_ time: String) -> String {
        "Curfew at \(time)"
    }

    func curfewIn(minutes: Int) -> String {
        minutes == 1 ? "Curfew in 1 minute" : "Curfew in \(minutes) minutes"
    }

    func lockedUntil(_ time: String) -> String {
        "Locked until \(time)"
    }

    func overrideUntil(_ time: String) -> String {
        "Override until \(time)"
    }

    func keepHolding(extensionsLeft: Int) -> String {
        "Keep holding. \(extensionsLeft) left this week"
    }

    func laterCurfew(startingOn day: String) -> String {
        "Your later curfew starts \(day). Until then, the old one stands."
    }

    func earlierCurfew(startingOn day: String) -> String {
        "Your earlier curfew starts \(day)."
    }

    /// The line for a warning stage, or `nil` outside the warning half hour.
    func stageLine(for stage: WarningStage) -> String? {
        switch stage {
        case .thirtyMinutes: thirtyMinutes
        case .fifteenMinutes: fifteenMinutes
        case .fiveMinutes, .twoMinutes: fiveMinutes
        case .oneMinute: oneMinute
        case .none, .lockout: nil
        }
    }

    /// A clock time in the person's locale, e.g. "6:00 PM" or "18:00".
    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// A duration as VoiceOver should say it, e.g. "2 hours, 30 minutes".
    static func spokenDuration(_ interval: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .full
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute]
        let rounded = (max(interval, 60) / 60).rounded(.up) * 60
        return formatter.string(from: rounded) ?? ""
    }
}

/// The facts Today needs, gathered from the model so the resolution below is
/// a pure function that tests can drive directly.
struct TodaySituation: Equatable {
    var setupComplete: Bool
    var enforcing: Bool
    var phase: EnforcementPhase
    var warningStage: WarningStage
    var minutesRemaining: Int
    /// The next lock as the person should read it; never in the past.
    var upcomingCurfew: Date?
    var unlockDate: Date?
    /// The end of an override that does not re-lock tonight.
    var overrideEnds: Date?
    var canRequestExtension: Bool
    var extensionsRemaining: Int
    var canCallItADay: Bool
}

/// Everything Today and the menu bar popover put on screen. The sky holds
/// time and voice; the ground holds what the person does.
struct TodayPresentation: Equatable {
    enum Headline: Equatable {
        /// Hours and minutes left, `H:MM`.
        case countdown(String)
        /// A short sentence in place of the countdown.
        case statement(String)
    }

    enum MoreTime: Equatable {
        case available(extensionsLeft: Int)
        case exhausted
    }

    var headline: Headline
    var line: String?
    var lineSymbol: HorizonSymbol?
    /// What VoiceOver reads for the headline and line together.
    var spokenTime: String
    var moreTime: MoreTime?
    var callsItADay: Bool
    var offersTurnOn: Bool
    /// Whether the ground carries the one thing.
    var showsOneThing: Bool

    /// Whether the headline is the countdown rather than a statement.
    var isCountdown: Bool {
        if case .countdown = headline {
            return true
        }
        return false
    }

    static func resolve(_ situation: TodaySituation, voice: TodayVoice = .standard)
        -> TodayPresentation {
        guard situation.setupComplete, situation.enforcing else {
            return statement(voice.curfewOff, line: voice.curfewOffLine, turnOn: true)
        }
        if situation.phase == .locked {
            let line = situation.unlockDate.map { voice.unlocksAt(TodayVoice.time($0)) }
            return statement(voice.lockedHeadline, line: line, symbol: .locked)
        }
        if let release = situation.overrideEnds {
            return statement(voice.overrideUntil(TodayVoice.time(release)), oneThing: true)
        }
        guard let curfew = situation.upcomingCurfew,
              situation.phase == .working || situation.phase == .warning
        else {
            return statement(voice.noCurfewToday, oneThing: true)
        }
        return counting(situation, curfew: curfew, voice: voice)
    }

    private static func counting(
        _ situation: TodaySituation, curfew: Date, voice: TodayVoice
    ) -> TodayPresentation {
        let minutes = max(0, situation.minutesRemaining)
        let countdown = String(format: "%d:%02d", minutes / 60, minutes % 60)
        let stage = situation.phase == .warning ? voice.stageLine(for: situation.warningStage) : nil
        let curfewLine = voice.untilCurfew(at: TodayVoice.time(curfew))
        let spokenLeft = TodayVoice.spokenDuration(TimeInterval(minutes * 60))
        let moreTime: MoreTime? = if situation.canRequestExtension {
            situation.extensionsRemaining > 0
                ? .available(extensionsLeft: situation.extensionsRemaining) : .exhausted
        } else {
            nil
        }
        return TodayPresentation(
            headline: .countdown(countdown),
            line: stage ?? curfewLine,
            lineSymbol: stage == nil ? .curfew : nil,
            spokenTime: stage.map { "\(spokenLeft) until curfew. \($0)" }
                ?? "\(spokenLeft) \(curfewLine)",
            moreTime: moreTime,
            callsItADay: situation.canCallItADay,
            offersTurnOn: false,
            showsOneThing: true
        )
    }

    private static func statement(
        _ headline: String, line: String? = nil, symbol: HorizonSymbol? = nil,
        turnOn: Bool = false, oneThing: Bool = false
    ) -> TodayPresentation {
        TodayPresentation(
            headline: .statement(headline),
            line: line,
            lineSymbol: symbol,
            spokenTime: [headline, line].compactMap(\.self).joined(separator: " "),
            moreTime: nil,
            callsItADay: false,
            offersTurnOn: turnOn,
            showsOneThing: oneThing
        )
    }
}

/// Today's one thing: the morning's answer to "What is today for?" and
/// whether it has been ticked.
struct TodayOneThing: Equatable {
    var text: String
    var isDone: Bool
}
