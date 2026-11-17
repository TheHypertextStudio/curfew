@testable import CurfewKit
import Foundation
import Testing

/// The default voice is the spec's "Default voice" table, word for word.
struct VoicePackTests {
    private let voice = VoicePack.standard
    private let locale = Locale(identifier: "en_US")

    private func time(_ hour: Int, _ minute: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(
            year: 2026, month: 11, day: 16, hour: hour, minute: minute
        ))!
    }

    /// The locale formatter separates the hour and period with a narrow space.
    private func plain(_ line: String) -> String {
        line.replacingOccurrences(of: "\u{202F}", with: " ")
    }

    private var utc: TimeZone {
        TimeZone(identifier: "UTC")!
    }

    @Test("Curfew ships the default voice and two more, in the editor's order")
    func shippedVoices() {
        #expect(VoicePack.all == [.standard, .gentle, .playful])
        #expect(VoicePack.all.map(\.id) == ["default", "gentle", "playful"])
        #expect(VoicePack.all.map(\.name) == ["Firm", "Gentle", "Playful"])
        for choice in RestAppearancePreferences.Voice.allCases {
            #expect(VoicePack(choice).id == choice.rawValue)
        }
    }

    @Test("Warning stage lines follow the voice table")
    func stageLines() {
        #expect(voice.stageLine(.thirtyMinutes) == "Decide what gets finished and what waits.")
        #expect(voice.stageLine(.fifteenMinutes) == "Finish what you're in. Don't start anything.")
        #expect(voice.stageLine(.fiveMinutes) == "Save everything.")
        #expect(voice.stageLine(.twoMinutes) == "Save everything.")
        #expect(voice.stageLine(.oneMinute) == "Last call.")
        #expect(voice.stageLine(.none) == nil)
        #expect(voice.stageLine(.lockout) == nil)
    }

    @Test("Notification titles count down to curfew, never name the app")
    func notificationTitles() {
        #expect(voice.warningTitle(minutes: 30) == "30 minutes to curfew")
        #expect(voice.warningTitle(minutes: 15) == "15 minutes to curfew")
        #expect(voice.warningTitle(minutes: 5) == "5 minutes to curfew")
        #expect(voice.warningTitle(minutes: 1) == "1 minute to curfew")
    }

    @Test("The lock speaks in one headline and one line")
    func lockedLines() {
        #expect(voice.lockedHeadline == "That's the day.")
        #expect(plain(voice.unlocksAt(time(7, 0), locale: locale, timeZone: utc)) ==
            "Unlocks at 7:00 AM")
        #expect(voice.overrideEntry == "Need to get back in?")
        #expect(voice.overrideQuestion == "What can't wait?")
        #expect(voice.released == "Curfew's over. Welcome back.")
        #expect(voice.noOverridesLeft == "No overrides left this week")
        #expect(plain(voice.lockedSummary(until: time(7, 0), locale: locale, timeZone: utc))
            == "This Mac is locked until 7:00 AM.")
        #expect(voice.leadInSummary(minutes: 12) == "This Mac unlocks in 12 minutes.")
    }

    @Test("The override composer reports progress, cooling off and the hold")
    func overrideComposer() {
        #expect(voice.overrideProgress(count: 32, minimum: 50) == "32 of 50 characters")
        #expect(voice.overrideCoolingOff(seconds: 299) == "You can unlock in 4:59")
        #expect(voice.overrideCoolingOff(seconds: 5) == "You can unlock in 0:05")
        #expect(voice.overrideHold(minutes: 15) == "Hold to unlock for 15 minutes")
        #expect(voice.overrideHolding == "Keep holding.")
    }

    @Test("Sunrise lead-in counts minutes with the right number")
    func sunriseLeadIn() {
        #expect(voice.leadInHeadline == "Nearly morning.")
        #expect(voice.unlocksIn(minutes: 12) == "Unlocks in 12 minutes")
        #expect(voice.unlocksIn(minutes: 1) == "Unlocks in 1 minute")
        #expect(voice.unlocksIn(minutes: 0) == "Unlocks in 1 minute")
    }

    @Test("Today, Sunrise and the remaining moments use the table")
    func remainingMoments() {
        #expect(plain(voice.untilCurfew(time(18, 0), locale: locale, timeZone: utc))
            == "until curfew at 6:00 PM")
        #expect(voice.gateHeadline == "Morning.")
        #expect(voice.gateQuestion == "What is today for?")
        #expect(voice.gateAction == "Start the day")
        #expect(voice.lastNight("pick up at the retry test.")
            == "Last night you left: pick up at the retry test.")
        #expect(voice.moreTime(minutes: 15) == "15 more minutes")
        #expect(voice.moreTime(minutes: 1) == "1 more minute")
        #expect(voice.callItADay == "Call it a day")
        #expect(voice.holdingWithRemaining(2) == "Keep holding. 2 left this week")
        #expect(voice.added == "Added")
        #expect(voice.noExtensionsLeft == "No extensions left")
        #expect(voice.curfewOff == "Curfew is off.")
        #expect(voice.curfewOffDetail == "Nothing locks until you turn it back on.")
        #expect(voice.uninstallWhileLocked == "Uninstall is available once curfew lifts.")
    }

    @Test("The presence nudge asks a question and states what it saw")
    func presence() {
        #expect(voice.presenceTitle == "Still with it?")
        #expect(voice.presenceBody
            == "You're at this Mac but haven't touched it in a while. "
            + "Back to work, or call it a break.")
    }

    @Test("The evening close-out offers a head start, and one yes or no")
    func closeOut() {
        #expect(voice.closeOutTitle == "Close out the day")
        #expect(voice.closeOutSubtitle == "Two minutes now, a head start tomorrow.")
        #expect(voice.closeOutSave == "Save and close")
        #expect(voice.oneThingQuestion == "Did you do the one thing?")
        #expect(voice.noQuestionsTitle == "No questions tonight.")
        #expect(voice.noQuestionsDetail == "Add some in Journal once you're back.")
    }

    @Test("No line in any voice uses an exclamation mark, a dash as punctuation, or banned words")
    func rules() {
        let banned = [
            "lockout", "enforcement", "blocking access", "daybreak", "snooze",
            "computer", "device", "daemon", "convince me", "break glass", "!", " - ", "—", "–",
            "intention", "focus", "goal", "rest now", "wrap up", "extension request", "grace",
            "start of work", "morning reflection", "scheduled lockout", "work ends"
        ]
        for pack in VoicePack.all {
            for line in pack.everyFixedLine {
                for word in banned {
                    #expect(!line.lowercased().contains(word), "\(pack.name): \(line) has \(word)")
                }
            }
        }
    }

    @Test("Every line in every voice is sentence case, written out and short")
    func sentenceCaseAndShort() {
        for pack in VoicePack.all {
            for line in pack.everyFixedLine {
                #expect(!line.isEmpty, "\(pack.name) has an empty line")
                #expect(line == line.trimmingCharacters(in: .whitespacesAndNewlines))
                // Today's prefix runs into the time, so it starts lower case.
                if line != pack.untilCurfewPrefix, let first = line.first {
                    #expect(first.isUppercase, "\(pack.name): \(line) is not sentence case")
                }
                // No word after the first is capitalised, except names Curfew owns.
                let words = line.split(separator: " ").dropFirst()
                let allowed: Set = ["Curfew", "Curfew's", "Mac", "Mac.", "Journal", "I"]
                for word in words where word.first?.isUppercase == true {
                    let previous = line.range(of: " \(word)").map {
                        line[line.startIndex ..< $0.lowerBound]
                    }
                    let afterSentence = previous.map {
                        $0.hasSuffix(".") || $0.hasSuffix("?")
                    } ?? false
                    #expect(
                        allowed.contains(String(word)) || afterSentence,
                        "\(pack.name): \(line) capitalises \(word)"
                    )
                }
            }
            for line in pack.voiceLines where line != pack.presenceBody {
                #expect(line.count <= 48, "\(pack.name): \(line) is long")
            }
        }
    }

    @Test("The two new voices are their own, line for line, apart from shared vocabulary")
    func voicesAreDistinct() {
        for (index, pack) in VoicePack.all.enumerated() {
            for other in VoicePack.all[(index + 1)...] {
                for (mine, theirs) in zip(pack.voiceLines, other.voiceLines) {
                    #expect(mine != theirs, "\(pack.name) and \(other.name) share \(mine)")
                }
                #expect(pack.callItADay == other.callItADay)
                #expect(pack.gateAction == other.gateAction)
                #expect(pack.overrideEntry == other.overrideEntry)
            }
        }
    }

    @Test("Own words replace only the lines that carry the voice, and empty means the pack's")
    func customLines() {
        let custom = VoiceCustomLines([
            .lockedHeadline: "  Go see the kids. ",
            .thirtyMinutes: "Half time.",
            .fifteenMinutes: "",
            .sunriseGreeting: "Hello again.",
            .sunriseQuestion: "What's first?",
            .overrideQuestion: "Really?"
        ])
        let pack = VoicePack.gentle.applying(custom)
        #expect(pack.lockedHeadline == "Go see the kids.")
        #expect(pack.stageLine(.thirtyMinutes) == "Half time.")
        #expect(pack.stageLine(.fifteenMinutes) == VoicePack.gentle.fifteenMinuteLine)
        #expect(pack.stageLine(.oneMinute) == VoicePack.gentle.lastMinuteLine)
        #expect(pack.gateHeadline == "Hello again.")
        #expect(pack.gateQuestion == "What's first?")
        #expect(pack.overrideQuestion == "Really?")
        #expect(pack.closeOutTitle == VoicePack.gentle.closeOutTitle)
        #expect(pack.id == "gentle")
        #expect(custom[.fifteenMinutes] == nil)
        #expect(VoicePack.standard.applying(VoiceCustomLines()) == .standard)
        for line in VoicePack.Line.allCases {
            #expect(pack.line(line) == (custom[line] ?? VoicePack.gentle.line(line)))
        }
    }

    @Test("Setting a line validates it, and clearing it returns to the pack's words")
    func settingLines() {
        let long = String(repeating: "x", count: 200)
        var lines = VoiceCustomLines().setting(.lastMinute, to: long)
        #expect(lines[.lastMinute]?.count == VoiceCustomLines.maximumLength)
        lines = lines.setting(.lastMinute, to: "   ")
        #expect(lines[.lastMinute] == nil)
        lines = lines.setting(.lastMinute, to: "Done.").setting(.lastMinute, to: nil)
        #expect(lines.isEmpty)
        #expect(VoiceCustomLines.normalized("a\nb") == "a b")
        #expect(VoiceCustomLines.normalized(" \t ") == nil)
    }
}
