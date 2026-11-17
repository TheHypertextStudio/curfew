import CurfewKit
import SwiftUI

/// "When you stopped": one column per working day around the curfew line,
/// early up and over down, with the one thing and readiness in two rows
/// beneath that share each column's slot.
///
/// Built from SwiftUI shapes rather than Swift Charts because each day's
/// column and its two row marks are one hover, focus and VoiceOver target,
/// and month range separates weeks with gaps that are layout, not data.
struct JournalStopChart: View {
    let days: [JournalDay]
    let scale: JournalChartScale
    let range: JournalRange
    let format: JournalFormat

    @State private var active: Date?
    @State private var tipSize: CGSize = .zero
    @FocusState private var isFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    init(
        days: [JournalDay],
        scale: JournalChartScale,
        range: JournalRange,
        format: JournalFormat,
        initiallyActive: Date? = nil
    ) {
        self.days = days
        self.scale = scale
        self.range = range
        self.format = format
        _active = State(initialValue: initiallyActive)
    }

    private var textScale: CGFloat {
        JournalFont.scale(for: typeSize)
    }

    private var layout: JournalStopChartLayout {
        JournalStopChartLayout(textScale: textScale)
    }

    var body: some View {
        let layout = layout
        GeometryReader { proxy in
            let slots = layout.slots(for: days, width: proxy.size.width, range: range)
            ZStack(alignment: .topLeading) {
                gridlines(layout: layout, width: proxy.size.width)
                rowLabels(layout: layout)
                ForEach(slots) { slot in
                    JournalChartSlot(
                        day: slot.day,
                        layout: layout,
                        scale: scale,
                        width: slot.width,
                        barWidth: slot.barWidth,
                        showsAxisLabel: slot.showsAxisLabel,
                        isActive: active == slot.day.id,
                        isFocused: isFocused && active == slot.day.id
                    )
                    .offset(x: slot.originX)
                    .onHover { inside in
                        if inside {
                            active = slot.day.id
                        } else if active == slot.day.id, !isFocused {
                            active = nil
                        }
                    }
                }
                if let slot = slots.first(where: { $0.day.id == active }) {
                    tooltip(for: slot, layout: layout, width: proxy.size.width)
                }
            }
        }
        .frame(height: layout.height)
        .contentShape(Rectangle())
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onChange(of: isFocused) { _, focused in
            if focused, active == nil {
                active = days.last(where: { $0.kind == .stopped })?.id ?? days.last?.id
            } else if !focused {
                active = nil
            }
        }
        .onMoveCommand { direction in
            move(direction)
        }
        .onKeyPress(.escape) {
            active = nil
            return .handled
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("When you stopped each day, against curfew")
    }

    private func move(_ direction: MoveCommandDirection) {
        guard !days.isEmpty else { return }
        let index = days.firstIndex { $0.id == active } ?? days.count - 1
        switch direction {
        case .left: active = days[max(0, index - 1)].id
        case .right: active = days[min(days.count - 1, index + 1)].id
        default: break
        }
    }

    private func gridlines(layout: JournalStopChartLayout, width: CGFloat) -> some View {
        ForEach(scale.ticks, id: \.self) { value in
            let isCurfew = value == 0
            let lineY = layout.y(value, scale: scale)
            Rectangle()
                .fill(isCurfew ? JournalStyle.ink.opacity(0.5) : JournalStyle.grid)
                .frame(width: max(0, width - layout.leading - layout.trailing), height: 1)
                .offset(x: layout.leading, y: lineY - 0.5)
            Text(format.tickLabel(value))
                .journalFont(isCurfew ? .axisStrong : .axis)
                .foregroundStyle(isCurfew ? JournalStyle.ink : JournalStyle.soft)
                .lineLimit(1)
                .frame(width: layout.leading - 10, height: 20, alignment: .trailing)
                .offset(y: lineY - 10)
        }
        .accessibilityHidden(true)
    }

    private func rowLabels(layout: JournalStopChartLayout) -> some View {
        ForEach(
            [("One thing", layout.oneThingY), ("Felt ready", layout.readinessY)],
            id: \.0
        ) { row in
            Text(row.0)
                .journalFont(.axis)
                .foregroundStyle(JournalStyle.soft)
                .lineLimit(1)
                .frame(width: layout.leading - 10, height: 20, alignment: .trailing)
                .offset(y: row.1 - 10)
        }
        .accessibilityHidden(true)
    }

    private func tooltip(
        for slot: JournalStopChartLayout.Slot,
        layout: JournalStopChartLayout,
        width: CGFloat
    ) -> some View {
        let anchor = layout.markBounds(for: slot.day, scale: scale)
        let centre = slot.originX + slot.width / 2
        let tipX = min(max(0, centre - tipSize.width / 2), max(0, width - tipSize.width))
        let above = anchor.top - tipSize.height - 10
        let tipY = above >= -layout.top ? above : anchor.bottom + 10
        return JournalTooltipView(tooltip: slot.day.tooltip)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { tipSize = $0 }
            .offset(x: tipX, y: tipY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .zIndex(2)
    }
}

/// Geometry shared by the chart and its tests of alignment: every vertical
/// position and the horizontal slot for each day.
struct JournalStopChartLayout {
    struct Slot: Identifiable {
        let day: JournalDay
        let originX: CGFloat
        let width: CGFloat
        let barWidth: CGFloat
        let showsAxisLabel: Bool

        var id: Date {
            day.id
        }
    }

    let textScale: CGFloat
    var top: CGFloat {
        20
    }

    var plotHeight: CGFloat {
        200
    }

    var leading: CGFloat {
        92 * textScale
    }

    var trailing: CGFloat {
        8
    }

    var axisHeight: CGFloat {
        26 * textScale
    }

    var rowHeight: CGFloat {
        22 * textScale
    }

    var axisLabelY: CGFloat {
        top + plotHeight + axisHeight / 2
    }

    var oneThingY: CGFloat {
        top + plotHeight + axisHeight + rowHeight / 2
    }

    var readinessY: CGFloat {
        oneThingY + rowHeight
    }

    var height: CGFloat {
        top + plotHeight + axisHeight + rowHeight * 2 + 8
    }

    /// Top of a slot's hover fill, a little above the plot.
    var slotTop: CGFloat {
        top - 12
    }

    var slotHeight: CGFloat {
        height - slotTop
    }

    func y(_ value: Int, scale: JournalChartScale) -> CGFloat {
        top + CGFloat(scale.position(value)) * plotHeight
    }

    /// Month range leaves a gap before each new week.
    func slots(for days: [JournalDay], width: CGFloat, range: JournalRange) -> [Slot] {
        guard !days.isEmpty else { return [] }
        let gap: CGFloat = range == .month ? 12 : 0
        let gaps = CGFloat(days.dropFirst().count(where: \.startsWeek))
        let available = max(0, width - leading - trailing - gap * gaps)
        let slotWidth = available / CGFloat(days.count)
        let barWidth = min(24, max(5, slotWidth * 0.56))
        let labelEvery = slotWidth < 22 * textScale
        var cursor = leading
        return days.enumerated().map { index, day in
            if index > 0, day.startsWeek {
                cursor += gap
            }
            defer { cursor += slotWidth }
            return Slot(
                day: day, originX: cursor, width: slotWidth, barWidth: barWidth,
                showsAxisLabel: !labelEvery || day.startsWeek
            )
        }
    }

    /// The vertical extent of a day's data mark, for placing the tooltip.
    func markBounds(
        for day: JournalDay,
        scale: JournalChartScale
    ) -> (top: CGFloat, bottom: CGFloat) {
        let baseline = y(0, scale: scale)
        guard let offset = day.offset, offset != 0 else { return (baseline - 4, baseline + 4) }
        let end = y(-offset, scale: scale)
        return (min(end, baseline), max(end, baseline))
    }
}

/// One day's column, labels and row marks inside its slot.
private struct JournalChartSlot: View {
    let day: JournalDay
    let layout: JournalStopChartLayout
    let scale: JournalChartScale
    let width: CGFloat
    let barWidth: CGFloat
    let showsAxisLabel: Bool
    let isActive: Bool
    let isFocused: Bool

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? JournalStyle.chip : .clear)
                .overlay {
                    if isFocused {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(JournalStyle.accent, lineWidth: 2)
                    }
                }
                .frame(width: width, height: layout.slotHeight)
                .offset(y: layout.slotTop)
            column
            extremeLabel
            if showsAxisLabel {
                Text(day.axisLabel)
                    .journalFont(.axis)
                    .foregroundStyle(JournalStyle.soft)
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: width, height: 20)
                    .offset(y: layout.axisLabelY - 10)
            }
            oneThingMark
            readinessMark
        }
        .frame(width: width, height: layout.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(day.accessibilityLabel)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    @ViewBuilder
    private var column: some View {
        let baseline = layout.y(0, scale: scale)
        switch (day.kind, day.offset) {
        case (.stopped, 0?):
            let markWidth = max(barWidth, 10)
            Capsule()
                .fill(JournalStyle.atCurfew)
                .frame(width: markWidth, height: 3)
                .offset(x: (width - markWidth) / 2, y: baseline - 1.5)
        case (.stopped, let offset?):
            let end = layout.y(-offset, scale: scale)
            let isEarly = offset < 0
            JournalColumnShape(roundsTop: isEarly)
                .fill(JournalStyle.color(JournalMark(offset: offset)))
                .frame(width: barWidth, height: max(2, abs(end - baseline)))
                .offset(x: (width - barWidth) / 2, y: isEarly ? end : baseline)
        case (.noStopTime, _):
            Circle()
                .strokeBorder(JournalStyle.faint, style: StrokeStyle(lineWidth: 1.5, dash: [2, 2]))
                .frame(width: 9, height: 9)
                .offset(x: (width - 9) / 2, y: baseline - 4.5)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var extremeLabel: some View {
        if let label = day.extremeLabel, let offset = day.offset {
            let end = layout.y(-offset, scale: scale)
            Text(label)
                .journalFont(.axisStrong)
                .foregroundStyle(JournalStyle.ink)
                .lineLimit(1)
                .fixedSize()
                .frame(width: width, height: 16)
                .offset(y: offset < 0 ? end - 6 - 16 : end + 4)
        }
    }

    @ViewBuilder
    private var oneThingMark: some View {
        if let done = day.record?.oneThingDone {
            Group {
                if done {
                    Circle().fill(JournalStyle.ink)
                } else {
                    Circle().strokeBorder(JournalStyle.faint, lineWidth: 1.5)
                }
            }
            .frame(width: 8, height: 8)
            .offset(x: (width - 8) / 2, y: layout.oneThingY - 4)
        }
    }

    @ViewBuilder
    private var readinessMark: some View {
        if let readiness = day.record?.readiness {
            let height = max(1.5, CGFloat(readiness.fivePoint) * 2.4)
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(JournalStyle.atCurfew)
                .frame(width: 6, height: height)
                .offset(x: (width - 6) / 2, y: layout.readinessY + 6 - height)
        }
    }
}
