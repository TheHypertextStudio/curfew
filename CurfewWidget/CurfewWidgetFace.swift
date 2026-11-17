import SwiftUI

/// What the widget says for one moment, free of WidgetKit so it can be
/// tested and rendered anywhere.
struct CurfewWidgetPresentation: Equatable {
    enum Phase: String {
        case working
        case warning
        case locked
        case dayOff = "day_off"
    }

    /// Big rounded numerals: "2:30" before curfew, otherwise a short word.
    let headline: String
    /// Whether the headline is a countdown (numerals) or words.
    let headlineIsCountdown: Bool
    /// "until curfew at 6:00 PM", "Unlocks at 7:00 AM", "No curfew today."
    let line: String
    /// Height of the sun above the horizon, 0 (at the line) to 1. `nil`
    /// hides the sun entirely, as it does while this Mac is locked.
    let sunHeight: Double?
    /// One sentence VoiceOver reads for the whole widget.
    let accessibilityLabel: String

    /// The working day the sun's height is measured against.
    static let dayLengthMinutes = 8 * 60

    init(
        phase rawPhase: String,
        minutesRemaining: Int,
        lockDate: Date?,
        unlockDate: Date?,
        timeFormatter: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
    ) {
        let phase = Phase(rawValue: rawPhase) ?? .working
        switch phase {
        case .working, .warning:
            let minutes = max(0, minutesRemaining)
            let countdown = Self.countdown(minutes: minutes)
            headline = countdown
            headlineIsCountdown = true
            if let lockDate {
                line = "until curfew at \(timeFormatter(lockDate))"
            } else {
                line = "until curfew"
            }
            sunHeight = min(1, Double(minutes) / Double(Self.dayLengthMinutes))
            accessibilityLabel = "\(Self.spokenDuration(minutes: minutes)) \(line)."
        case .locked:
            headline = "That's the day."
            headlineIsCountdown = false
            line = unlockDate.map { "Unlocks at \(timeFormatter($0))" } ?? "Locked"
            sunHeight = nil
            accessibilityLabel = "Locked. \(line)."
        case .dayOff:
            headline = "Day off"
            headlineIsCountdown = false
            line = "No curfew today."
            sunHeight = 1
            accessibilityLabel = "Day off. No curfew today."
        }
    }

    /// Hours and minutes as the app shows them: "2:30", "0:05".
    static func countdown(minutes: Int) -> String {
        let minutes = max(0, minutes)
        return "\(minutes / 60):" + String(format: "%02d", minutes % 60)
    }

    static func spokenDuration(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        func unit(_ value: Int, _ name: String) -> String {
            "\(value) \(name)\(value == 1 ? "" : "s")"
        }
        switch (hours, rest) {
        case (0, _): return unit(rest, "minute")
        case (_, 0): return unit(hours, "hour")
        default: return "\(unit(hours, "hour")) \(unit(rest, "minute"))"
        }
    }
}

/// The app's ember accent. The widget cannot import the app's theme, so the
/// two values are repeated here and kept identical to `CurfewTheme.accent`.
enum CurfewWidgetPalette {
    static let ember = Color(nsColor: NSColor(name: nil) { appearance in
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return dark
            ? NSColor(srgbRed: 0.800, green: 0.545, blue: 0.408, alpha: 1)
            : NSColor(srgbRed: 0.608, green: 0.310, blue: 0.188, alpha: 1)
    })
}

/// A sun over a line. The sun sits lower as curfew nears and is gone while
/// this Mac is locked, leaving only the line.
struct CurfewHorizonGlyph: View {
    let sunHeight: Double?

    var body: some View {
        Canvas { context, size in
            let lineY = size.height * 0.78
            let lineWidth = max(1.5, size.height * 0.06)
            var line = Path()
            line.move(to: CGPoint(x: 0, y: lineY))
            line.addLine(to: CGPoint(x: size.width, y: lineY))
            context.stroke(line, with: .color(.secondary), style: StrokeStyle(
                lineWidth: lineWidth, lineCap: .round
            ))
            guard let sunHeight else { return }
            let radius = size.height * 0.22
            let lowest = lineY - radius * 0.35
            let highest = radius + lineWidth
            let centerY = lowest - (lowest - highest) * sunHeight
            let sun = Path(ellipseIn: CGRect(
                x: size.width / 2 - radius, y: centerY - radius,
                width: radius * 2, height: radius * 2
            ))
            // The line hides whatever part of the sun has set below it.
            context.clip(to: Path(CGRect(x: 0, y: 0, width: size.width, height: lineY - lineWidth / 2)))
            context.fill(sun, with: .color(CurfewWidgetPalette.ember))
        }
        .accessibilityHidden(true)
    }
}

/// The widget's face for the small and medium sizes.
struct CurfewWidgetFace: View {
    enum Size {
        case small
        case medium
    }

    let presentation: CurfewWidgetPresentation
    let size: Size

    var body: some View {
        switch size {
        case .small: small
        case .medium: medium
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            CurfewHorizonGlyph(sunHeight: presentation.sunHeight)
                .frame(width: 64, height: 40)
            Spacer(minLength: 6)
            headline(.largeTitle)
            Text(presentation.line)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    private var medium: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Spacer(minLength: 0)
                headline(.system(size: 48, weight: .semibold, design: .rounded), scales: true)
                Text(presentation.line)
                    .font(.headline.weight(.regular))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            CurfewHorizonGlyph(sunHeight: presentation.sunHeight)
                .frame(width: 112, height: 72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }

    @ViewBuilder
    private func headline(_ style: Font, scales: Bool = false) -> some View {
        if presentation.headlineIsCountdown {
            Text(presentation.headline)
                .font(scales ? style : .system(.largeTitle, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        } else {
            Text(presentation.headline)
                .font(.system(.title2, design: .rounded).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }
}
