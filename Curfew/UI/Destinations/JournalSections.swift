import CurfewKit
import Foundation

/// One of the four summary tiles.
struct JournalTile: Identifiable, Equatable {
    enum Kind: CaseIterable {
        case stoppedBeforeCurfew
        case oneThing
        case extraTime
        case readiness

        var metric: JournalMetric {
            switch self {
            case .stoppedBeforeCurfew: .stoppedBeforeCurfewRate
            case .oneThing: .oneThingRate
            case .extraTime: .extraMinutes
            case .readiness: .readinessAverage
            }
        }

        var title: String {
            switch self {
            case .stoppedBeforeCurfew: "Stopped before curfew"
            case .oneThing: "Did the one thing"
            case .extraTime: "Extra time taken"
            case .readiness: "Felt ready in the morning"
            }
        }
    }

    let kind: Kind
    let value: String
    let qualifier: String
    /// "Up from 48% in September"; `nil` in year range or without a
    /// previous period to compare with.
    let comparison: String?
    /// The trailing values for the trend line, oldest first.
    let trend: [Double]

    var id: Kind {
        kind
    }

    var title: String {
        kind.title
    }

    var accessibilityLabel: String {
        let qualifier = qualifier.isEmpty ? "" : ", \(qualifier)"
        let comparison = comparison.map { ". \($0)" } ?? ""
        return "\(title): \(value)\(qualifier)\(comparison)."
    }

    /// "Up from 48% in September", "Down from 3.4 the week before", or
    /// "Same as the week before" when both read the same once formatted.
    static func comparison(
        current: Double?,
        previous: Double?,
        range: JournalRange,
        previousName: String?,
        format: (Double) -> String
    ) -> String? {
        guard range != .year, let current, let previous, let previousName else { return nil }
        if format(current) == format(previous) {
            return "Same as \(previousName)"
        }
        let direction = current > previous ? "Up from" : "Down from"
        let joiner = range == .week ? " " : " in "
        return "\(direction) \(format(previous))\(joiner)\(previousName)"
    }

    static func tiles(
        summary: JournalSummary,
        previous: JournalSummary?,
        period: JournalPeriod,
        records: [JournalDayRecord],
        format: JournalFormat
    ) -> [JournalTile] {
        let previousName = format.previousName(period)
        return Kind.allCases.map { kind in
            let valueFormat: (Double) -> String = switch kind {
            case .stoppedBeforeCurfew, .oneThing: format.percent
            case .extraTime: { $0 == 0 ? "none" : format.duration(Int($0)) }
            case .readiness: format.decimal
            }
            let current = kind.metric.value(in: summary)
            let value: String
            let qualifier: String
            switch kind {
            case .stoppedBeforeCurfew:
                value = current.map(format.percent) ?? "None yet"
                qualifier = summary.daysWithStop == 0 ? "" : "\(summary.stoppedBeforeCurfew) of "
                    + JournalFormat.count(summary.daysWithStop, "day")
            case .oneThing:
                value = current.map(format.percent) ?? "None yet"
                qualifier = summary.oneThingAnswered == 0 ? "Not answered" : "\(summary.oneThingDone) of "
                    + JournalFormat.count(summary.oneThingAnswered, "day")
            case .extraTime:
                value = summary.extraMinutes > 0 ? format.duration(summary.extraMinutes) : "None"
                qualifier = summary.ranOver > 0 ? JournalFormat.count(summary.ranOver, "night") : ""
            case .readiness:
                value = current.map(format.decimal) ?? "None yet"
                qualifier = current == nil ? "" : "out of 5"
            }
            let trend = JournalTrend.points(
                kind.metric, endingAt: period, records: records, calendar: format.calendar
            )
            .map(\.value)
            return JournalTile(
                kind: kind,
                value: value,
                qualifier: qualifier,
                comparison: comparison(
                    current: current,
                    previous: previous.flatMap(kind.metric.value(in:)),
                    range: period.range,
                    previousName: previousName,
                    format: valueFormat
                ),
                trend: trend
            )
        }
    }
}

/// "Extra time, in your words".
struct JournalWords: Equatable {
    struct Override: Identifiable, Equatable {
        let id: Date
        let title: String
        let reasons: [String]
    }

    let overrides: [Override]
    /// Shown in place of the list when there were no overrides.
    let emptyLine: String?
    let closingTitle: String
    let closingLine: String

    init(records: [JournalDayRecord], format: JournalFormat) {
        self.overrides = records
            .filter { $0.overrideCount > 0 }
            .sorted { $0.day > $1.day }
            .map { record in
                let minutes = format.duration(record.overrideMinutes)
                let what = record.overrideCount == 1 ? "\(minutes) override"
                    : "\(record.overrideCount) overrides, \(minutes)"
                return Override(
                    id: record.day,
                    title: "\(format.shortDay(record.day)) · \(what)",
                    reasons: record.overrideReasons
                )
            }
        self.emptyLine = overrides.isEmpty ? "You did not ask to get back in after the lock." : nil
        let times = records.reduce(0) { $0 + $1.extensionCount }
        let minutes = records.reduce(0) { $0 + $1.extensionMinutes }
        if times > 0 {
            self.closingTitle = times == 1 ? "More time, once" : "More time, \(times) times"
            self.closingLine = "\(format.duration(minutes)) in all. More time does not ask for a reason."
        } else {
            self.closingTitle = "No more time"
            self.closingLine = "You did not ask for more minutes before the lock."
        }
    }
}

/// A term and its value in an opened day.
struct JournalDetail: Hashable {
    let term: String
    let value: String
}

/// One row of "Every day", the accessible twin of the charts.
struct JournalRow: Identifiable, Equatable {
    let day: Date
    let dayLabel: String
    let thing: String?
    let done: Bool?
    let stopped: String?
    let offset: Int?
    let against: String
    let ready: String?
    let scheduledCurfew: Date?
    let curfewLabel: String?
    let stopLabel: String?
    let details: [JournalDetail]
    let accessibilityLabel: String

    var id: Date {
        day
    }

    init(record: JournalDayRecord, morningExtras: [ReflectionAnswer], format: JournalFormat) {
        self.day = record.day
        self.dayLabel = format.shortDay(record.day)
        self.thing = record.oneThing
        self.done = record.oneThingDone
        self.offset = record.stopOffsetMinutes
        self.stopped = record.stoppedAt.map(format.clock)
        self.against = record.stopOffsetMinutes.map(format.relativeShort) ?? "No record"
        self.ready = record.readiness.map { "\($0.value) of \($0.scale)" }
        self.scheduledCurfew = record.scheduledCurfew
        self.curfewLabel = record.scheduledCurfew.map { "Curfew \(format.clock($0))" }
        if let offset = record.stopOffsetMinutes, let stopped {
            self.stopLabel = (offset >= 0 ? "Locked " : "Stopped ") + stopped
        } else {
            self.stopLabel = nil
        }

        var details: [JournalDetail] = []
        if let how = JournalDayWords.howItEnded(record), let offset = record.stopOffsetMinutes {
            let minutes = offset > 0 ? ", \(format.duration(offset))" : ""
            details.append(JournalDetail(term: "How it ended", value: how + minutes))
        } else {
            details.append(JournalDetail(term: "How it ended", value: "No stop time recorded"))
        }
        for reason in record.overrideReasons {
            details.append(JournalDetail(term: "Your reason", value: "“\(reason)”"))
        }
        for answer in morningExtras + record.eveningAnswers {
            details.append(JournalDetail(
                term: answer.promptTextSnapshot,
                value: Self.answerText(answer.value)
            ))
        }
        self.details = details
        self.accessibilityLabel = JournalDayWords.sentence(
            day: record.day,
            record: record,
            format: format
        )
    }

    static func answerText(_ value: ReflectionValue) -> String {
        switch value {
        case .rating(let value, let scale): "\(value) of \(scale)"
        default: reflectionValueText(value)
        }
    }

    /// Morning answers the record does not already carry (anything other
    /// than the one thing and readiness), by working day.
    static func morningExtras(_ reflections: [Reflection], calendar: Calendar)
        -> [Date: [ReflectionAnswer]] {
        let journal = JournalCalendar(calendar: calendar)
        var extras: [Date: [ReflectionAnswer]] = [:]
        for reflection in reflections where reflection.gate == .morning {
            let answers = reflection.answers.filter {
                $0.promptID != JournalPromptIDs.oneThing && $0.promptID != JournalPromptIDs
                    .readiness
            }
            guard !answers.isEmpty else { continue }
            extras[journal.workingDay(forMorning: reflection.timestamp), default: []] += answers
        }
        return extras
    }
}
