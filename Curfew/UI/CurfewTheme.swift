import AppKit
import SwiftUI

enum CurfewTheme {
    // Backgrounds
    static let canvas       = adaptive(l: (0.95, 0.93, 0.90), d: (0.11, 0.12, 0.13))
    static let canvasStrong = adaptive(l: (0.89, 0.87, 0.83), d: (0.16, 0.17, 0.19))
    static let surface      = adaptive(l: (0.99, 0.98, 0.96), d: (0.15, 0.16, 0.18))
    static let surfaceMuted = adaptive(l: (0.96, 0.95, 0.92), d: (0.19, 0.20, 0.22))

    // Text
    static let ink      = adaptive(l: (0.13, 0.16, 0.18), d: (0.92, 0.91, 0.89))
    static let mutedInk = adaptive(l: (0.35, 0.39, 0.41), d: (0.58, 0.62, 0.65))

    // Accent / semantic
    static let accent      = adaptive(l: (0.19, 0.43, 0.36), d: (0.25, 0.62, 0.52))
    static let accentMuted = adaptive(l: (0.30, 0.53, 0.47), d: (0.32, 0.68, 0.58))
    static let warning     = adaptive(l: (0.72, 0.45, 0.19), d: (0.90, 0.58, 0.25))

    // Chrome
    static let border = Color(NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.08)
    })
    static let shadow = Color(NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.black.withAlphaComponent(0.30)
            : NSColor.black.withAlphaComponent(0.08)
    })
}

private func adaptive(
    l: (CGFloat, CGFloat, CGFloat),
    d: (CGFloat, CGFloat, CGFloat)
) -> Color {
    Color(NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let (r, g, b) = isDark ? d : l
        return NSColor(red: r, green: g, blue: b, alpha: 1)
    })
}

enum CurfewTypography {
    static func display(_ size: CGFloat) -> Font {
        .custom("AvenirNext-DemiBold", size: size)
    }

    static func title(_ size: CGFloat = 24) -> Font {
        .custom("AvenirNext-DemiBold", size: size)
    }

    static func body(_ size: CGFloat = 15) -> Font {
        .custom("AvenirNext-Regular", size: size)
    }

    static func bodyEmphasis(_ size: CGFloat = 15) -> Font {
        .custom("AvenirNext-Medium", size: size)
    }

    static func label(_ size: CGFloat = 12) -> Font {
        .custom("AvenirNext-Medium", size: size)
    }

    static func numeric(_ size: CGFloat = 24) -> Font {
        .custom("AvenirNext-Bold", size: size)
    }
}

struct CurfewPanel<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CurfewTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(CurfewTheme.border, lineWidth: 1)
        )
        .shadow(color: CurfewTheme.shadow, radius: 10, x: 0, y: 4)
    }
}

struct CurfewSectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(CurfewTypography.label(12))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(CurfewTheme.mutedInk)
            if let subtitle {
                Text(subtitle)
                    .font(CurfewTypography.body(14))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
        }
    }
}

struct CurfewPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CurfewTypography.bodyEmphasis(14))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CurfewTheme.accent)
            )
            .foregroundStyle(Color.white)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

struct CurfewSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(CurfewTypography.bodyEmphasis(14))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CurfewTheme.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(CurfewTheme.border, lineWidth: 1)
            )
            .foregroundStyle(CurfewTheme.ink)
            .opacity(configuration.isPressed ? 0.86 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}
