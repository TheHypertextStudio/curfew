import CurfewAtmosphere
import CurfewKit
import SwiftUI

/// What the lock says right now, from the restriction status and the voice
/// pack. Pure, so tests read the words without SwiftUI.
struct LockScreenContent: Equatable {
    let headline: String
    let line: String?
    let symbol: HorizonSymbol
    let isLeadIn: Bool
    /// One sentence for VoiceOver as the lock appears.
    let accessibilitySummary: String

    static func resolve(
        status: RestRestrictionStatus, now: Date, leadMinutes: Int, voice: VoicePack
    ) -> LockScreenContent {
        switch status {
        case .lockedUntil(let unlock):
            let seconds = unlock.timeIntervalSince(now)
            if seconds <= TimeInterval(max(0, leadMinutes)) * 60 {
                let minutes = Int((seconds / 60).rounded(.up))
                return LockScreenContent(
                    headline: voice.leadInHeadline, line: voice.unlocksIn(minutes: minutes),
                    symbol: .sunrise, isLeadIn: true,
                    accessibilitySummary: voice.leadInSummary(minutes: minutes)
                )
            }
            return LockScreenContent(
                headline: voice.lockedHeadline, line: voice.unlocksAt(unlock), symbol: .locked,
                isLeadIn: false, accessibilitySummary: voice.lockedSummary(until: unlock)
            )
        case .stillLocked:
            return LockScreenContent(
                headline: voice.lockedHeadline, line: voice.unlockPassed, symbol: .locked,
                isLeadIn: false, accessibilitySummary: voice.unlockPassed
            )
        case .unknown:
            return LockScreenContent(
                headline: voice.lockedHeadline, line: voice.unlockUnknown, symbol: .locked,
                isLeadIn: false, accessibilitySummary: voice.unlockUnknown
            )
        case .released:
            return LockScreenContent(
                headline: voice.released, line: nil, symbol: .override, isLeadIn: false,
                accessibilitySummary: voice.released
            )
        }
    }
}

/// Accessibility-driven visual tuning for the lock screen.
struct LockoutVisualConfiguration: Equatable {
    /// When `false`, moves are replaced by short fades.
    var animateBackground: Bool
    /// When `true`, translucent panels switch to solid fills.
    var usesSolidPanels: Bool

    static func resolve(
        reduceMotion: Bool,
        reduceTransparency: Bool
    ) -> LockoutVisualConfiguration {
        LockoutVisualConfiguration(
            animateBackground: !reduceMotion,
            usesSolidPanels: reduceTransparency
        )
    }
}

/// The clock's numerals and day period, split so the period can sit small
/// beside the numerals as in the prototype.
enum LockClockText {
    static func numerals(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle.dateTime.hour(.defaultDigits(amPM: .omitted))
            .minute(.twoDigits)
        style.locale = locale
        return date.formatted(style)
    }

    static func period(_ date: Date, locale: Locale = .autoupdatingCurrent) -> String? {
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? ""
        guard template.contains("a") else { return nil }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "a"
        return formatter.string(from: date)
    }
}

/// The lock, laid out like the prototype's `lock` phase: the clock centred
/// in the sky, "That's the day." under it, the unlock line with the lock
/// symbol, and one quiet text button on the ground, "Need to get back in?".
/// Opening the override composer or the evening close-out lifts the clock
/// and makes room on the same scene.
struct LockoutScreenView: View {
    @Environment(CurfewAppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AccessibilityFocusState private var clockFocused: Bool

    var scene: LockScene?
    /// The instant the scene is drawn for; the timeline's progress reads it.
    var date: Date
    /// A still lock for the theme editor: its own clock and unlock, nothing
    /// pressable, nothing announced.
    var preview: RestScreenPreview?

    /// The active voice: the chosen pack with the person's own words.
    private var voice: VoicePack {
        model.voice
    }

    private var now: Date {
        preview?.now ?? model.currentTime
    }

    private var content: LockScreenContent {
        LockScreenContent.resolve(
            status: preview.map { .lockedUntil($0.unlock) } ?? model.restRestrictionStatus,
            now: now,
            leadMinutes: model.restAppearance.sunriseLeadMinutes, voice: voice
        )
    }

    private var isCompact: Bool {
        preview == nil
            && (model.isOverrideComposerVisible || model.reflectionState.isEveningReflectionPending)
    }

    private var clockDesign: Font.Design {
        model.restAppearance.clockStyle.fontDesign
    }

    private var clockProgress: Double {
        scene?.timeline.clock(at: date) ?? 1
    }

    private var wordsProgress: Double {
        scene?.timeline.words(at: date) ?? 1
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let layout = textLayout(in: size)
            ZStack(alignment: .topLeading) {
                textBlock(layout)
                    .frame(width: layout.block.width, height: layout.block.height)
                    .position(x: layout.block.midX, y: layout.block.midY)
                if isCompact {
                    let below = max(0, size.height - layout.block.maxY)
                    ScrollView {
                        panel
                            .padding(.vertical, CurfewSpacing.xLarge)
                            .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(width: size.width, height: below)
                    .position(x: size.width / 2, y: layout.block.maxY + below / 2)
                    .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 12)))
                } else {
                    supporting(width: size.width)
                        .frame(width: size.width)
                        .position(x: size.width / 2, y: layout.block.maxY + CurfewSpacing.xLarge)
                        .opacity(wordsProgress)
                    ground
                        .position(x: size.width / 2, y: size.height * 0.85)
                        .opacity(wordsProgress)
                }
            }
            .frame(width: size.width, height: size.height)
            .animation(.smooth(duration: reduceMotion ? 0.2 : 0.6), value: isCompact)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(content.accessibilitySummary)
        .accessibilityIdentifier("lockout-screen")
        .onAppear(perform: announce)
    }

    // MARK: Clock and words

    private func textLayout(in size: CGSize) -> LockTextLayout {
        LockTextLayout.resolve(
            size: size,
            content: LockTextContent(
                clock: LockClockText.numerals(now),
                period: LockClockText.period(now),
                headline: content.headline, line: content.line
            ),
            compact: isCompact
        )
    }

    /// The clock, headline and unlock line, each held to its slot so the
    /// block's frame is exactly what is drawn.
    private func textBlock(_ layout: LockTextLayout) -> some View {
        VStack(spacing: 0) {
            clock(layout)
                .frame(height: layout.clockHeight)
            Color.clear.frame(height: layout.clockGap)
            Text(content.headline)
                .font(.system(size: layout.headlineSize, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.opacity)
                .frame(height: layout.headlineHeight)
                .opacity(wordsProgress)
            if layout.lineHeight > 0, let line = content.line {
                Color.clear.frame(height: layout.lineGap)
                Label {
                    Text(line)
                } icon: {
                    content.symbol.image
                }
                .font(.system(size: layout.lineSize, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .contentTransition(.opacity)
                .frame(height: layout.lineHeight)
                .opacity(wordsProgress)
                .accessibilityIdentifier("lockout-unlock-line")
            }
        }
        .frame(width: layout.block.width)
        .foregroundStyle(SundownPalette.warmWhite)
        .animation(.easeInOut(duration: 0.6), value: content.headline)
    }

    private func clock(_ layout: LockTextLayout) -> some View {
        let numerals = LockClockText.numerals(now)
        var text = Text(numerals)
            .font(.system(size: layout.clockSize, weight: .semibold, design: clockDesign))
        if let period = LockClockText.period(now) {
            text = text + Text(" ") + Text(period)
                .font(.system(
                    size: layout.clockSize * 0.28, weight: .semibold, design: clockDesign
                ))
                .foregroundStyle(SundownPalette.warmWhite.opacity(0.85))
        }
        return text
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .contentTransition(.numericText())
            .scaleEffect(0.9 + 0.1 * clockProgress)
            .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: numerals)
            .accessibilityLabel(now.formatted(date: .omitted, time: .shortened))
            .accessibilityAddTraits(.isStaticText)
            .accessibilityFocused($clockFocused)
            .accessibilityIdentifier("rest-clock")
    }

    /// Any shutdown notice, under the block. The person's own words are the
    /// headline itself.
    private func supporting(width: CGFloat) -> some View {
        let size = max(13, width * 0.014)
        return VStack(spacing: CurfewSpacing.small) {
            if preview == nil, let shutdown = model.shutdownStatusLine {
                Text(shutdown)
            }
        }
        .font(.system(size: size))
        .foregroundStyle(SundownPalette.supportingText)
    }

    // MARK: Ground

    private var ground: some View {
        HStack(spacing: CurfewSpacing.xLarge) {
            if preview != nil {
                QuietLockButton(title: voice.overrideEntry, symbol: .override) {}
                    .allowsHitTesting(false)
            } else if model.isEnforcingLockout {
                if model.overridesRemaining == 0 {
                    Text(voice.noOverridesLeft)
                        .foregroundStyle(SundownPalette.supportingText)
                } else {
                    QuietLockButton(title: voice.overrideEntry, symbol: .override) {
                        model.beginOverrideRequest()
                    }
                    .accessibilityIdentifier("override-entry")
                }
            }
            if preview == nil {
                RestSaverControl()
            }
        }
        .font(.system(size: 15, weight: .medium))
    }

    @ViewBuilder
    private var panel: some View {
        if model.isOverrideComposerVisible, model.isEnforcingLockout {
            OverrideComposer()
        } else if model.reflectionState.isEveningReflectionPending {
            EveningReflectionCard(usesSolidPanels: reduceTransparency)
        }
    }

    private func announce() {
        guard preview == nil, model.isEnforcingLockout else { return }
        AccessibilityNotification.Announcement(content.accessibilitySummary).post()
        clockFocused = true
    }
}

/// The surface under panels that float over the sky or the desktop: system
/// glass tinted toward night so warm white text reads over any wallpaper,
/// a solid night panel under Reduce Transparency, and an outline under
/// Increase Contrast.
struct NightPanelSurface: ViewModifier {
    var cornerRadius = CurfewRadius.panel
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.horizonPalette) private var palette

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let fill = HorizonGlassLook.solidFill(palette)
        Group {
            if reduceTransparency {
                content.background(fill.opacity(0.94), in: shape)
            } else {
                // The glass sits behind the panel rather than around it, so
                // a click still reaches the close-out's text field and gives
                // it keyboard focus.
                content.background {
                    Color.clear.glassEffect(.regular.tint(fill.opacity(0.55)), in: shape)
                }
            }
        }
        .overlay {
            if contrast == .increased {
                shape.stroke(HorizonGlassLook.outline, lineWidth: 1)
            }
        }
    }
}

extension View {
    func nightPanel(cornerRadius: CGFloat = CurfewRadius.panel) -> some View {
        modifier(NightPanelSurface(cornerRadius: cornerRadius))
    }
}

/// The lock's one kind of secondary control: quiet text over the ground, led
/// by a symbol. Not glass; it does not compete with the clock.
struct QuietLockButton: View {
    let title: String
    let symbol: HorizonSymbol
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                symbol.image
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(SundownPalette.warmWhite.opacity(0.78))
        .contentShape(Rectangle())
    }
}
