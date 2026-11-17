import CurfewKit
import SwiftUI

/// The Journal's scrolling content for one period.
struct JournalPage: View {
    let screen: JournalScreen
    let format: JournalFormat
    @Binding var expanded: Set<Date>
    @Binding var showsAll: Bool
    var initiallyActive: Date?
    var editPrompts: () -> Void = {}

    var body: some View {
        if screen.state == .noHistory {
            firstDays
        } else {
            VStack(alignment: .leading, spacing: 40) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let review = screen.yearReview, screen.sections.first == .yearReview {
                        yearReview(review)
                            .padding(.vertical, 16)
                    }
                    if screen.state != .noWorkingDays {
                        JournalTilesView(tiles: screen.tiles)
                        chartCard
                    }
                }
                section("What the days say") {
                    Text(screen.patterns.basis)
                        .journalFont(.row)
                        .foregroundStyle(JournalStyle.soft)
                    JournalPatternsView(patterns: screen.patterns, format: format)
                        .padding(.top, 4)
                }
                if screen.state != .noWorkingDays {
                    section("Extra time, in your words") {
                        JournalWordsView(words: screen.words)
                    }
                    section("Every day") {
                        JournalDayTable(
                            rows: screen.rows,
                            collapsedRowLimit: screen.collapsedRowLimit,
                            showAllTitle: screen.showAllTitle,
                            expanded: $expanded,
                            showsAll: $showsAll
                        )
                    }
                }
                if let review = screen.yearReview, screen.sections.last == .yearReview {
                    yearReview(review)
                }
            }
        }
    }

    private func yearReview(_ review: JournalYearReview) -> some View {
        section("Year in review") {
            JournalYearReviewView(review: review)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(screen.label)
                .journalFont(.cardTitle)
                .foregroundStyle(JournalStyle.soft)
                .monospacedDigit()
            Text(screen.headline)
                .journalFont(.headline)
                .foregroundStyle(JournalStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 560, alignment: .leading)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var chartCard: some View {
        JournalCard(padding: 18) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 20) {
                    chartHeading
                    Spacer(minLength: 0)
                    legend
                }
                VStack(alignment: .leading, spacing: 8) {
                    chartHeading
                    legend
                }
            }
            if let grid = screen.yearGrid {
                JournalYearGridView(
                    days: screen.days,
                    grid: grid,
                    yearLabel: screen.label,
                    initiallyActive: initiallyActive
                )
            } else {
                JournalStopChart(
                    days: screen.days,
                    scale: screen.scale,
                    range: screen.period.range,
                    format: format,
                    initiallyActive: initiallyActive
                )
            }
        }
        .zIndex(1)
    }

    private var chartHeading: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(screen.chartTitle)
                .journalFont(.cardTitle)
                .foregroundStyle(JournalStyle.ink)
            if let subtitle = screen.chartSubtitle {
                Text(subtitle)
                    .journalFont(.row)
                    .foregroundStyle(JournalStyle.soft)
            }
        }
        .fixedSize()
    }

    private var legend: some View {
        JournalLegend(
            range: screen.period.range,
            showsNoStopTime: screen.days.contains { $0.kind == .noStopTime }
        )
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .journalFont(.section)
                .foregroundStyle(JournalStyle.ink)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var firstDays: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "book")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(JournalStyle.accent)
                .accessibilityHidden(true)
            Text(JournalScreen.firstDaysTitle)
                .journalFont(.headline)
                .foregroundStyle(JournalStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(JournalScreen.firstDaysLine)
                .journalFont(.body)
                .foregroundStyle(JournalStyle.soft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 520, alignment: .leading)
            Button("Edit prompts", action: editPrompts)
                .buttonStyle(.bordered)
                .buttonBorderShape(.roundedRectangle(radius: JournalStyle.controlRadius))
                .journalFont(.button)
                .padding(.top, 8)
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
