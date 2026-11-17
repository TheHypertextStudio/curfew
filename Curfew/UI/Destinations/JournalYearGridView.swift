import CurfewKit
import SwiftUI

/// Year range: every working day as a cell on the seven-step scale, one
/// column per week. Arrow keys move through the grid as it reads: left and
/// right by week, up and down by weekday.
struct JournalYearGridView: View {
    let days: [JournalDay]
    let grid: JournalYearGrid
    let yearLabel: String

    @State private var active: Int?
    @State private var tipSize: CGSize = .zero
    @State private var width: CGFloat = 720
    @FocusState private var isFocused: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    private let gap: CGFloat = 3
    private let top: CGFloat = 22

    init(
        days: [JournalDay],
        grid: JournalYearGrid,
        yearLabel: String,
        initiallyActive: Date? = nil
    ) {
        self.days = days
        self.grid = grid
        self.yearLabel = yearLabel
        _active = State(initialValue: initiallyActive.flatMap { day in
            days.firstIndex { $0.day == day }
        })
    }

    private var leading: CGFloat {
        36 * JournalFont.scale(for: typeSize)
    }

    private func cellSize(width: CGFloat) -> CGFloat {
        let columns = CGFloat(max(1, grid.columns))
        return max(4, min(16, ((width - leading - 2) / columns).rounded(.down) - gap))
    }

    var body: some View {
        GeometryReader { proxy in
            let cell = cellSize(width: proxy.size.width)
            ZStack(alignment: .topLeading) {
                labels(cell: cell)
                ForEach(grid.cells, id: \.dayIndex) { placement in
                    let day = days[placement.dayIndex]
                    let isActive = active == placement.dayIndex
                    RoundedRectangle(cornerRadius: min(3, cell / 3), style: .continuous)
                        .fill(JournalStyle.color(day.heatBin))
                        .overlay {
                            if isActive {
                                RoundedRectangle(cornerRadius: min(3, cell / 3), style: .continuous)
                                    .strokeBorder(
                                        isFocused ? JournalStyle.accent : JournalStyle.ink,
                                        lineWidth: 2
                                    )
                                    .padding(-1)
                            }
                        }
                        .frame(width: cell, height: cell)
                        .padding(gap / 2)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside {
                                active = placement.dayIndex
                            } else if active == placement.dayIndex, !isFocused {
                                active = nil
                            }
                        }
                        .offset(
                            x: x(placement.column, cell: cell) - gap / 2,
                            y: y(placement.row, cell: cell) - gap / 2
                        )
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(day.accessibilityLabel)
                        .accessibilityAddTraits(isActive ? .isSelected : [])
                }
                if let active, let placement = grid.cells.first(where: { $0.dayIndex == active }) {
                    tooltip(for: placement, cell: cell, width: proxy.size.width)
                }
            }
        }
        .frame(height: height(cell: cellSize(width: width)))
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .focusable()
        .focused($isFocused)
        .focusEffectDisabled()
        .onChange(of: isFocused) { _, focused in
            if focused, active == nil {
                active = days.indices.last
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
        .accessibilityLabel(
            "Every working day of \(yearLabel) by how far before or after curfew you stopped"
        )
    }

    private func height(cell: CGFloat) -> CGFloat {
        top + CGFloat(grid.rows.count) * (cell + gap) + 2
    }

    private func x(_ column: Int, cell: CGFloat) -> CGFloat {
        leading + CGFloat(column) * (cell + gap)
    }

    private func y(_ row: Int, cell: CGFloat) -> CGFloat {
        top + CGFloat(row) * (cell + gap)
    }

    private func labels(cell: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(grid.months, id: \.column) { month in
                Text(month.label)
                    .journalFont(.axis)
                    .foregroundStyle(JournalStyle.soft)
                    .fixedSize()
                    .offset(x: x(month.column, cell: cell), y: 0)
            }
            ForEach(Array(grid.rows.enumerated()), id: \.offset) { index, row in
                if row.showsLabel {
                    Text(row.label)
                        .journalFont(.axis)
                        .foregroundStyle(JournalStyle.soft)
                        .lineLimit(1)
                        .frame(width: leading - 8, height: cell, alignment: .trailing)
                        .offset(y: y(index, cell: cell))
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func tooltip(for placement: JournalYearGrid.Cell, cell: CGFloat, width: CGFloat)
        -> some View {
        let centre = x(placement.column, cell: cell) + cell / 2
        let tipX = min(max(0, centre - tipSize.width / 2), max(0, width - tipSize.width))
        let cellTop = y(placement.row, cell: cell)
        let above = cellTop - tipSize.height - 8
        let tipY = above >= -top ? above : cellTop + cell + 8
        return JournalTooltipView(tooltip: days[placement.dayIndex].tooltip)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { tipSize = $0 }
            .offset(x: tipX, y: tipY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .zIndex(2)
    }

    private func move(_ direction: MoveCommandDirection) {
        guard !grid.cells.isEmpty else { return }
        let current = grid.cells.first { $0.dayIndex == active } ?? grid.cells[grid.cells.count - 1]
        let lookup = Dictionary(
            grid.cells.map { (JournalGridPoint(column: $0.column, row: $0.row), $0.dayIndex) },
            uniquingKeysWith: { first, _ in first }
        )
        let step: (column: Int, row: Int) = switch direction {
        case .left: (-1, 0)
        case .right: (1, 0)
        case .up: (0, -1)
        case .down: (0, 1)
        @unknown default: (0, 0)
        }
        var column = current.column + step.column
        var row = current.row + step.row
        while column >= 0, column < grid.columns, row >= 0, row < grid.rows.count {
            if let index = lookup[JournalGridPoint(column: column, row: row)] {
                active = index
                return
            }
            column += step.column
            row += step.row
            if step == (0, 0) {
                return
            }
        }
    }
}

private struct JournalGridPoint: Hashable {
    let column: Int
    let row: Int
}
