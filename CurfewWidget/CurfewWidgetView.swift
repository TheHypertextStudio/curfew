import SwiftUI
import WidgetKit

struct CurfewWidgetView: View {
    let entry: CurfewWidgetEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:  smallView
        case .systemMedium: mediumView
        default:            largeView
        }
    }

    // MARK: - Small: phase icon + time remaining

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: phaseIcon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(phaseColor)

            Text(timeRemainingText)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(phaseColor)
                .minimumScaleFactor(0.6)

            Text(phaseLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(14)
        .containerBackground(.fill.tertiary, for: .widget)
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

    // MARK: - Large: full status

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: phaseIcon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(phaseColor)
                Text("Curfew")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
            }

            Text(timeRemainingText)
                .font(.system(size: 48, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(phaseColor)
                .minimumScaleFactor(0.5)

            Text(phaseLabel)
                .font(.system(size: 13))
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
                .font(.system(size: 13))
                .foregroundStyle(.secondary)

                HStack {
                    Label("Lock", systemImage: "lock.fill")
                    Spacer()
                    Text(lock)
                        .monospacedDigit()
                }
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            } else {
                Text("Day off")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(16)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    // MARK: - Helpers

    private var timeRemainingText: String {
        switch entry.phase {
        case "day_off": return "Day off"
        case "locked":  return "Locked"
        default:
            let h = entry.minutesRemaining / 60
            let m = entry.minutesRemaining % 60
            return h > 0 ? "\(h)h \(m)m" : "\(m)m"
        }
    }

    private var phaseLabel: String {
        switch entry.phase {
        case "working": return entry.warningStage == "none" ? "Working" : "Warning \(entry.warningStage)"
        case "warning": return "Warning \(entry.warningStage)"
        case "locked":  return "Locked"
        case "day_off": return "Day off"
        default:        return entry.phase
        }
    }

    private var phaseIcon: String {
        switch entry.phase {
        case "working": return "checkmark.circle"
        case "warning": return "exclamationmark.triangle"
        case "locked":  return "lock.fill"
        case "day_off": return "sun.max"
        default:        return "circle"
        }
    }

    private var phaseColor: Color {
        switch entry.phase {
        case "warning": return .orange
        case "locked":  return .red
        default:        return .green
        }
    }
}
