import AppKit
import SwiftUI

/// Shared colour palette. Every palette member resolves via `adaptive(...)`
/// so switching between Aqua and Dark Aqua picks the right value at
/// render time — no manual `@Environment(\.colorScheme)` checks needed
/// at call sites.
enum CurfewTheme {
    // MARK: - Backgrounds

    /// Default window background.
    static let canvas = adaptive(light: RGB(0.95, 0.93, 0.90), dark: RGB(0.11, 0.12, 0.13))
    /// Slightly stronger canvas used for sidebars and section headers.
    static let canvasStrong = adaptive(light: RGB(0.89, 0.87, 0.83), dark: RGB(0.16, 0.17, 0.19))
    /// Raised panel fill — used by `CurfewPanel`.
    static let surface = adaptive(light: RGB(0.99, 0.98, 0.96), dark: RGB(0.15, 0.16, 0.18))
    /// Low-emphasis surface for secondary buttons and inputs.
    static let surfaceMuted = adaptive(light: RGB(0.96, 0.95, 0.92), dark: RGB(0.19, 0.20, 0.22))

    // MARK: - Text

    /// Primary text colour — warm near-black.
    static let ink = adaptive(light: RGB(0.19, 0.16, 0.14), dark: RGB(0.94, 0.92, 0.88))
    /// Secondary / caption text colour.
    static let mutedInk = adaptive(light: RGB(0.52, 0.46, 0.41), dark: RGB(0.64, 0.60, 0.55))

    // MARK: - Accent / semantic

    /// Primary brand accent — warm ember (the colour of the setting sun),
    /// used for tint and primary buttons.
    static let accent = adaptive(light: RGB(0.85, 0.45, 0.23), dark: RGB(0.92, 0.56, 0.33))
    /// Lower-emphasis variant of the accent, used for inactive states
    /// where the full-saturation accent would pull too much focus.
    static let accentMuted = adaptive(light: RGB(0.80, 0.52, 0.36), dark: RGB(0.85, 0.60, 0.44))
    /// Amber warning tint used by the warning-phase overlay and the
    /// pending-schedule-change callout.
    static let warning = adaptive(light: RGB(0.72, 0.45, 0.19), dark: RGB(0.90, 0.58, 0.25))

    /// Hairline panel border. Adapts to appearance by selecting an alpha
    /// that reads correctly against both light and dark backgrounds.
    static let border = Color(NSColor(name: nil) { app in
        app.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor.white.withAlphaComponent(0.12)
            : NSColor.black.withAlphaComponent(0.08)
    })
}

/// Minimal RGB struct — positional `init` keeps the palette dense
/// without the verbosity of `red:green:blue:` everywhere.
private struct RGB {
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat
    /// Positional init so palette lines read as raw triples.
    init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
        self.red = red; self.green = green; self.blue = blue
    }
}

/// Builds a `Color` that swaps between `light` and `dark` at render
/// time by inspecting the resolved `NSAppearance`. Centralising this
/// resolution means palette entries don't need their own `Color(...)`
/// wrappers.
private func adaptive(light: RGB, dark: RGB) -> Color {
    Color(NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let rgb = isDark ? dark : light
        return NSColor(red: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    })
}

/// Typography scale on the system font (SF Pro) — native, modern, with free
/// Dynamic Type and optical sizing. Numerals use the rounded design (clock-
/// like, warm); text uses the default design. Sizes are caller-supplied so one
/// helper serves every surface.
enum CurfewTypography {
    /// Large numeric display, e.g. the main "Xh Ym remaining" label.
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
    }

    /// Section / pane title. Defaults to 24 pt.
    static func title(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .bold)
    }

    /// Body text. Defaults to 15 pt.
    static func body(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .regular)
    }

    /// Medium-weight body text for row labels and emphasised copy.
    static func bodyEmphasis(_ size: CGFloat = 15) -> Font {
        .system(size: size, weight: .medium)
    }

    /// Small caption used by `CurfewSectionTitle` and status chips.
    static func label(_ size: CGFloat = 12) -> Font {
        .system(size: size, weight: .medium)
    }

    /// Bold rounded weight for numeric readouts (countdown, percentages).
    static func numeric(_ size: CGFloat = 24) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

/// Rounded-rect panel container. Applies the `surface` fill, hairline
/// border, and 16 pt corner radius. Used everywhere grouped content
/// sits on a canvas background.
struct CurfewPanel<Content: View>: View {
    /// Internal padding between the border and `content`. Defaults to 18.
    var padding: CGFloat = 18
    /// Child content rendered inside the panel.
    @ViewBuilder var content: Content

    /// Panel body — padded, filled, and bordered.
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
    }
}

/// Section heading with an optional subtitle beneath it. Used as the first
/// child of most `CurfewPanel` containers.
struct CurfewSectionTitle: View {
    /// The section title.
    let title: String
    /// Optional subtitle rendered below the title.
    var subtitle: String?

    /// Two-line heading layout — a confident title over an optional subtitle.
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(CurfewTypography.title(16))
                .foregroundStyle(CurfewTheme.ink)
            if let subtitle {
                Text(subtitle)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
        }
    }
}

/// Solid accent-filled button style. The app's primary call-to-action
/// treatment — one per panel at most.
struct CurfewPrimaryButtonStyle: ButtonStyle {
    /// Pressed state dims opacity and scales slightly for tactile feel.
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

/// Subdued button style for supporting actions. Sits on the muted
/// surface with a hairline border so it recedes from the primary
/// button.
struct CurfewSecondaryButtonStyle: ButtonStyle {
    /// Same press-state treatment as the primary button for consistency.
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
