import AppKit
import CurfewKit
import SwiftUI

/// Shared colour palette. Every palette member resolves via `adaptive(...)`
/// so switching between Aqua and Dark Aqua picks the right value at
/// render time — no manual `@Environment(\.colorScheme)` checks needed
/// at call sites.
enum CurfewTheme {
    // MARK: - Backgrounds

    /// Default window background.
    static let canvas = adaptive(light: RGB(0.961, 0.953, 0.941), dark: RGB(0.125, 0.118, 0.114))
    /// Slightly stronger canvas used for sidebars and section headers.
    static let canvasStrong = adaptive(
        light: RGB(0.914, 0.898, 0.875),
        dark: RGB(0.153, 0.141, 0.133)
    )
    /// Raised panel fill — used by `CurfewPanel`.
    static let surface = adaptive(light: RGB(0.988, 0.980, 0.969), dark: RGB(0.169, 0.157, 0.149))
    /// Low-emphasis surface for secondary buttons and inputs.
    static let surfaceMuted = adaptive(
        light: RGB(0.933, 0.918, 0.894),
        dark: RGB(0.204, 0.188, 0.176)
    )

    // MARK: - Text

    /// Primary text colour — warm near-black.
    static let ink = adaptive(light: RGB(0.188, 0.165, 0.149), dark: RGB(0.957, 0.933, 0.914))
    /// Secondary / caption text colour.
    static let mutedInk = adaptive(light: RGB(0.412, 0.369, 0.337), dark: RGB(0.718, 0.671, 0.631))

    // MARK: - Accent / semantic

    /// Clay accent for readable links and native control tint.
    static let accent = adaptive(light: RGB(0.608, 0.310, 0.188), dark: RGB(0.800, 0.545, 0.408))
    /// Filled controls keep white labels readable in both appearances.
    static let accentFill = adaptive(
        light: RGB(0.608, 0.310, 0.188),
        dark: RGB(0.702, 0.365, 0.224)
    )
    /// Foreground and progress overlay for filled controls. A dark progress wash
    /// preserves label contrast throughout a hold instead of whitening the fill.
    static let onAccent = Color.white
    static let filledProgressOverlay = Color.black.opacity(0.18)
    /// Compatibility alias; inactive controls use opacity rather than a separate hue.
    static let accentMuted = accent
    /// Amber warning tint used by the warning-phase overlay and the
    /// pending-schedule-change callout.
    static let warning = adaptive(light: RGB(0.518, 0.337, 0.145), dark: RGB(0.878, 0.663, 0.365))

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

/// Spacing scale shared across the app's chrome (Settings, the workspace
/// destinations, panels). Centralising the values means the rhythm is
/// consistent and, crucially, that inter-panel spacing (`section`) reads as
/// larger than intra-panel spacing (`medium`) so grouped cards stay visually
/// distinct instead of melting together.
enum CurfewSpacing {
    /// Tight 4 pt gap — adjacent glyphs, chip internals.
    static let xSmall: CGFloat = 4
    /// 8 pt — related controls on one line.
    static let small: CGFloat = 8
    /// 12 pt — default gap between rows inside a panel.
    static let medium: CGFloat = 12
    /// 16 pt — generous in-panel separation, e.g. title to first control.
    static let large: CGFloat = 16
    /// 24 pt — outer page padding around a tab's scroll content.
    static let xLarge: CGFloat = 24
    /// 20 pt — gap *between* panels in a stack. Deliberately larger than
    /// `medium` so cards read as separate groups; deliberately smaller than
    /// `xLarge` so a tab doesn't feel sparse.
    static let section: CGFloat = 20
}

/// The Curfew chrome's typographic names, mapped onto the one canonical scale
/// (``SundownType``) so the whole app — workspace, Settings, and the sundown
/// surfaces — speaks a single typographic voice. These are thin aliases; the
/// scale itself (SF Pro, rounded numerals, weight earned by headlines and
/// figures) lives in one place.
enum CurfewTypography {
    /// Large numeric display, e.g. the main countdown.
    static func display(_ size: CGFloat) -> Font {
        SundownType.display(size)
    }

    /// Section / pane title. Defaults to 24 pt.
    static func title(_ size: CGFloat = 24) -> Font {
        SundownType.headline(size)
    }

    /// Body text. Defaults to 15 pt.
    static func body(_ size: CGFloat = 15) -> Font {
        SundownType.body(size)
    }

    /// Medium-weight body text for row labels and emphasised copy.
    static func bodyEmphasis(_ size: CGFloat = 15) -> Font {
        SundownType.strong(size)
    }

    /// Small caption used by `CurfewSectionTitle` and status chips.
    static func label(_ size: CGFloat = 12) -> Font {
        SundownType.label(size)
    }

    /// Bold rounded weight for numeric readouts (countdown, percentages).
    static func numeric(_ size: CGFloat = 24) -> Font {
        SundownType.figure(size)
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
        VStack(alignment: .leading, spacing: CurfewSpacing.medium) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CurfewTheme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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

/// Shared press feedback, including disabled and accessibility presentation.
struct CurfewButtonFeedback: Equatable {
    let opacity: Double
    let scale: CGFloat
    let animates: Bool

    static func resolve(isEnabled: Bool, isPressed: Bool, reduceMotion: Bool) -> Self {
        Self(
            opacity: isEnabled ? (isPressed ? 0.9 : 1) : 0.45,
            scale: isEnabled && isPressed && !reduceMotion ? 0.97 : 1,
            animates: isEnabled && !reduceMotion
        )
    }
}

/// Solid accent-filled button style. The app's primary call-to-action
/// treatment — one per panel at most.
struct CurfewPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Pressed state dims opacity and scales slightly for tactile feel.
    func makeBody(configuration: Configuration) -> some View {
        let feedback = CurfewButtonFeedback.resolve(
            isEnabled: isEnabled, isPressed: configuration.isPressed, reduceMotion: reduceMotion
        )
        return configuration.label
            .font(CurfewTypography.bodyEmphasis(14))
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CurfewTheme.accentFill)
            )
            .foregroundStyle(CurfewTheme.onAccent)
            .opacity(feedback.opacity)
            .scaleEffect(feedback.scale)
            .animation(
                feedback.animates ? .easeOut(duration: 0.12) : nil,
                value: configuration.isPressed
            )
    }
}

/// Subdued button style for supporting actions. Sits on the muted
/// surface with a hairline border so it recedes from the primary
/// button.
struct CurfewSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Same press-state treatment as the primary button for consistency.
    func makeBody(configuration: Configuration) -> some View {
        let feedback = CurfewButtonFeedback.resolve(
            isEnabled: isEnabled, isPressed: configuration.isPressed, reduceMotion: reduceMotion
        )
        return configuration.label
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
            .opacity(feedback.opacity)
            .scaleEffect(feedback.scale)
            .animation(
                feedback.animates ? .easeOut(duration: 0.12) : nil,
                value: configuration.isPressed
            )
    }
}

/// Chromeless accent text button — an inline affordance ("Add prompt",
/// "Buy Curfew Plus") that reads as a link without the surface/border of the
/// secondary style. Standardises the scattered `.borderless` / `.plain`
/// buttons so the app speaks one button language.
struct CurfewLinkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Tints the label with the accent and dims slightly while pressed.
    func makeBody(configuration: Configuration) -> some View {
        let feedback = CurfewButtonFeedback.resolve(
            isEnabled: isEnabled, isPressed: configuration.isPressed, reduceMotion: reduceMotion
        )
        return configuration.label
            .font(CurfewTypography.bodyEmphasis(14))
            .foregroundStyle(CurfewTheme.accent)
            .opacity(feedback.opacity)
            .animation(
                feedback.animates ? .easeOut(duration: 0.12) : nil,
                value: configuration.isPressed
            )
            .contentShape(Rectangle())
    }
}
