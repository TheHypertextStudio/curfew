import AppKit
import CoreGraphics
import CurfewKit
import Foundation

/// The year time card at the head of the Journal's year range: one headline
/// over the sky, the year punched into the card stock, and a footer. Worked
/// out from the year's day records so the views only draw it.
///
/// The card never carries the person's written words: no one thing text, no
/// answers, no override reasons. Only counts, times and holes.
struct JournalYearReview: Equatable, Sendable {
    /// Working days with a stop time the card needs before it says anything.
    /// Four working weeks: below that the punches are a handful of holes and
    /// "usual time" or "longest run" read as noise.
    static let minimumDays = 20

    /// One headline: a big value, an optional small unit set beside it, and
    /// the plain line under the sky that completes it.
    struct Headline: Equatable, Hashable, Sendable {
        let value: String
        /// The day period of a 12-hour time, set small after the value.
        let unit: String?
        let line: String
        /// The headline as a sentence, for VoiceOver.
        let spoken: String
    }

    /// What the card shows once the year has enough days.
    struct Card: Equatable, Sendable {
        let year: Int
        /// "2026", or "2026 so far" while the year is still running.
        let yearLabel: String
        /// "212 working days".
        let workingDaysLabel: String
        /// "40 ended by the lock".
        let lockLabel: String
        let calendar: JournalTimeCardCalendar
        let skyline: JournalTimeCardSkyline
        /// The default name for the saved image.
        let fileName: String
        let headlines: [JournalTimeCardHeadline: Headline]

        func headline(_ kind: JournalTimeCardHeadline) -> Headline {
            headlines[kind] ?? Headline(value: "", unit: nil, line: "", spoken: "")
        }

        /// Everything the card in `style` says, in reading order, for VoiceOver.
        func spokenSummary(_ style: JournalTimeCardStyle) -> String {
            let punches = switch style.punches {
            case .calendar:
                "Each evening out before curfew is a hole punched in its place in the year."
            case .skyline:
                "Each evening you stopped yourself is a hole, stacked by how early or late it "
                    + "was." + (skyline.spokenPeak.map { " Most were \($0)." } ?? "")
            }
            return "Curfew time card for \(yearLabel). \(headline(style.headline).spoken) "
                + "\(workingDaysLabel), \(lockLabel). \(punches)"
        }
    }

    enum Content: Equatable, Sendable {
        /// Too few days for the card to mean anything: one dry line, no export.
        case tooFewDays(String)
        case card(Card)
    }

    let year: Int
    let content: Content

    /// Where the time card sits on the year page.
    enum Placement: Equatable, Sendable {
        /// First, under the page's headline and above the tiles: the card
        /// is the year's shareable object.
        case leading
        /// After every other section.
        case trailing
    }

    var placement: Placement {
        switch content {
        case .card: .leading
        // One line leading the page reads as a fault; it waits at the end.
        case .tooFewDays: .trailing
        }
    }

    /// The card for the year `period` covers, from that year's records.
    /// `today` decides whether the year is finished; `workingWeekdays` lays
    /// out the calendar punches.
    init(
        records: [JournalDayRecord],
        period: JournalPeriod,
        today: Date,
        workingWeekdays: Set<Weekday>,
        format: JournalFormat
    ) {
        let calendar = format.calendar
        let sorted = records.sorted { $0.day < $1.day }
        let summary = JournalSummary(records: sorted)
        let totals = JournalYearInReview(records: sorted, calendar: calendar)
        let year = calendar.component(.year, from: period.interval.start)
        self.year = year
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

        let lock = sorted.count { $0.ending?.cause == .lock }
        self.content = .card(Card(
            year: year,
            yearLabel: isFinished ? "\(year)" : "\(year) so far",
            workingDaysLabel: JournalFormat.count(summary.daysWithStop, "working day"),
            lockLabel: "\(lock) ended by the lock",
            calendar: JournalTimeCardCalendar(
                year: year, records: sorted, workingWeekdays: workingWeekdays, format: format
            ),
            skyline: JournalTimeCardSkyline(records: sorted, format: format),
            fileName: Self.fileName(year: year),
            headlines: [
                .eveningsOut: Self.eveningsOut(totals.daysStoppedBeforeCurfew),
                .usualTime: Self.usualTime(format.clock(typical), isFinished: isFinished),
                .longestRun: Self.longestRun(totals.longestRunBeforeCurfew)
            ]
        ))
    }

    // MARK: - Words

    /// "A time card needs 20 working days. This year has 6."
    static func tooFewDaysLine(have: Int) -> String {
        "A time card needs \(minimumDays) working days. This year has \(have)."
    }

    static func eveningsOut(_ count: Int) -> Headline {
        let line = count == 1 ? "evening out before curfew" : "evenings out before curfew"
        return Headline(value: "\(count)", unit: nil, line: line, spoken: "\(count) \(line).")
    }

    /// "5:45" with "PM" set small, or "17:45" alone.
    static func usualTime(_ clock: String, isFinished: Bool) -> Headline {
        let line = isFinished ? "was your usual time out" : "is your usual time out"
        let parts = clock.split(separator: " ", maxSplits: 1).map(String.init)
        let hasPeriod = parts.count == 2 && !parts[1].contains { $0.isNumber }
        return Headline(
            value: hasPeriod ? parts[0] : clock,
            unit: hasPeriod ? parts[1] : nil,
            line: line,
            spoken: "\(clock) \(line)."
        )
    }

    /// "14" over "in a row out before curfew": short enough for one line.
    static func longestRun(_ count: Int) -> Headline {
        Headline(
            value: "\(count)", unit: nil, line: "in a row out before curfew",
            spoken: "Longest run: \(JournalFormat.count(count, "evening")) in a row out before curfew."
        )
    }

    /// "curfew-time-card-2026.png".
    static func fileName(year: Int) -> String {
        "curfew-time-card-\(year).png"
    }

    // MARK: - Export

    /// The exported image's size in points: the card on its stage at 4:5.
    /// One size, always, so every shared card looks the same.
    static let exportSize = CGSize(width: 800, height: 1000)
    /// Pixels per point in the exported image.
    static let exportScale: CGFloat = 2
    /// The card's width in the exported image, leaving an even margin of
    /// stage around it.
    static let exportCardWidth: CGFloat = 560
}

/// Puts the time card's PNG on a pasteboard.
enum JournalYearReviewPasteboard {
    /// Replaces `pasteboard`'s contents with the image. Returns whether the
    /// pasteboard took it.
    @discardableResult
    static func write(png: Data, to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setData(png, forType: .png)
    }
}
