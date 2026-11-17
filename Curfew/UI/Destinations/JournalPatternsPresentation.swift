import CurfewKit
import Foundation

/// A pattern card's sentence and the line under it.
struct JournalPatternCard: Equatable {
    let sentence: String
    /// How many days it rests on, or why there is nothing to report.
    let note: String
    let isEarned: Bool
}

/// "What the days say": the three pattern cards and their small charts.
struct JournalPatternsPresentation: Equatable {
    struct WeekdayRow: Equatable, Identifiable {
        let weekday: Weekday
        let label: String
        /// Median signed stop minutes; `nil` without a stop that weekday.
        let median: Int?
        let isHighlighted: Bool

        var id: Weekday {
            weekday
        }
    }

    let basis: String
    let weekday: JournalPatternCard
    let weekdayRows: [WeekdayRow]
    let readiness: JournalPatternCard
    let readyRate: Double?
    let otherRate: Double?
    let endings: JournalPatternCard
    let endingCounts: DayEndingsFinding?

    init(
        records: [JournalDayRecord],
        period: JournalPeriod,
        today: Date,
        workingWeekdays: Set<Weekday>,
        format: JournalFormat
    ) {
        let calendar = format.calendar
        let window = JournalPatterns.window(for: period, calendar: calendar)
        let windowRecords = records.filter { $0.day >= window.start && $0.day < window.end }
        let span = period.range == .year
            ? "all of \(format.periodLabel(period, workingWeekdays: workingWeekdays))"
            : "the 12 weeks to \(format.lastDayLabel(period, today: today))"
        self.basis = "From \(span), \(JournalFormat.count(windowRecords.count, "working day"))."

        let weekdayPattern = JournalPatterns.weekday(windowRecords, calendar: calendar)
        let highlighted: Weekday? = if case .earned(let finding) = weekdayPattern.verdict {
            finding.weekday
        } else {
            nil
        }
        self.weekday = Self.weekdayCard(weekdayPattern.verdict, format: format)
        let ordered = (0 ..< 7).compactMap { offset in
            Weekday(rawValue: (calendar.firstWeekday - 1 + offset) % 7 + 1)
        }
        self.weekdayRows = ordered
            .filter { workingWeekdays.contains($0) || weekdayPattern.medians[$0] != nil }
            .map { day in
                WeekdayRow(
                    weekday: day, label: format.weekdayShort(day),
                    median: weekdayPattern.medians[day], isHighlighted: day == highlighted
                )
            }

        let readinessPattern = JournalPatterns.readiness(windowRecords)
        self.readyRate = readinessPattern.readyRate
        self.otherRate = readinessPattern.otherRate
        self.readiness = Self.readinessCard(readinessPattern, format: format)

        let endingsVerdict = JournalPatterns.dayEndings(windowRecords).verdict
        if case .earned(let finding) = endingsVerdict {
            self.endingCounts = finding
        } else {
            self.endingCounts = nil
        }
        self.endings = Self.endingsCard(endingsVerdict)
    }

    private static func weekdayCard(
        _ verdict: JournalPatternVerdict<WeekdayFinding>,
        format: JournalFormat
    ) -> JournalPatternCard {
        switch verdict {
        case .earned(let finding):
            JournalPatternCard(
                sentence: "\(format.weekdayPlural(finding.weekday)) run about "
                    + "\(format.duration(finding.minutesLater)) later than your other days.",
                note: "From \(finding.days) \(format.weekdayPlural(finding.weekday)).",
                isEarned: true
            )
        case .notEarned(let shortfall):
            JournalPatternCard(
                sentence: "No weekday stands out yet.",
                note: weekdayNote(shortfall),
                isEarned: false
            )
        }
    }

    private static func readinessCard(
        _ pattern: ReadinessPattern,
        format: JournalFormat
    ) -> JournalPatternCard {
        switch pattern.verdict {
        case .earned(let finding):
            JournalPatternCard(
                sentence: "You did the one thing on \(format.percent(finding.readyRate)) of "
                    + "mornings you felt ready, and \(format.percent(finding.otherRate)) "
                    + "of the rest.",
                note: "From \(JournalFormat.count(finding.readyMornings, "ready morning")) and "
                    + "\(JournalFormat.count(finding.otherMornings, "other")).",
                isEarned: true
            )
        case .notEarned(.gapTooSmall):
            JournalPatternCard(
                sentence: "Feeling ready has not changed whether you did the one thing.",
                note: "From "
                    + JournalFormat.count(pattern.readyMornings + pattern.otherMornings, "morning")
                    + ".",
                isEarned: false
            )
        case .notEarned(.tooFewDays(let have, _)):
            JournalPatternCard(
                sentence: "Nothing to report yet.",
                note: "Needs five mornings of each kind. The fewer kind has \(have).",
                isEarned: false
            )
        case .notEarned:
            JournalPatternCard(
                sentence: "Nothing to report yet.",
                note: "Needs mornings with both a readiness rating and a one thing answer.",
                isEarned: false
            )
        }
    }

    private static func endingsCard(
        _ verdict: JournalPatternVerdict<DayEndingsFinding>
    ) -> JournalPatternCard {
        switch verdict {
        case .earned(let finding):
            JournalPatternCard(
                sentence: JournalCountWords.endings(
                    early: finding.stoppedBeforeCurfew,
                    lock: finding.endedByLock,
                    over: finding.ranOver
                ),
                note: "From \(JournalFormat.count(finding.days, "day")) with a stop time.",
                isEarned: true
            )
        case .notEarned:
            JournalPatternCard(
                sentence: "Nothing to report yet.",
                note: "No stop times were recorded in these weeks.",
                isEarned: false
            )
        }
    }

    private static func weekdayNote(_ shortfall: JournalPatternShortfall) -> String {
        switch shortfall {
        case .noDays:
            "No stop times were recorded in these weeks."
        case .nothingToCompare:
            "Needs more than one weekday to compare."
        case .tooFewDays(let have, _):
            "Needs four of a weekday to compare. The latest has \(have) so far."
        case .gapTooSmall:
            "No weekday runs ten minutes later than the rest."
        }
    }
}
