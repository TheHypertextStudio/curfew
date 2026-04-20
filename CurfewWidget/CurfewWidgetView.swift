import SwiftUI
import WidgetKit

/// WidgetKit view hierarchy. Dispatches to one of three layouts by
/// `@Environment(\.widgetFamily)` — small (Gauge ring), medium
/// (schedule + work-time row), and large (7-day bar chart + streak).
struct CurfewWidgetView: View {
    /// Timeline-provided snapshot to render.
    let entry: CurfewWidgetEntry
    /// WidgetKit family selected by the user in the gallery. Determines
    /// which of the three bodies renders.
    @Environment(\.widgetFamily) private var family

    /// Picks the layout variant based on the user's selected family.
    var body: some View {
        switch family {
        case .systemSmall: smallView
        case .systemMedium: mediumView
        default: largeView
        }
    }

    // MARK: - Small: phase-tinted countdown ring

    private var smallView: some View {
        ZStack {
            Gauge(value: ringProgress) {
                EmptyView()
            } currentValueLabel: {
                VStack(spacing: 2) {
                    Image(systemName: phaseIcon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(phaseColor)
                    Text(timeRemainingText)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(phaseColor)
                        .minimumScaleFactor(0.5)
                }
            }
            .gaugeStyle(.accessoryCircular)
            .tint(phaseColor)
            .scaleEffect(1.6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// Normalized 0 … 1 progress for the ring. Day-off and lockout render
    /// as full circles; during working/warning, progress fills from 0 at
    /// the start of the window to 1 at the lock moment.
    private var ringProgress: Double {
        switch entry.phase {
        case "day_off", "locked":
            return 1.0
        default:
            // Map minutesRemaining ∈ (0 … 480] to progress ∈ (1 … 0]; clamp.
            let minutes = max(0, min(entry.minutesRemaining, 480))
            return 1.0 - Double(minutes) / 480.0
        }
    }

    // MARK: - Medium: phase + remaining + schedule window

    private var mediumView: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: phaseIcon)
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(phaseColor)

                Text(timeRemainingText)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(phaseColor)
                    .minimumScaleFactor(0.6)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Curfew")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(phaseLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if let lock = entry.lockTime, let unlock = entry.unlockTime {
                    Text("\(unlock) → \(lock)")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Large: status + weekly chart + streak

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: phaseIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(phaseColor)
                Text("Curfew")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                streakPill
            }

            Text(timeRemainingText)
                .font(.system(size: 44, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(phaseColor)
                .minimumScaleFactor(0.5)

            Text(phaseLabel)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Divider()

            if let lock = entry.lockTime, let unlock = entry.unlockTime {
                HStack {
                    Label("Unlock", systemImage: "lock.open")
                    Spacer()
                    Text(unlock)
                        .monospacedDigit()
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

                HStack {
                    Label("Lock", systemImage: "lock.fill")
                    Spacer()
                    Text(lock)
                        .monospacedDigit()
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            } else {
                Text("Day off")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
            weeklyBars
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    /// Streak pill, rendered top-right on the large widget. Hidden when
    /// streak is 0 so a freshly-installed app doesn't advertise "0 days"
    /// as a spurious achievement.
    @ViewBuilder
    private var streakPill: some View {
        if entry.weeklyStreakDays > 0 {
            HStack(spacing: 3) {
                Image(systemName: "flame.fill")
                Text("\(entry.weeklyStreakDays)")
                    .monospacedDigit()
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(phaseColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(phaseColor.opacity(0.15), in: Capsule())
        }
    }

    /// Seven-bar sparkline of this week's lockouts. Filled bar = day held,
    /// hollow bar = day missed or still pending. Monday-first.
    private var weeklyBars: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(0 ..< entry.dailyBars.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(
                        entry.dailyBars[index] > 0
                            ? phaseColor
                            : phaseColor.opacity(0.2)
                    )
                    .frame(width: 10, height: 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Helpers

    /// Countdown label text — special-cased for day-off and locked
    /// phases, otherwise formatted as `Xh Ym` or `Ym`.
    private var timeRemainingText: String {
        switch entry.phase {
        case "day_off": return "Day off"
        case "locked": return "Locked"
        default:
            let h = entry.minutesRemaining / 60
            let m = entry.minutesRemaining % 60
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        }
    }

    /// Human-readable phase label shown under the countdown. For the
    /// warning phase it folds in the stage token so glances read
    /// "Warning T-5" instead of a bare "Warning".
    private var phaseLabel: String {
        switch entry.phase {
        case "working": entry.warningStage == "none" ? "Working" : "Warning \(entry.warningStage)"
        case "warning": "Warning \(entry.warningStage)"
        case "locked": "Locked"
        case "day_off": "Day off"
        default: entry.phase
        }
    }

    /// SF Symbol that accompanies the phase label. Tracks the app's
    /// menu-bar icon vocabulary so the widget feels consistent with
    /// other surfaces.
    private var phaseIcon: String {
        switch entry.phase {
        case "working": "checkmark.circle"
        case "warning": "exclamationmark.triangle"
        case "locked": "lock.fill"
        case "day_off": "sun.max"
        default: "circle"
        }
    }

    /// Tint colour for the Gauge ring and icon. Green for working /
    /// day-off, orange for warning, red for locked — matches the
    /// menu-bar icon tinting.
    private var phaseColor: Color {
        switch entry.phase {
        case "warning": .orange
        case "locked": .red
        default: .green
        }
    }
}
