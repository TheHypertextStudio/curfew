import CurfewKit
import SwiftUI

// MARK: - Patterns

/// "What the days say": three cards, each with its small chart.
struct JournalPatternsView: View {
    let patterns: JournalPatternsPresentation
    let format: JournalFormat

    @State private var width: CGFloat = 900

    var body: some View {
        let layout = width >= 3 * 220 + 24
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        layout {
            cards
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }

    @ViewBuilder
    private var cards: some View {
        card(patterns.weekday) {
            if !patterns.weekdayRows.allSatisfy({ $0.median == nil }) {
                JournalWeekdayChart(rows: patterns.weekdayRows, format: format)
            }
        }
        card(patterns.readiness) {
            if patterns.readyRate != nil || patterns.otherRate != nil {
                JournalReadinessChart(
                    readyRate: patterns.readyRate,
                    otherRate: patterns.otherRate,
                    format: format
                )
            }
        }
        card(patterns.endings) {
            if let counts = patterns.endingCounts {
                JournalEndingsChart(counts: counts)
            }
        }
    }

    private func card(
        _ card: JournalPatternCard,
        @ViewBuilder chart: () -> some View
    ) -> some View {
        JournalCard {
            Text(card.sentence)
                .journalFont(.statement)
                .foregroundStyle(JournalStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
            chart()
            Spacer(minLength: 0)
            Text(card.note)
                .journalFont(.caption)
                .foregroundStyle(JournalStyle.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(minWidth: 220)
        .accessibilityElement(children: .combine)
    }
}

/// Typical stop by weekday, earlier to the left of curfew and later to the
/// right. Only the weekday that stands out takes a colour.
private struct JournalWeekdayChart: View {
    let rows: [JournalPatternsPresentation.WeekdayRow]
    let format: JournalFormat

    private let rowHeight: CGFloat = 22
    private let labelWidth: CGFloat = 36

    var body: some View {
        let reach = max(30, rows.compactMap(\.median).map(abs).max() ?? 30)
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { proxy in
                let plot = proxy.size.width - labelWidth - 8
                let mid = labelWidth + 8 + plot / 2
                let half = plot / 2 - 34
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(JournalStyle.ink.opacity(0.5))
                        .frame(width: 1, height: rowHeight * CGFloat(rows.count))
                        .offset(x: mid - 0.5)
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        rowView(
                            row,
                            rowY: CGFloat(index) * rowHeight,
                            mid: mid,
                            half: half,
                            reach: reach
                        )
                    }
                }
            }
            .frame(height: rowHeight * CGFloat(rows.count))
            HStack {
                Text("Earlier")
                Spacer()
                Text("Curfew")
                Spacer()
                Text("Later")
            }
            .padding(.leading, labelWidth + 8)
            .journalFont(.axis)
            .foregroundStyle(JournalStyle.soft)
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func rowView(
        _ row: JournalPatternsPresentation.WeekdayRow,
        rowY: CGFloat,
        mid: CGFloat,
        half: CGFloat,
        reach: Int
    ) -> some View {
        let median = row.median ?? 0
        let length = CGFloat(abs(median)) / CGFloat(reach) * half
        let color = row.isHighlighted ? JournalStyle.color(JournalMark(offset: median))
            : JournalStyle.atCurfew
        Text(row.label)
            .journalFont(row.isHighlighted ? .axisStrong : .axis)
            .foregroundStyle(row.isHighlighted ? JournalStyle.ink : JournalStyle.soft)
            .frame(width: labelWidth, height: rowHeight, alignment: .trailing)
            .offset(y: rowY)
        if row.median != nil {
            if median == 0 {
                Capsule()
                    .fill(color)
                    .frame(width: 3, height: 10)
                    .offset(x: mid - 1.5, y: rowY + 6)
            } else {
                UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
                    topLeading: median < 0 ? 4 : 0,
                    bottomLeading: median < 0 ? 4 : 0,
                    bottomTrailing: median > 0 ? 4 : 0,
                    topTrailing: median > 0 ? 4 : 0
                ), style: .continuous)
                    .fill(color)
                    .frame(width: max(2, length), height: 10)
                    .offset(x: median < 0 ? mid - length : mid, y: rowY + 6)
            }
            if row.isHighlighted {
                Text(format.relativeShort(median))
                    .journalFont(.axisStrong)
                    .foregroundStyle(JournalStyle.ink)
                    .fixedSize()
                    .frame(
                        width: 80,
                        height: rowHeight,
                        alignment: median < 0 ? .trailing : .leading
                    )
                    .offset(x: median < 0 ? mid - length - 86 : mid + length + 6, y: rowY)
            }
        }
    }
}

/// The one thing done rate on ready mornings against the rest.
private struct JournalReadinessChart: View {
    let readyRate: Double?
    let otherRate: Double?
    let format: JournalFormat

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 10) {
            row("Felt ready", readyRate)
            row("Less ready", otherRate)
        }
        .accessibilityHidden(true)
    }

    private func row(_ label: String, _ rate: Double?) -> some View {
        GridRow {
            Text(label)
                .journalFont(.small)
                .foregroundStyle(JournalStyle.soft)
                .gridColumnAlignment(.trailing)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(JournalStyle.early1.opacity(0.4))
                    if let rate {
                        Capsule()
                            .fill(JournalStyle.early)
                            .frame(width: max(12, proxy.size.width * rate))
                    }
                }
            }
            .frame(height: 12)
            Text(rate.map(format.percent) ?? "None")
                .journalFont(.axisStrong)
                .foregroundStyle(JournalStyle.ink)
                .monospacedDigit()
                .frame(minWidth: 34, alignment: .leading)
        }
    }
}

/// How days ended, as one bar split three ways.
private struct JournalEndingsChart: View {
    let counts: DayEndingsFinding

    private struct Part {
        let days: Int
        let fill: Color
        let label: Color
        let name: String
    }

    private var parts: [Part] {
        [
            Part(
                days: counts.stoppedBeforeCurfew, fill: JournalStyle.early,
                label: JournalStyle.onEarly, name: "You called it a day"
            ),
            Part(
                days: counts.endedByLock, fill: JournalStyle.atCurfew,
                label: JournalStyle.onAtCurfew, name: "The lock ended it"
            ),
            Part(
                days: counts.ranOver, fill: JournalStyle.over,
                label: JournalStyle.onOver, name: "Ran over"
            )
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                let shown = parts.filter { $0.days > 0 }
                let spacing = CGFloat(max(0, shown.count - 1)) * 2
                let unit = (proxy.size.width - spacing) / CGFloat(max(1, counts.days))
                HStack(spacing: 2) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, part in
                        let share = Double(part.days) / Double(max(1, counts.days))
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4, style: .continuous).fill(part.fill)
                            if share > 0.1 {
                                Text("\(part.days)")
                                    .journalFont(.button)
                                    .foregroundStyle(part.label)
                                    .padding(.leading, 8)
                            }
                        }
                        .frame(width: unit * CGFloat(part.days))
                    }
                }
            }
            .frame(height: 28)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { legend }
                VStack(alignment: .leading, spacing: 4) { legend }
            }
            .journalFont(.caption)
            .foregroundStyle(JournalStyle.soft)
        }
        .accessibilityHidden(true)
    }

    private var legend: some View {
        ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
            HStack(spacing: 6) {
                JournalSwatch(color: part.fill)
                Text(part.name)
            }
            .fixedSize()
        }
    }
}
