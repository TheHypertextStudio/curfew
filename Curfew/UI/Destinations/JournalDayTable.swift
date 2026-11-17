import CurfewKit
import SwiftUI

/// "Every day": the table twin of the charts. Each row is a button that
/// opens that evening's timeline and what was written; rows are reachable
/// with the keyboard and read as full sentences.
struct JournalDayTable: View {
    let rows: [JournalRow]
    let collapsedRowLimit: Int?
    let showAllTitle: String?

    @Binding var expanded: Set<Date>
    @Binding var showsAll: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private var visibleRows: ArraySlice<JournalRow> {
        if let collapsedRowLimit, !showsAll {
            return rows.prefix(collapsedRowLimit)
        }
        return rows[...]
    }

    private var columns: JournalTableColumns {
        JournalTableColumns(scale: JournalFont.scale(for: typeSize))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 0) {
                header
                ForEach(visibleRows) { row in
                    JournalDayRowView(
                        row: row,
                        columns: columns,
                        isExpanded: expanded.contains(row.day)
                    ) {
                        toggle(row.day)
                    }
                }
            }
            if let showAllTitle {
                Button(showsAll ? "Show the latest 12" : showAllTitle) {
                    withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
                        showsAll.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: JournalStyle.controlRadius))
                .journalFont(.button)
            }
        }
    }

    private func toggle(_ day: Date) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) {
            if expanded.contains(day) {
                expanded.remove(day)
            } else {
                expanded.insert(day)
            }
        }
    }

    private var header: some View {
        HStack(spacing: columns.spacing) {
            Text("Day").frame(width: columns.day, alignment: .leading)
            Text("Today was for").frame(maxWidth: .infinity, alignment: .leading)
            Text("Stopped").frame(width: columns.stopped, alignment: .leading)
            Text("Against curfew").frame(width: columns.against, alignment: .leading)
            Text("Ready").frame(width: columns.ready, alignment: .leading)
            Color.clear.frame(width: columns.chevron, height: 1)
        }
        .journalFont(.caption)
        .foregroundStyle(JournalStyle.soft)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle().fill(JournalStyle.line).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}

/// Fixed widths for the numeric columns; the one thing takes the rest.
struct JournalTableColumns {
    let scale: CGFloat
    var spacing: CGFloat {
        16
    }

    var day: CGFloat {
        96 * scale
    }

    var stopped: CGFloat {
        68 * scale
    }

    var against: CGFloat {
        104 + 8 + 96 * scale
    }

    var ready: CGFloat {
        44 * scale
    }

    var chevron: CGFloat {
        14
    }
}

private struct JournalDayRowView: View {
    let row: JournalRow
    let columns: JournalTableColumns
    let isExpanded: Bool
    let toggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            Button(action: toggle) {
                cells
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .contentShape(Rectangle())
                    .background(isHovered || isExpanded ? JournalStyle.chip : .clear)
            }
            .buttonStyle(JournalRowButtonStyle())
            .onHover { isHovered = $0 }
            .accessibilityLabel(row.accessibilityLabel)
            .accessibilityValue(isExpanded ? "Open" : "Closed")
            .accessibilityHint(isExpanded ? "Closes this evening" : "Opens this evening")

            if isExpanded {
                JournalDayDetail(row: row)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(JournalStyle.chip)
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(JournalStyle.line).frame(height: 1)
        }
    }

    private var cells: some View {
        HStack(alignment: .center, spacing: columns.spacing) {
            Text(row.dayLabel)
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: columns.day, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let done = row.done {
                    Image(systemName: done ? "checkmark.circle" : "circle")
                        .foregroundStyle(JournalStyle.soft)
                        .accessibilityLabel(done ? "Done" : "Not done")
                }
                Text(row.thing ?? "Nothing named")
                    .foregroundStyle(row.thing == nil ? JournalStyle.soft : JournalStyle.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(row.stopped ?? "")
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: columns.stopped, alignment: .leading)
            HStack(spacing: 8) {
                JournalOffsetBar(offset: row.offset)
                    .frame(width: 104, height: 12)
                Text(row.against)
                    .monospacedDigit()
                    .lineLimit(1)
                    .foregroundStyle(row.offset == nil ? JournalStyle.soft : JournalStyle.ink)
            }
            .frame(width: columns.against, alignment: .leading)
            Text(row.ready ?? "")
                .monospacedDigit()
                .lineLimit(1)
                .frame(width: columns.ready, alignment: .leading)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(JournalStyle.soft)
                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                .frame(width: columns.chevron)
        }
        .journalFont(.row)
        .foregroundStyle(JournalStyle.ink)
    }
}

/// Keeps the row flat and only darkens it a touch while pressed.
private struct JournalRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.85 : 1)
    }
}

/// The small curfew-centred bar in the table: early to the left, over to
/// the right, a short neutral tick at curfew.
struct JournalOffsetBar: View {
    let offset: Int?

    var body: some View {
        GeometryReader { proxy in
            let mid = proxy.size.width / 2
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(JournalStyle.ink.opacity(0.5))
                    .frame(width: 1, height: proxy.size.height)
                    .offset(x: mid - 0.5)
                if let offset {
                    if offset == 0 {
                        Capsule()
                            .fill(JournalStyle.atCurfew)
                            .frame(width: 3, height: 10)
                            .offset(x: mid - 1.5, y: 1)
                    } else {
                        let length = max(4, min(mid - 2, CGFloat(abs(offset)) / 90 * (mid - 2)))
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .fill(JournalStyle.color(JournalMark(offset: offset)))
                            .frame(width: length, height: 8)
                            .offset(x: offset < 0 ? mid - length : mid, y: 2)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// An opened row: the evening on a line, and what was written.
private struct JournalDayDetail: View {
    let row: JournalRow

    @State private var width: CGFloat = 800

    var body: some View {
        let isWide = width >= 640
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 28))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        layout {
            if let offset = row.offset, let curfew = row.curfewLabel, let stop = row.stopLabel,
               let curfewTime = row.scheduledCurfew {
                JournalEveningTimeline(
                    offset: offset,
                    curfewLabel: curfew,
                    stopLabel: stop,
                    curfew: curfewTime
                )
                .frame(maxWidth: isWide ? width * 0.5 : .infinity)
                .frame(height: 78)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(Array(row.details.enumerated()), id: \.offset) { _, detail in
                    GridRow {
                        Text(detail.term)
                            .foregroundStyle(JournalStyle.soft)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(width: 150, alignment: .leading)
                        Text(detail.value)
                            .foregroundStyle(JournalStyle.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .journalFont(.row)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .accessibilityElement(children: .combine)
    }
}

/// The evening from two hours before curfew to the stop: the working line
/// in blue, any time over in ember, curfew as a vertical rule.
private struct JournalEveningTimeline: View {
    let offset: Int
    let curfewLabel: String
    let stopLabel: String
    let curfew: Date

    @Environment(\.calendar) private var calendar

    var body: some View {
        GeometryReader { proxy in
            let first = min(-120, offset - 10)
            let last = max(75, offset + 15)
            let span = CGFloat(last - first)
            let place: (Int) -> CGFloat = { minute in
                16 + CGFloat(minute - first) / span * (proxy.size.width - 32)
            }
            let lineY: CGFloat = 40
            ZStack(alignment: .topLeading) {
                Rectangle().fill(JournalStyle.grid)
                    .frame(width: place(last) - place(first), height: 1)
                    .offset(x: place(first), y: lineY - 0.5)
                Capsule().fill(JournalStyle.early)
                    .frame(width: max(0, place(min(offset, 0)) - place(first)), height: 2)
                    .offset(x: place(first), y: lineY - 1)
                if offset > 0 {
                    Capsule().fill(JournalStyle.over)
                        .frame(width: place(offset) - place(0), height: 2)
                        .offset(x: place(0), y: lineY - 1)
                }
                Rectangle().fill(JournalStyle.ink.opacity(0.5))
                    .frame(width: 1, height: 30)
                    .offset(x: place(0) - 0.5, y: 22)
                Text(curfewLabel)
                    .journalFont(.axisStrong)
                    .foregroundStyle(JournalStyle.ink)
                    .fixedSize()
                    .offset(x: place(0) + 6, y: 12)
                Text(startLabel(minutesBefore: -first))
                    .journalFont(.axis)
                    .foregroundStyle(JournalStyle.soft)
                    .fixedSize()
                    .offset(x: place(first), y: 50)
                Circle()
                    .fill(JournalStyle.color(JournalMark(offset: offset)))
                    .overlay(Circle().strokeBorder(JournalStyle.chip, lineWidth: 2))
                    .frame(width: 14, height: 14)
                    .offset(x: place(offset) - 7, y: lineY - 7)
                Text(stopLabel)
                    .journalFont(.axisStrong)
                    .foregroundStyle(JournalStyle.ink)
                    .fixedSize()
                    .frame(width: 140, alignment: alignment(place(offset), width: proxy.size.width))
                    .offset(x: labelX(place(offset), width: proxy.size.width), y: 52)
            }
        }
        .accessibilityHidden(true)
    }

    private func startLabel(minutesBefore: Int) -> String {
        let start = curfew.addingTimeInterval(-TimeInterval(minutesBefore) * 60)
        return JournalFormat(calendar: calendar).clock(start)
    }

    private func alignment(_ point: CGFloat, width: CGFloat) -> Alignment {
        point > width - 70 ? .trailing : point < 70 ? .leading : .center
    }

    private func labelX(_ point: CGFloat, width: CGFloat) -> CGFloat {
        point > width - 70 ? point - 140 + 7 : point < 70 ? point - 7 : point - 70
    }
}
