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
    var voice = VoicePack.standard
    /// The instant the scene is drawn for; the timeline's progress reads it.
    var date: Date

    private var content: LockScreenContent {
        LockScreenContent.resolve(
            status: model.restRestrictionStatus, now: model.currentTime,
            leadMinutes: model.restAppearance.sunriseLeadMinutes, voice: voice
        )
    }

    private var isCompact: Bool {
        model.isOverrideComposerVisible || model.reflectionState.isEveningReflectionPending
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
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    clock(in: size)
                        .padding(.top, size.height * (isCompact ? 0.07 : 0.2))
                    words(in: size)
                        .padding(.top, size.height * (isCompact ? 0.01 : 0.035))
                    if isCompact {
                        ScrollView {
                            panel
                                .padding(.vertical, CurfewSpacing.xLarge)
                                .frame(maxWidth: .infinity)
                        }
                        .scrollIndicators(.hidden)
                        .scrollBounceBehavior(.basedOnSize)
                        .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 12)))
                    }
                    Spacer(minLength: 0)
                }
                .frame(width: size.width)
                if !isCompact {
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

    private func clock(in size: CGSize) -> some View {
        let full = min(size.width * 0.15, size.height * 0.26)
        let fontSize = isCompact ? full * 0.32 : full
        let numerals = LockClockText.numerals(model.currentTime)
        return HStack(alignment: .firstTextBaseline, spacing: fontSize * 0.04) {
            Text(numerals)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let period = LockClockText.period(model.currentTime) {
                Text(period)
                    .font(.system(size: fontSize * 0.28, weight: .semibold, design: .rounded))
                    .opacity(0.85)
            }
        }
        .foregroundStyle(SundownPalette.warmWhite)
        .scaleEffect(0.9 + 0.1 * clockProgress)
        .animation(reduceMotion ? nil : .snappy(duration: 0.28), value: numerals)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.currentTime.formatted(date: .omitted, time: .shortened))
        .accessibilityFocused($clockFocused)
        .accessibilityIdentifier("rest-clock")
    }

    private func words(in size: CGSize) -> some View {
        let headlineSize = min(size.width * 0.042, size.height * 0.075)
        let lineSize = max(15, size.width * 0.0175)
        return VStack(spacing: isCompact ? CurfewSpacing.small : size.height * 0.035) {
            Text(content.headline)
                .font(.system(
                    size: isCompact ? headlineSize * 0.7 : headlineSize,
                    weight: .semibold, design: .rounded
                ))
                .multilineTextAlignment(.center)
                .contentTransition(.opacity)
            if let line = content.line, !isCompact {
                Label {
                    Text(line)
                } icon: {
                    content.symbol.image
                }
                .font(.system(size: lineSize, weight: .medium))
                .contentTransition(.opacity)
                .accessibilityIdentifier("lockout-unlock-line")
            }
            if !model.restAppearance.message.isEmpty, !isCompact {
                Text(model.restAppearance.message)
                    .font(.system(size: max(13, lineSize * 0.8)))
                    .foregroundStyle(SundownPalette.supportingText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 600)
            }
            if let shutdown = model.shutdownStatusLine, !isCompact {
                Text(shutdown)
                    .font(.system(size: max(13, lineSize * 0.75)))
                    .foregroundStyle(SundownPalette.supportingText)
            }
        }
        .foregroundStyle(SundownPalette.warmWhite)
        .opacity(wordsProgress)
        .offset(y: (1 - wordsProgress) * (reduceMotion ? 0 : 10))
        .animation(.easeInOut(duration: 0.6), value: content.headline)
    }

    // MARK: Ground

    private var ground: some View {
        HStack(spacing: CurfewSpacing.xLarge) {
            if model.isEnforcingLockout {
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
            RestSaverControl()
        }
        .font(.system(size: 15, weight: .medium))
    }

    @ViewBuilder
    private var panel: some View {
        if model.isOverrideComposerVisible, model.isEnforcingLockout {
            OverrideComposer(voice: voice)
        } else if model.reflectionState.isEveningReflectionPending {
            EveningReflectionCard(
                voice: voice, usesSolidPanels: reduceTransparency
            )
        }
    }

    private func announce() {
        guard model.isEnforcingLockout else { return }
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

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Group {
            if reduceTransparency {
                content.background(HorizonGlassLook.solidFill.opacity(0.94), in: shape)
            } else {
                content.glassEffect(
                    .regular.tint(HorizonGlassLook.solidFill.opacity(0.55)),
                    in: shape
                )
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
