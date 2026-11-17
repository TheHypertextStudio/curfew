import CurfewKit
import Foundation

/// Everything the Journal shows for one period, worked out from day records
/// so the views only lay it out. Every count comes from CurfewKit's
/// ``JournalSummary``, ``JournalPatterns`` and ``JournalTrend``; this type
/// only words and arranges them.
struct JournalScreen {
    enum State: Equatable {
        /// Nothing has been recorded yet: the first days after install.
        case noHistory
        /// The shown period has no recorded working days.
        case noWorkingDays
        /// The period's days were recorded before stop times existed.
        case noStopTimes
        case populated
    }

    let period: JournalPeriod
    let state: State
    let label: String
    let headline: String
    let summary: JournalSummary
    let tiles: [JournalTile]
    let chartTitle: String
    let chartSubtitle: String?
    let scale: JournalChartScale
    let days: [JournalDay]
    let yearGrid: JournalYearGrid?
    let patterns: JournalPatternsPresentation
    let words: JournalWords
    let rows: [JournalRow]
    /// Year range shows the latest twelve rows until asked for the rest.
    let collapsedRowLimit: Int?
    let showAllTitle: String?
    let canGoBack: Bool
    let canGoForward: Bool

    static let firstDaysTitle = "Your Journal fills in as the days end."
    static let firstDaysLine = "Each evening Curfew notes when you stopped and whether you did "
        + "the one thing you named that morning. Your first day appears here after tonight."

    // swiftlint:disable:next function_body_length
    init(
        records allRecords: [JournalDayRecord],
        reflections: [Reflection] = [],
        period: JournalPeriod,
        today: Date,
        workingWeekdays: Set<Weekday>,
        format: JournalFormat
    ) {
        let calendar = format.calendar
        let todayStart = calendar.startOfDay(for: today)
        let records = allRecords
            .filter { $0.day < todayStart || ($0.day <= today && $0.ending != nil) }
            .sorted { $0.day < $1.day }
        let periodRecords = period.records(from: records)
        let summary = JournalSummary(records: periodRecords)
        self.period = period
        self.summary = summary
        self.label = format.periodLabel(
            period,
            workingWeekdays: workingWeekdays,
            recordedDays: periodRecords.map(\.day)
        )

        if records.isEmpty {
            self.state = .noHistory
        } else if periodRecords.isEmpty {
            self.state = .noWorkingDays
        } else if summary.daysWithStop == 0 {
            self.state = .noStopTimes
        } else {
            self.state = .populated
        }

        switch state {
        case .noHistory:
            self.headline = Self.firstDaysTitle
        case .noWorkingDays where period.interval.contains(today):
            self.headline = "Nothing recorded yet \(JournalFormat.periodNoun(period.range))."
        case .noWorkingDays:
            self.headline = "No working days were recorded in \(JournalFormat.periodNoun(period.range))."
        case .noStopTimes:
            self.headline = "These days were recorded before Curfew noted stop times."
        case .populated:
            self.headline = JournalCountWords.headline(
                early: summary.stoppedBeforeCurfew,
                lock: summary.endedByLock,
                over: summary.ranOver
            )
        }

        let previous = period.previous(calendar: calendar)
        let previousSummary = previous.summary(of: records)
        self.tiles = JournalTile.tiles(
            summary: summary,
            previous: previousSummary.days > 0 ? previousSummary : nil,
            period: period,
            records: records,
            format: format
        )

        self.chartTitle = period.range == .year ? "Every working day" : "When you stopped"
        if let median = summary.medianStopOffsetMinutes,
           let minute = JournalYearInReview(records: periodRecords, calendar: calendar)
               .typicalStopMinuteOfDay,
           let typical = calendar
               .date(byAdding: .minute, value: minute, to: period.interval.start) {
            self.chartSubtitle = "Typical stop \(format.clock(typical)), \(format.relative(median))."
        } else {
            self.chartSubtitle = nil
        }
        self.scale = JournalChartScale(offsets: periodRecords.compactMap(\.stopOffsetMinutes))

        let days = Self.days(
            periodRecords: periodRecords,
            firstRecordDay: records.first.map { calendar.startOfDay(for: $0.day) },
            context: DayContext(
                period: period,
                todayStart: todayStart,
                workingWeekdays: workingWeekdays,
                format: format
            )
        )
        self.days = days
        self.yearGrid = period.range == .year
            ? JournalYearGrid(
                days: days,
                period: period,
                workingWeekdays: workingWeekdays,
                format: format
            )
            : nil

        self.patterns = JournalPatternsPresentation(
            records: records,
            period: period,
            today: today,
            workingWeekdays: workingWeekdays,
            format: format
        )
        self.words = JournalWords(records: periodRecords, format: format)

        let extras = JournalRow.morningExtras(reflections, calendar: calendar)
        self.rows = periodRecords.reversed().map { record in
            JournalRow(record: record, morningExtras: extras[record.day] ?? [], format: format)
        }
        if period.range == .year, rows.count > 12 {
            self.collapsedRowLimit = 12
            self.showAllTitle = "Show all \(rows.count) days"
        } else {
            self.collapsedRowLimit = period.range == .year ? 12 : nil
            self.showAllTitle = nil
        }

        self.canGoBack = records.contains { $0.day < period.interval.start }
        self.canGoForward = period.next(calendar: calendar).interval.start <= todayStart
    }

    // MARK: - Days

    /// What the day columns need to know about the shown period.
    private struct DayContext {
        let period: JournalPeriod
        let todayStart: Date
        let workingWeekdays: Set<Weekday>
        let format: JournalFormat
    }

    /// The period's working days from the first recorded day to yesterday,
    /// plus today once it has ended, plus any recorded day the schedule now
    /// treats as off.
    private static func shownDays(
        byDay: [Date: JournalDayRecord],
        firstRecordDay: Date,
        context: DayContext
    ) -> [Date] {
        let calendar = context.format.calendar
        var result: [Date] = []
        var day = max(context.period.interval.start, firstRecordDay)
        while day < context.period.interval.end, day <= context.todayStart {
            defer {
                day = calendar.date(byAdding: .day, value: 1, to: day)
                    ?? context.period.interval.end
            }
            let record = byDay[day]
            let isWorking = Weekday(rawValue: calendar.component(.weekday, from: day))
                .map(context.workingWeekdays.contains) ?? false
            let isPast = day < context.todayStart
            if record?.ending != nil || (isPast && (record != nil || isWorking)) {
                result.append(day)
            }
        }
        return result
    }

    private static func days(
        periodRecords: [JournalDayRecord],
        firstRecordDay: Date?,
        context: DayContext
    ) -> [JournalDay] {
        let format = context.format
        let calendar = format.calendar
        guard let firstRecordDay else { return [] }
        var byDay: [Date: JournalDayRecord] = [:]
        for record in periodRecords {
            byDay[calendar.startOfDay(for: record.day)] = record
        }
        let offsets = periodRecords.compactMap(\.stopOffsetMinutes)
        var earliest = offsets.filter { $0 < 0 }.min()
        var latest = offsets.filter { $0 > 0 }.max()
        var previousWeek: Date?
        return shownDays(byDay: byDay, firstRecordDay: firstRecordDay, context: context)
            .map { day in
                let record = byDay[day]
                let week = calendar.dateInterval(of: .weekOfYear, for: day)?.start
                defer { previousWeek = week }
                let offset = record?.stopOffsetMinutes
                var extreme: String?
                if let offset, let stoppedAt = record?.stoppedAt,
                   offset == earliest || offset == latest {
                    // Only the first day at each extreme is labelled.
                    if offset == earliest {
                        earliest = nil
                    } else {
                        latest = nil
                    }
                    extreme = format.clock(stoppedAt)
                }
                return JournalDay(
                    day: day,
                    kind: record == nil ? .nothingRecorded : offset == nil ? .noStopTime : .stopped,
                    record: record,
                    offset: offset,
                    startsWeek: week != previousWeek,
                    axisLabel: context.period.range == .week
                        ? "\(format.weekdayShort(day)) \(format.dayNumber(day))"
                        : format.dayNumber(day),
                    extremeLabel: extreme,
                    accessibilityLabel: JournalDayWords.sentence(
                        day: day, record: record, format: format
                    ),
                    tooltip: JournalDayWords.tooltip(day: day, record: record, format: format)
                )
            }
    }
}

/// Sentences about one day, shared by the chart, the grid and the table.
enum JournalDayWords {
    /// "You called it a day", "The lock ended it", "More time", "Override".
    static func howItEnded(_ record: JournalDayRecord) -> String? {
        guard let offset = record.stopOffsetMinutes, let ending = record.ending else { return nil }
        if offset > 0 {
            return record.overrideCount > 0 ? "Override" : "More time"
        }
        return ending.cause == .calledItADay ? "You called it a day" : "The lock ended it"
    }

    /// "Did the one thing: Ship it." or "Today was for: Ship it."
    static func oneThing(_ record: JournalDayRecord) -> String? {
        switch (record.oneThingDone, record.oneThing) {
        case (true?, let thing?): "Did the one thing: \(thing)"
        case (false?, let thing?): "Did not do the one thing: \(thing)"
        case (nil, let thing?): "Today was for: \(thing)"
        case (true?, nil): "Did the one thing"
        case (false?, nil): "Did not do the one thing"
        case (nil, nil): nil
        }
    }

    static func readiness(_ record: JournalDayRecord) -> String? {
        record.readiness.map { "Felt ready \($0.value) of \($0.scale)" }
    }

    /// The full sentence VoiceOver reads for a day.
    static func sentence(day: Date, record: JournalDayRecord?, format: JournalFormat) -> String {
        var parts = [format.shortDay(day)]
        guard let record else {
            return (parts + ["Nothing recorded"]).joined(separator: ". ") + "."
        }
        if let offset = record.stopOffsetMinutes, let stoppedAt = record.stoppedAt {
            parts.append("Stopped \(format.clock(stoppedAt)), \(format.relative(offset))")
            if let how = howItEnded(record) {
                parts.append(how)
            }
        } else {
            parts.append("No stop time recorded")
        }
        parts += [oneThing(record), readiness(record)].compactMap(\.self)
        return parts.joined(separator: ". ") + "."
    }

    static func tooltip(day: Date, record: JournalDayRecord?, format: JournalFormat)
        -> JournalTooltip {
        let date = format.shortDay(day)
        guard let record else {
            return JournalTooltip(
                date: date, headline: "Nothing recorded", mark: nil, markText: nil,
                lines: [], footnote: nil
            )
        }
        let footnote = readiness(record)
        let lines = [oneThingShort(record)].compactMap(\.self)
        guard let offset = record.stopOffsetMinutes, let stoppedAt = record.stoppedAt else {
            return JournalTooltip(
                date: date, headline: "No stop time recorded", mark: nil, markText: nil,
                lines: lines, footnote: footnote
            )
        }
        let how = howItEnded(record).map { " · " + $0.lowercased() } ?? ""
        return JournalTooltip(
            date: date,
            headline: "Stopped \(format.clock(stoppedAt))",
            mark: JournalMark(offset: offset),
            markText: format.relativeShort(offset) + how,
            lines: lines,
            footnote: footnote
        )
    }

    /// The tooltip's shorter one thing line: "Did: Ship it."
    private static func oneThingShort(_ record: JournalDayRecord) -> String? {
        guard let thing = record.oneThing else { return nil }
        switch record.oneThingDone {
        case true?: return "Did: \(thing)"
        case false?: return "Did not do: \(thing)"
        case nil: return "Today was for: \(thing)"
        }
    }
}
