import CurfewAtmosphere
import SwiftUI

/// Sizes and spacing for setup. The radii and spacing steps follow the launch
/// spec (8 for controls, 20 for panels, capsule for floating buttons; spacing
/// 4, 8, 12, 16, 24, 40, 64).
enum GettingStartedLayout {
    static let controlRadius: CGFloat = 8
    static let panelRadius: CGFloat = 20
    static let spacing4: CGFloat = 4
    static let spacing8: CGFloat = 8
    static let spacing12: CGFloat = 12
    static let spacing16: CGFloat = 16
    static let spacing24: CGFloat = 24
    static let spacing40: CGFloat = 40

    /// The smallest frame every screen fits in at the default text size.
    static let contentMinimum = CGSize(width: 720, height: 520)
    /// The window opens at exactly the size its content needs.
    static let windowSize = contentMinimum
}

/// Colours setup uses over the sky.
enum GettingStartedPalette {
    /// The floating drag panel and the lock preview sit over other apps, so
    /// they keep the night palette in both appearances.
    static let panelSurface = Color.black.opacity(0.88)
    static let panelText = AtmospherePalette.warmWhite
    static let panelMutedText = AtmospherePalette.warmWhite.opacity(0.72)

    /// Warm white, the one ink over setup's sky.
    static let ink = AtmospherePalette.warmWhite
    /// The primary button's fill, dark enough for its own label
    /// (`SetupSkyContrastTests` checks the same value, `SetupSky.primaryFill`).
    static let primaryFill = SundownPalette.emberDeep
}

/// Sizes for one setup window, from the prototype's proportions. Every screen
/// shares the same four places, top to bottom: the mark, the heading, the
/// content and the buttons. Their heights are fixed here so nothing moves when
/// one screen replaces another.
struct SetupMetrics: Equatable {
    var headline: CGFloat
    var numeral: CGFloat
    var body: CGFloat
    var small: CGFloat
    var button: CGFloat
    /// The mark above the heading. Only the welcome fills it.
    var markSlot: CGFloat
    /// One line of heading. A second line grows down into the content.
    var headlineSlot: CGFloat
    /// The row of buttons, in the same place on every screen.
    var actionSlot: CGFloat
    /// The height of the band all of setup's text sits in.
    var bandHeight: CGFloat

    static func window(_ size: CGSize) -> SetupMetrics {
        // Scale with whichever side is tighter, so a wide window does not
        // outgrow the band its text must stay inside.
        let unit = min(size.width, size.height * 720 / 520) / 720
        let headline = (32 * unit).rounded()
        return SetupMetrics(
            headline: headline,
            numeral: (84 * unit).rounded(),
            body: max(15, (17 * unit).rounded()),
            small: max(13, (14 * unit).rounded()),
            button: max(15, (16 * unit).rounded()),
            markSlot: (28 * unit).rounded(),
            headlineSlot: (headline * 1.3).rounded(),
            actionSlot: max(44, (44 * unit).rounded()),
            bandHeight: size.height * SetupSky.textBand.height
        )
    }
}

extension EnvironmentValues {
    @Entry var setupMetrics = SetupMetrics.window(GettingStartedLayout.windowSize)
}

/// A screen leaving: quickly up and out of focus.
private struct SetupLeave: ViewModifier {
    var isLeaving: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isLeaving ? 0 : 1)
            .offset(y: isLeaving ? -12 : 0)
            .blur(radius: isLeaving ? 5 : 0)
    }
}

/// A caption arriving: up from below, into focus.
private struct SetupRise: ViewModifier {
    var isBelow: Bool

    func body(content: Content) -> some View {
        content
            .opacity(isBelow ? 0 : 1)
            .offset(y: isBelow ? 14 : 0)
            .blur(radius: isBelow ? 6 : 0)
    }
}

extension AnyTransition {
    /// Something arriving in one of the scaffold's places: the old content
    /// leaves at once, the new rises in after `delay`.
    static func setupArrival(delay: Double, animates: Bool) -> AnyTransition {
        guard animates else { return .opacity }
        return .asymmetric(
            insertion: .modifier(
                active: SetupRise(isBelow: true), identity: SetupRise(isBelow: false)
            )
            .animation(.spring(duration: 0.75, bounce: 0.12).delay(delay)),
            removal: .modifier(
                active: SetupLeave(isLeaving: true), identity: SetupLeave(isLeaving: false)
            )
            .animation(.easeIn(duration: 0.22))
        )
    }
}

/// The sky behind every setup screen, drawn from the story. It is always the
/// standard palette: the contrast of setup's text is proven against it.
struct SetupSkyBackdrop: View {
    var story: SetupSkyStory
    /// When the welcome's day began playing, while it plays.
    var introStart: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: reduceMotion)) { context in
            let minute = introStart.map {
                SetupSky.Intro.minute(at: context.date.timeIntervalSince($0))
            } ?? story.minute(at: context.date)
            GeometryReader { proxy in
                HorizonSkyView(
                    frame: SetupSky.frame(at: minute, moonDate: context.date),
                    isDayRunning: true
                )
                .frame(width: proxy.size.width, height: proxy.size.height * SetupSky.heightScale)
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                .clipped()
            }
        }
        .environment(\.horizonPalette, .standard)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// The one primary action on a screen: an ember capsule.
struct GettingStartedPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.setupMetrics) private var metrics

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sundownFont(.button, size: metrics.button)
            .padding(.horizontal, GettingStartedLayout.spacing24)
            .frame(minHeight: 40)
            .foregroundStyle(GettingStartedPalette.ink)
            .background(GettingStartedPalette.primaryFill, in: Capsule())
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Every other action: a capsule of darkened sky with a fine edge. The fill
/// only ever darkens what is behind the label, so the label keeps the contrast
/// the sky already gives it. The closing offer's three actions all use it, so
/// declining weighs the same as accepting.
struct GettingStartedSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.setupMetrics) private var metrics
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .sundownFont(.button, size: compact ? metrics.small : metrics.button)
            .padding(
                .horizontal,
                compact ? GettingStartedLayout.spacing12 : GettingStartedLayout.spacing24
            )
            .frame(minHeight: compact ? 28 : 40)
            .foregroundStyle(GettingStartedPalette.ink)
            .background(.black.opacity(configuration.isPressed ? 0.42 : 0.26), in: Capsule())
            .overlay(Capsule().strokeBorder(GettingStartedPalette.ink.opacity(0.32), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// A weekday chip: a toggle drawn as a small rounded control.
struct GettingStartedChipStyle: ToggleStyle {
    @Environment(\.setupMetrics) private var metrics

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: GettingStartedLayout.controlRadius)
        Button {
            configuration.isOn.toggle()
        } label: {
            configuration.label
                .sundownFont(.button, size: metrics.small)
                .frame(minWidth: 40, minHeight: 32)
                .foregroundStyle(
                    configuration.isOn ? SundownPalette.nightSky : GettingStartedPalette.ink
                )
                .background(configuration.isOn ? GettingStartedPalette.ink : .clear, in: shape)
                .overlay(shape.strokeBorder(
                    GettingStartedPalette.ink.opacity(configuration.isOn ? 0 : 0.55),
                    lineWidth: 1.5
                ))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(configuration.isOn ? .isSelected : [])
    }
}

/// The round earlier and later buttons beside a time.
struct GettingStartedStepButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .frame(width: 36, height: 36)
            .foregroundStyle(GettingStartedPalette.ink)
            .background(
                GettingStartedPalette.ink.opacity(configuration.isPressed ? 0.2 : 0),
                in: Circle()
            )
            .overlay(Circle().strokeBorder(GettingStartedPalette.ink.opacity(0.55), lineWidth: 1.5))
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(duration: 0.2, bounce: 0.3), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// A row's or screen's live state, in words with a symbol so colour is never
/// the signal.
struct GettingStartedStatus: View {
    let text: String
    let done: Bool
    @Environment(\.setupMetrics) private var metrics

    var body: some View {
        Label {
            Text(text)
        } icon: {
            if done {
                Image(systemName: "checkmark")
            }
        }
        .sundownFont(.button, size: metrics.small)
        .foregroundStyle(GettingStartedPalette.ink)
    }
}

extension View {
    /// A screen's heading.
    func setupHeadline(_ metrics: SetupMetrics) -> some View {
        sundownFont(.headline, size: metrics.headline)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }

    /// A sentence under a heading.
    func setupBody(_ size: CGFloat) -> some View {
        sundownFont(.body, size: size)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}
