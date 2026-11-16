import SwiftUI

/// A column with a rounded data end and a square end on the curfew line.
struct JournalColumnShape: Shape {
    /// True when the data end is at the top (an early day).
    let roundsTop: Bool

    func path(in rect: CGRect) -> Path {
        let radius = min(4, rect.height / 2, rect.width / 2)
        return Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(
            topLeading: roundsTop ? radius : 0,
            bottomLeading: roundsTop ? 0 : radius,
            bottomTrailing: roundsTop ? 0 : radius,
            topTrailing: roundsTop ? radius : 0
        ), style: .continuous)
    }
}

/// The dark card that follows hover and keyboard focus.
struct JournalTooltipView: View {
    let tooltip: JournalTooltip

    var body: some View {
        JournalCappedWidth(maxWidth: 236) {
            content
        }
        .foregroundStyle(JournalStyle.tipForeground)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            JournalStyle.tipBackground,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(tooltip.date)
                .journalFont(.small)
                .opacity(0.72)
            Text(tooltip.headline)
                .journalFont(.statement)
                .padding(.bottom, 3)
            if let mark = tooltip.mark, let text = tooltip.markText {
                HStack(spacing: 7) {
                    Capsule()
                        .fill(JournalStyle.color(mark))
                        .frame(width: 12, height: 3)
                    Text(text)
                }
                .journalFont(.small)
            }
            ForEach(tooltip.lines, id: \.self) { line in
                Text(line)
                    .journalFont(.small)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let footnote = tooltip.footnote {
                Text(footnote)
                    .journalFont(.small)
                    .opacity(0.72)
            }
        }
    }
}

/// Sizes its content to fit, but no wider than `maxWidth`; longer text wraps.
struct JournalCappedWidth: Layout {
    let maxWidth: CGFloat

    func sizeThatFits(
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let ideal = content.sizeThatFits(.unspecified)
        return content.sizeThatFits(ProposedViewSize(
            width: min(ideal.width, maxWidth),
            height: nil
        ))
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal _: ProposedViewSize,
        subviews: Subviews,
        cache _: inout ()
    ) {
        subviews.first?.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }
}
