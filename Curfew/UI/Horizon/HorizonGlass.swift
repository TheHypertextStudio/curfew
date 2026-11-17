import CurfewAtmosphere
import SwiftUI

/// How a glass surface draws for the current accessibility settings. System
/// Liquid Glass by default; Reduce Transparency gives a solid panel; Increase
/// Contrast adds an outline either way.
struct HorizonGlassLook: Equatable {
    let usesSystemGlass: Bool
    let drawsOutline: Bool

    static func resolve(reduceTransparency: Bool, increaseContrast: Bool) -> HorizonGlassLook {
        HorizonGlassLook(usesSystemGlass: !reduceTransparency, drawsOutline: increaseContrast)
    }

    /// The solid stand-in for glass over the sky: the night ramp's second stop,
    /// dark enough for warm white text at any time of day. Sundown's; views
    /// use ``solidFill(_:)`` with the theme's palette.
    static let solidFill = SundownPalette.nightPanel

    /// The solid stand-in for glass in `palette`: its night's second stop.
    static func solidFill(_ palette: HorizonPalette) -> Color {
        let stop = palette.night[1]
        return AtmospherePalette.solidBackground(red: stop.red, green: stop.green, blue: stop.blue)
    }

    static let outline = SundownPalette.warmWhite.opacity(0.7)
}

extension View {
    /// Glass behind this view in `shape`, resolved for accessibility. Used by
    /// the Horizon controls; `prominent` tints the glass ember.
    @ViewBuilder
    func horizonGlassBackground(
        in shape: some Shape, look: HorizonGlassLook, prominent: Bool = false,
        interactive: Bool = true
    ) -> some View {
        let tint: Color? = prominent ? CurfewTheme.accentFill : nil
        Group {
            if look.usesSystemGlass {
                glassEffect(.regular.tint(tint).interactive(interactive), in: shape)
            } else if prominent {
                background(CurfewTheme.accentFill, in: shape)
            } else {
                background { HorizonSolidPanel(shape: shape) }
            }
        }
        .overlay {
            if look.drawsOutline {
                shape.stroke(HorizonGlassLook.outline, lineWidth: 1)
            }
        }
        .foregroundStyle(SundownPalette.warmWhite)
    }

    /// A glass panel for content that floats over the sky. Solid under Reduce
    /// Transparency, outlined under Increase Contrast.
    func horizonGlassPanel(cornerRadius: CGFloat = CurfewRadius.panel) -> some View {
        horizonGlass(in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// Non-interactive glass in any shape, resolved from the environment's
    /// accessibility settings.
    func horizonGlass(in shape: some Shape) -> some View {
        modifier(HorizonGlassSurface(shape: shape))
    }
}

/// The solid panel under Reduce Transparency, in the theme's palette.
private struct HorizonSolidPanel<S: Shape>: View {
    let shape: S
    @Environment(\.horizonPalette) private var palette

    var body: some View {
        shape.fill(HorizonGlassLook.solidFill(palette))
    }
}

private struct HorizonGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.horizonGlassBackground(
            in: shape,
            look: HorizonGlassLook.resolve(
                reduceTransparency: reduceTransparency, increaseContrast: contrast == .increased
            ),
            interactive: false
        )
    }
}

/// The system glass button styles, with Curfew's type and the defined
/// Reduce Transparency and Increase Contrast behaviour. Floating buttons are
/// capsules.
struct HorizonGlassButtonStyle: PrimitiveButtonStyle {
    var prominent = false
    @Environment(\.horizonPalette) private var palette
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func makeBody(configuration: Configuration) -> some View {
        let look = HorizonGlassLook.resolve(
            reduceTransparency: reduceTransparency, increaseContrast: contrast == .increased
        )
        Group {
            if look.usesSystemGlass {
                if prominent {
                    Button(configuration).buttonStyle(.glassProminent).tint(CurfewTheme.accentFill)
                } else {
                    Button(configuration).buttonStyle(.glass)
                }
            } else {
                Button(configuration)
                    .buttonStyle(.plain)
                    .padding(.horizontal, CurfewSpacing.large)
                    .padding(.vertical, CurfewSpacing.small)
                    .background(
                        prominent ? CurfewTheme.accentFill : HorizonGlassLook.solidFill(palette),
                        in: Capsule()
                    )
                    .foregroundStyle(SundownPalette.warmWhite)
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
        .sundownFont(.button, size: 15)
        .overlay {
            if look.drawsOutline {
                Capsule().stroke(HorizonGlassLook.outline, lineWidth: 1)
            }
        }
    }
}

extension PrimitiveButtonStyle where Self == HorizonGlassButtonStyle {
    /// A glass capsule floating over the sky.
    static var horizonGlass: HorizonGlassButtonStyle {
        HorizonGlassButtonStyle()
    }

    /// The one primary glass action, tinted ember.
    static var horizonGlassProminent: HorizonGlassButtonStyle {
        HorizonGlassButtonStyle(prominent: true)
    }
}
