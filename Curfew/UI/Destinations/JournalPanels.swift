import CurfewKit
import SwiftUI

// MARK: - Tiles

/// The four summary tiles.
struct JournalTilesView: View {
    let tiles: [JournalTile]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 170), spacing: 12, alignment: .top)],
            alignment: .leading,
            spacing: 12
        ) {
            ForEach(tiles) { tile in
                JournalTileView(tile: tile)
            }
        }
    }
}

private struct JournalTileView: View {
    let tile: JournalTile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tile.title)
                .journalFont(.row)
                .foregroundStyle(JournalStyle.soft)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
            HStack(alignment: .center, spacing: 8) {
                Text(tile.value)
                    .journalFont(.figure)
                    .foregroundStyle(JournalStyle.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
                if tile.trend.count > 2 {
                    JournalSparkline(values: tile.trend)
                        .frame(width: 64, height: 22)
                }
            }
            .padding(.top, 2)
            Text(tile.qualifier.isEmpty ? " " : tile.qualifier)
                .journalFont(.caption)
                .foregroundStyle(JournalStyle.soft)
                .lineLimit(1)
            if let comparison = tile.comparison {
                Text(comparison)
                    .journalFont(.caption)
                    .foregroundStyle(JournalStyle.soft)
                    .lineLimit(2, reservesSpace: true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            JournalStyle.chip,
            in: RoundedRectangle(cornerRadius: JournalStyle.panelRadius, style: .continuous)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tile.accessibilityLabel)
    }
}

/// A tile's trend line: a neutral line with the current period marked in
/// ember.
struct JournalSparkline: View {
    let values: [Double]

    var body: some View {
        GeometryReader { proxy in
            let points = points(in: proxy.size)
            ZStack(alignment: .topLeading) {
                Path { path in
                    path.addLines(points)
                }
                .stroke(
                    JournalStyle.atCurfew,
                    style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
                )
                if let last = points.last {
                    Circle()
                        .fill(JournalStyle.accent)
                        .overlay(Circle().strokeBorder(JournalStyle.chip, lineWidth: 2))
                        .frame(width: 9, height: 9)
                        .offset(x: last.x - 4.5, y: last.y - 4.5)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard let low = values.min(), let high = values.max() else { return [] }
        let span = high - low == 0 ? 1 : high - low
        let step = (size.width - 8) / CGFloat(max(1, values.count - 1))
        return values.enumerated().map { index, value in
            CGPoint(
                x: 3 + CGFloat(index) * step,
                y: size.height - 4 - CGFloat((value - low) / span) * (size.height - 8)
            )
        }
    }
}

// MARK: - Legend

/// The key above the chart.
struct JournalLegend: View {
    let range: JournalRange
    let showsNoStopTime: Bool

    var body: some View {
        HStack(spacing: 14) {
            if range == .year {
                HStack(spacing: 3) {
                    Text("Earlier")
                        .padding(.trailing, 3)
                    ForEach(Array(JournalHeatBin.scale.enumerated()), id: \.offset) { _, bin in
                        JournalSwatch(color: JournalStyle.color(bin))
                    }
                    Text("Later")
                        .padding(.leading, 3)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Colour runs from earlier, in blue, to later, in ember")
                item(JournalSwatch(color: JournalStyle.chip), "No stop time")
            } else {
                item(JournalSwatch(color: JournalStyle.early), "Before curfew")
                item(JournalSwatch(color: JournalStyle.atCurfew, isLine: true), "At curfew")
                item(JournalSwatch(color: JournalStyle.over), "Over")
                item(
                    HStack(spacing: 4) {
                        Circle().fill(JournalStyle.ink).frame(width: 8, height: 8)
                        Circle().strokeBorder(JournalStyle.faint, lineWidth: 1.5)
                            .frame(width: 8, height: 8)
                    },
                    "Did it, didn’t"
                )
                if showsNoStopTime {
                    item(
                        Circle()
                            .strokeBorder(
                                JournalStyle.faint,
                                style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])
                            )
                            .frame(width: 9, height: 9),
                        "No stop time"
                    )
                }
            }
        }
        .journalFont(.caption)
        .foregroundStyle(JournalStyle.soft)
    }

    private func item(_ mark: some View, _ text: String) -> some View {
        HStack(spacing: 6) {
            mark
            Text(text)
        }
        .fixedSize()
    }
}

// MARK: - Words

/// "Extra time, in your words": each override's reason, newest first, and
/// a closing line about more time.
struct JournalWordsView: View {
    let words: JournalWords

    @State private var width: CGFloat = 900

    private var isWide: Bool {
        width >= 180 + 20 + 260
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Color.clear.frame(height: 0)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            if let empty = words.emptyLine {
                row(key: Text("No overrides"), mark: false) {
                    Text(empty)
                }
            }
            ForEach(words.overrides) { override in
                row(key: Text(override.title), mark: true) {
                    if override.reasons.isEmpty {
                        Text("No reason was recorded.")
                            .foregroundStyle(JournalStyle.soft)
                    }
                    ForEach(override.reasons, id: \.self) { reason in
                        Text("“\(reason)”")
                    }
                }
            }
            row(key: Text(words.closingTitle), mark: false) {
                Text(words.closingLine)
            }
        }
    }

    private func row(
        key: Text,
        mark: Bool,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(spacing: 0) {
            Divider().overlay(JournalStyle.line)
            let layout = isWide
                ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 20))
                : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            layout {
                keyView(key, mark: mark)
                    .frame(width: isWide ? 180 : nil, alignment: .leading)
                valueView(content)
            }
            .padding(.vertical, 12)
        }
        .accessibilityElement(children: .combine)
    }

    private func keyView(_ key: Text, mark: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if mark {
                Circle()
                    .fill(JournalStyle.over)
                    .frame(width: 8, height: 8)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            }
            key
                .journalFont(.row)
                .foregroundStyle(JournalStyle.soft)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func valueView(_ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .journalFont(.body)
        .foregroundStyle(JournalStyle.ink)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
