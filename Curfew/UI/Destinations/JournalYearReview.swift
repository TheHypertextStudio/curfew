import CoreGraphics
import CurfewAtmosphere
import CurfewKit
import Foundation

/// The year in review card at the end of the Journal's year range: the
/// year's working days as marks on the curfew line over the sky, and four
/// totals. Worked out from the year's day records so the views only draw it.
///
/// The card never carries the person's written words: no one thing text, no
/// answers, no override reasons. Only counts, times and the marks.
struct JournalYearReview: Equatable, Sendable {
    /// Working days with a stop time the card needs before it says anything.
    /// Four working weeks: below that the marks are a handful of strokes and
    /// "longest run" or "typical stop" read as noise.
    static let minimumDays = 20

    /// One total: a figure over a few plain words.
    struct Total: Equatable, Hashable, Sendable {
        let value: String
        let label: String
        /// The total as a sentence, for VoiceOver.
        let spoken: String
    }

    /// What the card shows once the year has enough days.
    struct Card: Equatable, Sendable {
        /// "2026", or "2026 so far" while the year is still running.
        let yearLabel: String
        /// "127 evenings ended before curfew."
        let headline: String
        let totals: [Total]
        let marks: [JournalYearMark]
        /// The marks in words, for VoiceOver.
        let marksSummary: String
        /// The default name for the saved image.
        let fileName: String

        /// Everything the card says, in reading order, for VoiceOver.
        var accessibilityValue: String {
            ([headline] + totals.map(\.spoken) + [marksSummary]).joined(separator: " ")
        }
    }

    enum Content: Equatable, Sendable {
        /// Too few days for the card to mean anything: one dry line, no export.
        case tooFewDays(String)
        case card(Card)
    }

    let year: Int
    let content: Content

    /// The card for the year `period` covers, from that year's records.
    /// `today` decides whether the year is finished.
    init(records: [JournalDayRecord], period: JournalPeriod, today: Date, format: JournalFormat) {
        let calendar = format.calendar
        let sorted = records.sorted { $0.day < $1.day }
        let summary = JournalSummary(records: sorted)
        let totals = JournalYearInReview(records: sorted, calendar: calendar)
        self.year = calendar.component(.year, from: period.interval.start)
        let isFinished = calendar.startOfDay(for: today) >= period.interval.end

        guard summary.daysWithStop >= Self.minimumDays,
              let minute = totals.typicalStopMinuteOfDay,
              let typical = calendar.date(
                  byAdding: .minute,
                  value: minute,
                  to: period.interval.start
              )
        else {
            self.content = .tooFewDays(Self.tooFewDaysLine(have: summary.daysWithStop))
            return
        }

        let early = totals.daysStoppedBeforeCurfew
        let clock = format.clock(typical)
        let oneThing = JournalFormat.count(totals.oneThingDays, "day")
        let extra = format.duration(totals.extraMinutes)
        let run = JournalFormat.count(totals.longestRunBeforeCurfew, "day")
        let marks = JournalYearMark.marks(offsets: sorted.compactMap(\.stopOffsetMinutes))
        self.content = .card(Card(
            yearLabel: isFinished ? "\(year)" : "\(year) so far",
            headline: Self.headline(early: early),
            totals: [
                Total(value: clock, label: "typical stop", spoken: "Typical stop \(clock)."),
                Total(
                    value: oneThing, label: "you did the one thing",
                    spoken: "You did the one thing on \(oneThing)."
                ),
                Total(
                    value: extra,
                    label: isFinished ? "extra time, all year" : "extra time so far",
                    spoken: isFinished ? "\(extra) extra time all year." : "\(extra) extra time so far."
                ),
                Total(
                    value: run, label: "longest run stopping early",
                    spoken: "Longest run stopping early: \(run)."
                )
            ],
            marks: marks,
            marksSummary: Self.marksSummary(marks),
            fileName: Self.fileName(year: year)
        ))
    }

    // MARK: - Words

    /// "A year in review needs 20 working days. This year has 6."
    static func tooFewDaysLine(have: Int) -> String {
        "A year in review needs \(minimumDays) working days. This year has \(have)."
    }

    /// "127 evenings ended before curfew."
    static func headline(early: Int) -> String {
        switch early {
        case 0: "No evening ended before curfew."
        case 1: "1 evening ended before curfew."
        default: "\(early) evenings ended before curfew."
        }
    }

    /// "Each working day is a mark on the curfew line: 127 rise above it for
    /// stopping early, 52 sit on it where the lock ended the day, 40 drop
    /// below it for running over."
    static func marksSummary(_ marks: [JournalYearMark]) -> String {
        let early = marks.count { $0.kind == .early }
        let lock = marks.count { $0.kind == .atCurfew }
        let over = marks.count { $0.kind == .over }
        let clauses = [
            early > 0 ? "\(early) rise above it for stopping early" : nil,
            lock > 0 ? "\(lock) sit on it where the lock ended the day" : nil,
            over > 0 ? "\(over) drop below it for running over" : nil
        ].compactMap(\.self)
        return "Each working day is a mark on the curfew line: "
            + clauses.joined(separator: ", ") + "."
    }

    /// "curfew-year-in-review-2026.png".
    static func fileName(year: Int) -> String {
        "curfew-year-in-review-\(year).png"
    }

    // MARK: - Export

    /// The exported image's size in points. One size, always, so every
    /// shared card looks the same.
    static let exportSize = CGSize(width: 1600, height: 1000)
    /// Pixels per point in the exported image.
    static let exportScale: CGFloat = 2
    /// Width over height, shared by the card on screen and the image.
    static let aspectRatio = exportSize.width / exportSize.height

    /// The sky behind the card: the sun just under the line at the right, the
    /// last light of the day. Fixed, so the card looks the same whenever and
    /// wherever it is opened.
    static let skyFrame = HorizonFrame(
        sun: HorizonPoint(x: 0.86, y: 0.2),
        sunWeight: 1,
        moon: HorizonPoint(x: 0.5, y: -1),
        moonWeight: 0,
        elevation: 0.02,
        moonPhase: 0
    )
    /// How much the sky is dimmed under the words, as in the prototype.
    static let skyDimming = 0.18
}

/// One working day on the year in review's curfew line. Up for stopping
/// early, down for running over, a short neutral tick across the line when
/// the lock ended the day.
struct JournalYearMark: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case early
        case atCurfew
        case over
    }

    let kind: Kind
    /// Horizontal centre as a fraction of the card's width.
    let centerX: Double
    /// Top and bottom of the stroke as fractions of the card's height, from
    /// the top.
    let top: Double
    let bottom: Double

    // MARK: - Layout, in fractions of the card

    /// Where the line starts and ends across the card.
    static let lineStart = 0.05
    static let lineEnd = 0.95
    /// The curfew line sits on the sky's horizon.
    static let lineY = 1 - HorizonGeometry.horizon
    /// Stroke length per minute from curfew, as a fraction of the height.
    /// Early and over share one scale.
    static let lengthPerMinute = 0.0021
    /// Longest early stroke, in minutes. Earlier days draw at this length so
    /// marks stay clear of the headline.
    static let earliestMinutes = 90
    /// Longest over stroke, in minutes. Later days draw at this length so
    /// marks stay clear of the totals below the line.
    static let latestMinutes = 45
    /// Half the length of the neutral tick, as a fraction of the height.
    static let tickHalfLength = 0.012
    /// Stroke width as a share of each day's slot.
    static let strokeShare = 0.55

    /// One mark per offset, in day order, spaced evenly along the line.
    static func marks(offsets: [Int]) -> [JournalYearMark] {
        let slot = (lineEnd - lineStart) / Double(max(offsets.count, 1))
        return offsets.enumerated().map { index, offset in
            let centerX = lineStart + (Double(index) + 0.5) * slot
            if offset < 0 {
                let length = Double(min(-offset, earliestMinutes)) * lengthPerMinute
                return JournalYearMark(
                    kind: .early,
                    centerX: centerX,
                    top: lineY - length,
                    bottom: lineY
                )
            } else if offset > 0 {
                let length = Double(min(offset, latestMinutes)) * lengthPerMinute
                return JournalYearMark(
                    kind: .over,
                    centerX: centerX,
                    top: lineY,
                    bottom: lineY + length
                )
            }
            return JournalYearMark(
                kind: .atCurfew, centerX: centerX, top: lineY - tickHalfLength,
                bottom: lineY + tickHalfLength
            )
        }
    }

    /// Stroke width in points for `count` marks on a card `width` wide.
    static func strokeWidth(count: Int, width: Double) -> Double {
        let slot = (lineEnd - lineStart) * width / Double(max(count, 1))
        return max(1, slot * strokeShare)
    }
}
