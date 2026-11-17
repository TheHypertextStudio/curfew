import CurfewKit
import Foundation

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

    static func resolve(_ situation: TodaySituation, voice: VoicePack = .standard)
        -> TodayPresentation {
        guard situation.setupComplete, situation.enforcing else {
            return statement(voice.curfewOff, line: voice.curfewOffDetail, turnOn: true)
        }
        if situation.phase == .locked {
            let line = situation.unlockDate.map { voice.unlocksAt($0) }
            return statement(voice.lockedHeadline, line: line, symbol: .locked)
        }
        if let release = situation.overrideEnds {
            return statement(voice.overrideUntil(VoicePack.time(release)), oneThing: true)
        }
        guard let curfew = situation.upcomingCurfew,
              situation.phase == .working || situation.phase == .warning
        else {
            return statement(voice.noCurfewToday, oneThing: true)
        }
        return counting(situation, curfew: curfew, voice: voice)
    }

    private static func counting(
        _ situation: TodaySituation, curfew: Date, voice: VoicePack
    ) -> TodayPresentation {
        let minutes = max(0, situation.minutesRemaining)
        let countdown = String(format: "%d:%02d", minutes / 60, minutes % 60)
        let stage = situation.phase == .warning ? voice.stageLine(situation.warningStage) : nil
        let curfewLine = voice.untilCurfew(curfew)
        let spokenLeft = VoicePack.spokenDuration(TimeInterval(minutes * 60))
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
