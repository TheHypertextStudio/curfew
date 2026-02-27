import SwiftUI

enum CurfewTheme {
    static let canvas = Color(red: 0.95, green: 0.93, blue: 0.90)
    static let canvasStrong = Color(red: 0.89, green: 0.87, blue: 0.83)
    static let surface = Color(red: 0.99, green: 0.98, blue: 0.96)
    static let surfaceMuted = Color(red: 0.96, green: 0.95, blue: 0.92)

    static let ink = Color(red: 0.13, green: 0.16, blue: 0.18)
    static let mutedInk = Color(red: 0.35, green: 0.39, blue: 0.41)

    static let accent = Color(red: 0.19, green: 0.43, blue: 0.36)
    static let accentMuted = Color(red: 0.30, green: 0.53, blue: 0.47)
    static let warning = Color(red: 0.72, green: 0.45, blue: 0.19)

    static let border = Color.black.opacity(0.08)
    static let shadow = Color.black.opacity(0.08)
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
