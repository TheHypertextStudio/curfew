import SwiftUI

/// DESIGN PROPOSAL — not wired into the app.
///
/// The Journal's weekly view. The week itself is the content, so it's the
/// hero: a full-width chart of the seven nights, each marked kept / override /
/// day off / upcoming. Plain language, no "nights held".
struct JournalSundownView: View {
    enum NightState {
        case kept
        case overridden
        case off
        case upcoming
    }

    var dateRange = "June 1–7"
    var nights: [(day: String, state: NightState)] = [
        ("M", .kept), ("T", .overridden), ("W", .kept), ("T", .kept),
        ("F", .upcoming), ("S", .off), ("S", .off)
    ]
    var footnote = "2 extensions used this week"

    private let chartHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            chart
            legend
            Text(footnote)
                .font(SundownType.body(15))
                .foregroundStyle(Palette.inkSoft)
                .padding(.horizontal, 40)
                .padding(.top, 22)
        }
        .padding(.bottom, 44)
        .background(Palette.canvas)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dateRange.uppercased())
                .font(SundownType.label(12))
                .tracking(1.4)
                .foregroundStyle(Palette.inkSoft)
            Text("This Week")
                .font(SundownType.headline(34))
                .foregroundStyle(Palette.ink)
        }
        .padding(.horizontal, 40)
        .padding(.top, 40)
    }

    private var chart: some View {
        HStack(alignment: .bottom, spacing: 18) {
            ForEach(Array(nights.enumerated()), id: \.offset) { _, night in
                VStack(spacing: 14) {
                    ZStack(alignment: .bottom) {
                        bar(for: night.state)
                    }
                    .frame(maxWidth: .infinity, minHeight: chartHeight, alignment: .bottom)

                    Text(night.day)
                        .font(SundownType.strong(15))
                        .foregroundStyle(Palette.inkSoft)
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 34)
    }

    @ViewBuilder
    private func bar(for state: NightState) -> some View {
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)
        switch state {
        case .kept:
            shape.fill(Palette.ember).frame(height: chartHeight)
        case .overridden:
            shape.stroke(Palette.ember, lineWidth: 2.5).frame(height: chartHeight)
        case .upcoming:
            shape
                .stroke(
                    Palette.inkSoft.opacity(0.4),
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 5])
                )
                .frame(height: chartHeight)
        case .off:
            shape.fill(Palette.faint).frame(height: 30)
        }
    }

    private var legend: some View {
        HStack(spacing: 22) {
            legendItem(label: "Kept") {
                RoundedRectangle(cornerRadius: 4).fill(Palette.ember)
            }
            legendItem(label: "Override") {
                RoundedRectangle(cornerRadius: 4).stroke(Palette.ember, lineWidth: 2)
            }
            legendItem(label: "Day off") {
                RoundedRectangle(cornerRadius: 4).fill(Palette.faint)
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 30)
    }

    private func legendItem(label: String, swatch: () -> some View) -> some View {
        HStack(spacing: 8) {
            swatch()
                .frame(width: 13, height: 13)
            Text(label)
                .font(SundownType.strong(14))
                .foregroundStyle(Palette.inkSoft)
        }
    }

    /// Sundown palette, scoped to this proposal.
    private enum Palette {
        static let canvas = Color(red: 0.96, green: 0.94, blue: 0.90)
        static let ink = Color(red: 0.19, green: 0.16, blue: 0.14)
        static let inkSoft = Color(red: 0.52, green: 0.46, blue: 0.41)
        static let ember = Color(red: 0.85, green: 0.45, blue: 0.23)
        static let faint = Color.black.opacity(0.1)
    }
}
