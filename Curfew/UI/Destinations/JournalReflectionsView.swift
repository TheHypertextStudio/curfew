import CurfewKit
import SwiftUI

/// The Journal's reflections section — the per-entry log plus a neutral
/// "Ratings this week" trend for every rating question, below the week's
/// sundown chart. Uses the shared ``JournalPalette`` so the Journal reads as
/// one surface.
struct JournalReflectionsView: View {
    /// The week's reflections (any order); grouped and charted internally.
    let reflections: [Reflection]

    /// A date inside the week being shown — used to lay out the 7-day trend
    /// axis. Defaults are supplied by the caller (the live clock).
    let referenceDate: Date

    /// Called when the user taps "Set up prompts" in the empty-entries state.
    var onConfigurePrompts: () -> Void = {}

    private typealias Palette = JournalPalette

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            if !ratingTrends.isEmpty {
                trendsSection
            }
            entriesSection
        }
        .padding(.top, 8)
        .padding(.bottom, 44)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.canvas)
    }

    // MARK: - Trends

    private var trendsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Ratings this week")
                .font(SundownType.headline(24))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 18) {
                ForEach(ratingTrends) { trend in
                    trendRow(trend)
                }
            }
            .padding(.horizontal, 40)
        }
    }

    private func trendRow(_ trend: RatingTrend) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(trend.label)
                    .font(SundownType.title(15))
                    .foregroundStyle(Palette.ink)
                Spacer(minLength: 12)
                Text(trend.averageText)
                    .font(SundownType.strong(14))
                    .foregroundStyle(Palette.inkSoft)
                    .accessibilityLabel("average \(trend.averageText)")
            }

            HStack(alignment: .bottom, spacing: 10) {
                ForEach(weekDays, id: \.self) { day in
                    trendBar(value: trend.points[day], scale: trend.scale, day: day)
                }
            }
            .frame(height: 64)
        }
        .accessibilityElement(children: .combine)
    }

    private func trendBar(value: Int?, scale: Int, day: Date) -> some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let fraction = value.map { Double($0) / Double(max(1, scale)) } ?? 0
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Palette.faint)
                        .frame(height: 4)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    if value != nil {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Palette.ember)
                            .frame(height: max(4, geo.size.height * fraction))
                    }
                }
            }
            Text(Self.narrowDayFormatter.string(from: day))
                .font(SundownType.label(11))
                .foregroundStyle(Palette.inkSoft)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(
            value.map { "\(Self.fullDayFormatter.string(from: day)): \($0) of \(scale)" }
                ?? "\(Self.fullDayFormatter.string(from: day)): no rating"
        )
    }

    // MARK: - Entries

    private var entriesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Reflections")
                .font(SundownType.headline(24))
                .foregroundStyle(Palette.ink)
                .padding(.horizontal, 40)
                .padding(.bottom, 18)

            if groupedDays.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    Text("No reflections yet this week. They'll appear here as you "
                        + "set intentions in the morning and close out the day.")
                        .font(SundownType.body(15))
                        .foregroundStyle(Palette.inkSoft)
                    Button(action: onConfigurePrompts) {
                        HStack(spacing: 6) {
                            Text("Set up reflection prompts")
                                .font(SundownType.title(14))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Palette.ember)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 40)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(groupedDays, id: \.day) { group in
                        dayBlock(group)
                    }
                }
                .padding(.horizontal, 40)
            }
        }
    }

    private func dayBlock(_ group: DayGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.dayFormatter.string(from: group.day).uppercased())
                .font(SundownType.label(12))
                .tracking(1.2)
                .foregroundStyle(Palette.inkSoft)

            ForEach(group.reflections) { reflection in
                entry(reflection)
            }
        }
    }

    private func entry(_ reflection: Reflection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: reflection.gate == .morning ? "sunrise" : "sunset")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.ember)
                Text(reflection.gate == .morning ? "Morning intent" : "Evening reflection")
                    .font(SundownType.title(15))
                    .foregroundStyle(Palette.ink)
                Spacer()
                Text(Self.timeFormatter.string(from: reflection.timestamp))
                    .font(SundownType.body(13))
                    .foregroundStyle(Palette.inkSoft)
            }

            ForEach(reflection.answers) { answer in
                answerRow(answer)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func answerRow(_ answer: ReflectionAnswer) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(answer.promptTextSnapshot)
                .font(SundownType.label(12))
                .foregroundStyle(Palette.inkSoft)
            answerValue(answer.value)
        }
    }

    @ViewBuilder
    private func answerValue(_ value: ReflectionValue) -> some View {
        switch value {
        case .text(let string):
            Text(string)
                .font(SundownType.body(15))
                .foregroundStyle(Palette.ink)
        default:
            chip(text: reflectionValueText(value))
        }
    }

    private func chip(text: String) -> some View {
        Text(text)
            .font(SundownType.strong(14))
            .foregroundStyle(Palette.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Palette.ember.opacity(0.16))
            .clipShape(Capsule())
    }

    private var ratingTrends: [RatingTrend] {
        RatingTrend.build(from: reflections)
    }

    /// The seven day-starts of the week containing ``referenceDate``,
    /// first-weekday aligned (matching `reflections(inWeekOf:)`).
    private var weekDays: [Date] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let daysBack = (weekday - calendar.firstWeekday + 7) % 7
        let weekStart = calendar
            .date(byAdding: .day, value: -daysBack, to: startOfDay) ?? startOfDay
        return (0 ..< 7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    // MARK: - Entry grouping

    private struct DayGroup {
        let day: Date
        let reflections: [Reflection]
    }

    /// Reflections grouped by start-of-day, newest day first; within a day
    /// morning sorts before evening (then by timestamp).
    private var groupedDays: [DayGroup] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: reflections) {
            calendar.startOfDay(for: $0.timestamp)
        }
        return buckets.keys.sorted(by: >).map { day in
            let sorted = (buckets[day] ?? []).sorted { lhs, rhs in
                if lhs.gate != rhs.gate {
                    return lhs.gate == .morning
                }
                return lhs.timestamp < rhs.timestamp
            }
            return DayGroup(day: day, reflections: sorted)
        }
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter
    }()

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()

    private static let narrowDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEEE"
        return formatter
    }()

    private static let fullDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        return formatter
    }()
}
