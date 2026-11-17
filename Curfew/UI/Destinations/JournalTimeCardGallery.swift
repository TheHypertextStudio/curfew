import CurfewKit
import SwiftUI

/// The editing gallery: Stock, Sky, Punches and Headline, each option a live
/// miniature of the card with only that choice changed, on its own stage.
struct JournalTimeCardGallery: View {
    let card: JournalYearReview.Card
    let style: JournalTimeCardStyle
    let choose: ((inout JournalTimeCardChoices) -> Void) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: CurfewSpacing.xLarge) {
                stock
                sky
                punches
                headline
            }
            Grid(
                alignment: .topLeading,
                horizontalSpacing: CurfewSpacing.xLarge,
                verticalSpacing: CurfewSpacing.large
            ) {
                GridRow {
                    stock
                    sky
                }
                GridRow {
                    punches
                    headline
                }
            }
        }
    }

    private var stock: some View {
        group("Stock", JournalTimeCardStock.allCases, current: style.stock) { option in
            var next = style
            next.stock = option
            return next
        } pick: { option in choose { $0.stock = option } }
    }

    private var sky: some View {
        group("Sky", JournalTimeCardSky.allCases, current: style.sky) { option in
            var next = style
            next.sky = option
            return next
        } pick: { option in choose { $0.sky = option } }
    }

    private var punches: some View {
        group("Punches", JournalTimeCardPunches.allCases, current: style.punches) { option in
            var next = style
            next.punches = option
            return next
        } pick: { option in choose { $0.punches = option } }
    }

    private var headline: some View {
        group("Headline", JournalTimeCardHeadline.allCases, current: style.headline) { option in
            var next = style
            next.headline = option
            return next
        } pick: { option in choose { $0.headline = option } }
    }

    private func group<Option: Hashable & JournalTimeCardOption>(
        _ title: String,
        _ options: [Option],
        current: Option,
        preview: @escaping (Option) -> JournalTimeCardStyle,
        pick: @escaping (Option) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.small) {
            Text(title)
                .journalFont(.cardTitle)
                .foregroundStyle(JournalStyle.soft)
                .accessibilityAddTraits(.isHeader)
            HStack(alignment: .top, spacing: CurfewSpacing.small) {
                ForEach(options, id: \.self) { option in
                    JournalTimeCardOptionTile(
                        card: card,
                        style: preview(option),
                        title: option.title,
                        spokenTitle: "\(option.title) \(title.lowercased())",
                        isSelected: option == current
                    ) { pick(option) }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

/// The four kinds of choice share a title.
protocol JournalTimeCardOption {
    var title: String { get }
}

extension JournalTimeCardStock: JournalTimeCardOption {}
extension JournalTimeCardSky: JournalTimeCardOption {}
extension JournalTimeCardPunches: JournalTimeCardOption {}
extension JournalTimeCardHeadline: JournalTimeCardOption {}

/// One option: the card in miniature on its own small stage, with a ring
/// when it is the current choice.
struct JournalTimeCardOptionTile: View {
    let card: JournalYearReview.Card
    let style: JournalTimeCardStyle
    let title: String
    let spokenTitle: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    static let width: CGFloat = 72
    static let height: CGFloat = 88
    static let radius: CGFloat = 12

    var body: some View {
        Button(action: action) {
            VStack(spacing: CurfewSpacing.xSmall + 2) {
                let shape = RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                JournalTimeCardArt(card: card, style: style)
                    .frame(width: 50)
                    .scaleEffect(isHovered && !reduceMotion ? 1.04 : 1)
                    .frame(width: Self.width, height: Self.height)
                    .background(JournalTimeCardInk(style).stage, in: shape)
                    .overlay {
                        shape.strokeBorder(
                            Color.primary.opacity(isSelected ? 0 : 0.1),
                            lineWidth: 1
                        )
                    }
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: Self.radius + 3, style: .continuous)
                            .strokeBorder(CurfewTheme.accent, lineWidth: 2)
                            .opacity(isSelected ? 1 : 0)
                    }
                Text(title)
                    .journalFont(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? JournalStyle.ink : JournalStyle.soft)
                    .lineLimit(1)
                    .fixedSize()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .spring(duration: 0.25), value: isHovered)
        .accessibilityLabel(spokenTitle)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
