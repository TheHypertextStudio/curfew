import CurfewAtmosphere
import SwiftUI

/// Sizes and spacing for setup. The radii and spacing steps follow the launch
/// spec (8 for controls, 20 for panels, capsule for floating buttons; spacing
/// 4, 8, 12, 16, 24, 40, 64) until shared tokens replace them.
enum GettingStartedLayout {
    static let controlRadius: CGFloat = 8
    static let panelRadius: CGFloat = 20
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24
    static let spacing40: CGFloat = 40

    /// The smallest frame every step fits in at the default text size.
    static let contentMinimum = CGSize(width: 640, height: 500)
    /// The window opens at exactly the size its content needs; a larger
    /// system text size grows the window rather than clipping.
    static let windowSize = contentMinimum
}

/// Colours setup uses beyond the shared paper and ink.
enum GettingStartedPalette {
    /// The floating drag panel and the lock preview sit over other apps, so
    /// they keep the night palette in both appearances.
    static let panelSurface = Color.black.opacity(0.88)
    static let panelText = AtmospherePalette.warmWhite
    static let panelMutedText = AtmospherePalette.warmWhite.opacity(0.72)
}

/// The single backdrop behind every setup step. A plain surface today; the
/// sky drops in here, and only here.
struct GettingStartedBackdrop: View {
    var body: some View {
        CurfewTheme.canvas
            .ignoresSafeArea()
    }
}

/// Filled, rounded-design primary action for setup.
struct GettingStartedPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .padding(.horizontal, GettingStartedLayout.spacing16)
            .padding(.vertical, GettingStartedLayout.spacing8)
            .frame(minHeight: 32)
            .foregroundStyle(CurfewTheme.onAccent)
            .background(
                CurfewTheme.accentFill.opacity(isEnabled ? 1 : 0.4),
                in: RoundedRectangle(cornerRadius: GettingStartedLayout.controlRadius)
            )
            .overlay {
                if configuration.isPressed {
                    RoundedRectangle(cornerRadius: GettingStartedLayout.controlRadius)
                        .fill(CurfewTheme.filledProgressOverlay)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: GettingStartedLayout.controlRadius))
    }
}

/// Outlined, rounded-design action. Skip uses this too, so declining is as
/// easy to see as accepting.
struct GettingStartedSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded, weight: .semibold))
            .padding(.horizontal, GettingStartedLayout.spacing16)
            .padding(.vertical, GettingStartedLayout.spacing8)
            .frame(minHeight: 32)
            .foregroundStyle(CurfewTheme.ink.opacity(isEnabled ? 1 : 0.4))
            .background(
                configuration.isPressed ? CurfewTheme.surfaceMuted : CurfewTheme.surface,
                in: RoundedRectangle(cornerRadius: GettingStartedLayout.controlRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: GettingStartedLayout.controlRadius)
                    .strokeBorder(CurfewTheme.border)
            )
            .contentShape(RoundedRectangle(cornerRadius: GettingStartedLayout.controlRadius))
    }
}

/// The small text link that keeps "no schedule yet" available without
/// competing with the primary action.
struct GettingStartedLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, design: .rounded, weight: .medium))
            .foregroundStyle(CurfewTheme.accent.opacity(configuration.isPressed ? 0.6 : 1))
            .underline()
            .contentShape(Rectangle())
    }
}

/// A weekday chip: a toggle drawn as a small rounded control.
struct GettingStartedChipStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .font(.system(.callout, design: .rounded, weight: .semibold))
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 32)
                .padding(.horizontal, GettingStartedLayout.spacing4)
                .foregroundStyle(configuration.isOn ? CurfewTheme.onAccent : CurfewTheme.ink)
                .background(
                    configuration.isOn ? CurfewTheme.accentFill : CurfewTheme.surface,
                    in: RoundedRectangle(cornerRadius: GettingStartedLayout.controlRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: GettingStartedLayout.controlRadius)
                        .strokeBorder(configuration.isOn ? Color.clear : CurfewTheme.border)
                )
                .contentShape(RoundedRectangle(cornerRadius: GettingStartedLayout.controlRadius))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

/// A grouped panel on the setup backdrop.
struct GettingStartedPanel<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .background(
            CurfewTheme.surface,
            in: RoundedRectangle(cornerRadius: GettingStartedLayout.panelRadius, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GettingStartedLayout.panelRadius, style: .continuous)
                .strokeBorder(CurfewTheme.border)
        )
    }
}

extension Font {
    /// Rounded headline for step titles; scales with the system text size.
    static var setupHeading: Font {
        .system(.title, design: .rounded, weight: .bold)
    }

    static var setupRowTitle: Font {
        .system(.headline, design: .rounded, weight: .semibold)
    }
}
