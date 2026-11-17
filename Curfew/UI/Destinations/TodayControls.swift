import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// The two Today actions in one glass container, or the single "Turn on
/// Curfew" when Curfew is off.
struct TodayActions: View {
    var presentation: TodayPresentation
    var voice: TodayVoice
    var holdDuration: TimeInterval
    var stacked: Bool
    var onTurnOn: () -> Void
    var onMoreTime: () -> Void
    var onCallItADay: () -> Void

    var body: some View {
        GlassEffectContainer(spacing: CurfewSpacing.medium) {
            let layout = stacked
                ? AnyLayout(VStackLayout(spacing: CurfewSpacing.small))
                : AnyLayout(HStackLayout(spacing: CurfewSpacing.medium))
            layout {
                if let moreTime = presentation.moreTime {
                    MoreTimeButton(
                        moreTime: moreTime, voice: voice, holdDuration: holdDuration,
                        action: onMoreTime
                    )
                }
                if presentation.callsItADay {
                    HoldToConfirmButton(
                        voice.callItADay, holdingLabel: voice.keepHolding, symbol: .curfew,
                        duration: holdDuration, prominent: true, action: onCallItADay
                    )
                    .accessibilityHint("Locks this Mac now, until the scheduled unlock.")
                }
                if presentation.offersTurnOn {
                    Button(voice.turnOn, action: onTurnOn)
                        .buttonStyle(.horizonGlassProminent)
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: presentation.moreTime)
        .animation(.smooth(duration: 0.3), value: presentation.callsItADay)
    }
}

/// "15 more minutes": hold to confirm. The count of extensions left shows
/// only while holding; "Added" confirms; with none left it says so and does
/// nothing.
struct MoreTimeButton: View {
    var moreTime: TodayPresentation.MoreTime
    var voice: TodayVoice
    var holdDuration: TimeInterval
    var action: () -> Void
    @State private var justAdded = false

    var body: some View {
        switch moreTime {
        case .available(let left):
            HoldToConfirmButton(
                justAdded ? voice.added : voice.moreTime,
                holdingLabel: voice.keepHolding(extensionsLeft: left),
                symbol: .moreTime, duration: holdDuration
            ) {
                action()
                justAdded = true
            }
            .accessibilityHint("Moves curfew 15 minutes later. \(left) left this week.")
            .task(id: justAdded) {
                guard justAdded else { return }
                try? await Task.sleep(for: .seconds(1.6))
                justAdded = false
            }
        case .exhausted:
            HoldToConfirmButton(
                voice.noExtensionsLeft, holdingLabel: voice.noExtensionsLeft,
                symbol: .moreTime, duration: holdDuration
            ) {}
                .disabled(true)
        }
    }
}

/// The one thing on the ground: a circle to tick, or "What is today for?" as
/// a field when the morning has not named one. Long text wraps to two lines.
struct OneThingView: View {
    var oneThing: TodayOneThing?
    var size: CGFloat
    var voice: TodayVoice
    var onDone: (Bool) -> Void
    var onSave: (String) -> Bool
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        if let oneThing {
            Button { onDone(!oneThing.isDone) } label: {
                HStack(alignment: .firstTextBaseline, spacing: size * 0.5) {
                    Image(systemName: oneThing.isDone
                        ? HorizonSymbol.oneThingDone.systemName : HorizonSymbol.oneThing.systemName)
                        .contentTransition(.symbolEffect(.replace))
                    Text(oneThing.text)
                        .strikethrough(oneThing.isDone)
                        .opacity(oneThing.isDone ? 0.6 : 1)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .sundownFont(.title, size: size)
                .foregroundStyle(SundownPalette.warmWhite)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .animation(.smooth(duration: 0.3), value: oneThing.isDone)
            .accessibilityLabel(oneThing.text)
            .accessibilityValue(oneThing.isDone ? "Done" : "Not done")
            .accessibilityHint(oneThing.isDone ? "Marks it not done." : "Marks it done.")
        } else {
            TextField(
                voice.oneThingQuestion, text: $draft,
                prompt: Text(voice.oneThingQuestion)
                    .foregroundStyle(SundownPalette.warmWhite.opacity(0.66))
            )
            .textFieldStyle(.plain)
            .focused($fieldFocused)
            .sundownFont(.title, size: size)
            .foregroundStyle(SundownPalette.warmWhite)
            .multilineTextAlignment(.center)
            .padding(.bottom, CurfewSpacing.small)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SundownPalette.warmWhite.opacity(fieldFocused ? 0.85 : 0.5))
                    .frame(height: 1.5)
            }
            .onSubmit {
                if onSave(draft) {
                    draft = ""
                }
            }
            .frame(maxWidth: 420)
            .accessibilityLabel(voice.oneThingQuestion)
            .accessibilityHint("Press Return to save it as today's one thing.")
        }
    }
}

/// Keeps text over the sky readable from noon to last light without a scrim:
/// a tight halo in the moment's ground colour hugs each glyph, so the light
/// text always meets a dark edge however bright the band behind it is.
/// ``TodaySkyLegibility`` models it and its test proves the contrast over
/// the palette.
private struct SkyInk: ViewModifier {
    var frame: HorizonFrame
    var isActive: Bool

    func body(content: Content) -> some View {
        let ground = TodaySkyLegibility.halo(for: frame)
        let color = isActive
            ? AtmospherePalette.solidBackground(
                red: ground.red, green: ground.green, blue: ground.blue
            ) : .clear
        content
            .shadow(color: color.opacity(TodaySkyLegibility.haloOpacity), radius: 1)
            .shadow(color: color.opacity(TodaySkyLegibility.haloOpacity), radius: 3)
    }
}

extension View {
    /// Text over the sky, kept legible on every band by a tight ground halo.
    func skyInk(_ frame: HorizonFrame, isActive: Bool = true) -> some View {
        modifier(SkyInk(frame: frame, isActive: isActive))
    }
}

/// The legibility model for text over the sky. The halo is two stacked
/// shadows of `haloOpacity`; at a glyph's edge each lays down at least half
/// its opacity, so the edge carries `haloEdgeDensity` of the ground colour.
enum TodaySkyLegibility {
    static let haloOpacity = 0.85
    static var haloEdgeDensity: Double {
        1 - pow(1 - haloOpacity / 2, 2)
    }

    /// The halo colour: the flat ground of the moment, so it reads as part of
    /// the scene rather than a shadow.
    static func halo(for frame: HorizonFrame) -> HorizonRGB {
        HorizonPalette.ground(elevation: frame.elevation)
    }

    /// The colour at a glyph's edge: the sky under the halo's edge density.
    static func edge(over sky: HorizonRGB, frame: HorizonFrame) -> HorizonRGB {
        let halo = halo(for: frame)
        let density = haloEdgeDensity
        return HorizonRGB(
            sky.red + (halo.red - sky.red) * density,
            sky.green + (halo.green - sky.green) * density,
            sky.blue + (halo.blue - sky.blue) * density
        )
    }

    /// WCAG contrast ratio between two sRGB colours.
    static func contrast(_ first: HorizonRGB, _ second: HorizonRGB) -> Double {
        func channel(_ value: Double) -> Double {
            let clamped = min(max(value, 0), 1)
            return clamped <= 0.04045 ? clamped / 12.92 : pow((clamped + 0.055) / 1.055, 2.4)
        }
        func luminance(_ color: HorizonRGB) -> Double {
            0.2126 * channel(color.red) + 0.7152 * channel(color.green)
                + 0.0722 * channel(color.blue)
        }
        let one = luminance(first)
        let two = luminance(second)
        return (max(one, two) + 0.05) / (min(one, two) + 0.05)
    }

    /// Warm white, the ink over the sky.
    static let ink = HorizonRGB(0.99, 0.97, 0.94)
}

/// The Accessibility health banner as the setup flow defines it, on its own
/// paper so it reads the same over the sky as it did over the page.
struct TodayHealthBanner: View {
    var showWarning: Bool
    var showGranted: Bool
    var onResolve: () -> Void

    var body: some View {
        Group {
            if showGranted {
                HStack(spacing: 11) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CurfewTheme.accent)
                    Text("Accessibility access granted.")
                        .font(SundownType.body(14))
                        .foregroundStyle(CurfewTheme.ink)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(CurfewTheme.surfaceMuted, in: .rect(cornerRadius: 12))
                .transition(.opacity)
            } else if showWarning {
                HStack(spacing: 11) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(CurfewTheme.warning)
                    Text("Curfew needs Accessibility access to block bypass shortcuts "
                        + "during lockout.")
                        .font(SundownType.body(14))
                        .foregroundStyle(CurfewTheme.ink)
                    Spacer(minLength: 12)
                    Button("Grant Access", action: onResolve)
                        .buttonStyle(.plain)
                        .font(SundownType.title(14))
                        .foregroundStyle(CurfewTheme.accent)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(CurfewTheme.warning.opacity(0.13), in: .rect(cornerRadius: 12))
                .background(CurfewTheme.canvas, in: .rect(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 22)
    }
}
