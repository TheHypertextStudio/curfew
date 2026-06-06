import EventKit
import SwiftUI

/// Builds the single VoiceOver summary string read aloud when the
/// lockout overlay appears. Centralised so tests can verify the copy
/// without instantiating SwiftUI.
enum LockoutAccessibilityCopy {
    /// Combines the lockout message and optional unlock time into a
    /// single screen-reader sentence. Falls back to "Unlock time
    /// unavailable." when `unlockLine` is `nil` (schedule error).
    static func summary(message: String, unlockLine: String?) -> String {
        let unlockPortion = unlockLine ?? "Unlock time unavailable."
        return "Curfew lockout active. \(message). \(unlockPortion)"
    }
}

/// Accessibility-driven visual tuning for the lockout screen.
/// Evaluates the user's Reduce Motion / Reduce Transparency preferences
/// once per render; the struct is pure data so tests can assert the
/// mapping without touching SwiftUI environment.
struct LockoutVisualConfiguration: Equatable {
    /// When `false`, the slow gradient animation is disabled.
    var animateBackground: Bool
    /// When `true`, semi-transparent panels switch to solid fills so
    /// content remains legible for users who can't parse translucency.
    var usesSolidPanels: Bool

    /// Derives a configuration from the two accessibility environment
    /// values. Kept as a pure static so `LockoutBackgroundView` and the
    /// body rendering path can share the same resolution logic.
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

/// Full-screen overlay rendered on every display during the lockout
/// phase. Shows the current time, the lockout message, the unlock time,
/// optional calendar context (Pro), and the Convince Me override flow.
struct LockoutScreenView: View {
    @EnvironmentObject private var model: CurfewAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// The user-facing message body — varies by trigger (wall time vs.
    /// hours exhausted vs. combined). Formatted by the app model.
    let message: String

    private var visualConfiguration: LockoutVisualConfiguration {
        LockoutVisualConfiguration.resolve(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency
        )
    }

    private var unlockLine: String? {
        guard let unlockDate = model.state.unlockDate else {
            return nil
        }
        return "Your computer unlocks at \(unlockDate.formatted(date: .omitted, time: .shortened))"
    }

    private var accessibilitySummary: String {
        LockoutAccessibilityCopy.summary(message: message, unlockLine: unlockLine)
    }

    /// Full-screen lockout UI — animated gradient background with the
    /// time, message, unlock info, optional calendar pill, and the
    /// Convince Me flow stacked centrally.
    var body: some View {
        ZStack {
            LockoutBackgroundView(animate: visualConfiguration.animateBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text(model.currentTime, style: .time)
                    .font(.system(size: 104, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3), radius: 28, y: 10)

                Text(message)
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 760)

                if let unlockLine {
                    Text(unlockLine)
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.75))
                }

                if let shutdownStatusLine = model.shutdownStatusLine {
                    Text(shutdownStatusLine)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                }

                // Calendar strip: next event and current event, Pro-gated.
                if model.featureFlags.calendarEnabled, model.licenseGate.isProUnlocked {
                    calendarStrip
                }

                VStack(spacing: 10) {
                    if model.overrideCooldownRemaining > 0 {
                        Text("Unlock available in \(model.overrideCooldownRemaining)s")
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    if model.isOverrideComposerVisible {
                        TextEditor(text: $model.overrideReasonDraft)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .frame(width: 420, height: 120)
                            .padding(8)
                            .background(
                                visualConfiguration.usesSolidPanels
                                    ? Color.black.opacity(0.72)
                                    : Color.black.opacity(0.25)
                            )
                            .cornerRadius(12)

                        Text(
                            "Minimum \(OverrideRequestPolicy.minimumJustificationCharacters) characters"
                        )
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))

                        Button(
                            "Hold for 3s to unlock for \(model.settings.overrideDurationMinutes) min"
                        ) {}
                            .buttonStyle(.borderedProminent)
                            .disabled(!model.canConfirmOverride)
                            .simultaneousGesture(
                                LongPressGesture(
                                    minimumDuration: OverrideRequestPolicy.confirmationHoldSeconds
                                )
                                .onEnded { _ in
                                    model.confirmOverride()
                                }
                            )
                    } else {
                        Button(OverrideRequestPolicy.entryPrompt) {
                            model.beginOverrideRequest()
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.white.opacity(0.45))
                    }
                }
                .padding(.top, 24)
            }
            .padding(40)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    /// Compact pill strip showing the currently-running meeting or next
    /// upcoming event today. Visibility is pre-gated at the call site.
    @ViewBuilder
    private var calendarStrip: some View {
        if model.calendarMonitor.hasCurrentEvent,
           let event = model.calendarMonitor.todayEvents.first(where: {
               guard let start = $0.startDate, let end = $0.endDate else { return false }
               return start <= Date() && end > Date()
           }) {
            calendarPill(
                label: "In progress",
                title: event.title ?? "Meeting",
                end: event.endDate
            )
        } else if let next = model.calendarMonitor.nextEvent {
            calendarPill(
                label: "Up next",
                title: next.title ?? "Meeting",
                end: next.startDate
            )
        }
    }

    private func calendarPill(label: String, title: String, end: Date?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 12, weight: .medium))
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .tracking(0.5)
            Text(title)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .lineLimit(1)
            if let end {
                Text("until \(end.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .opacity(0.8)
            }
        }
        .foregroundStyle(.white.opacity(0.7))
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.white.opacity(0.08))
        .clipShape(Capsule())
    }
}

/// Slowly-panning three-stop linear gradient behind the lockout UI.
/// When Reduce Motion is enabled the animation is disabled — the view
/// still renders with the final colours but stops panning.
private struct LockoutBackgroundView: View {
    /// When `false`, the animation is entirely disabled (static gradient).
    let animate: Bool
    /// Drives the start/end-point swap. Flipped on appear to kick off
    /// the repeating animation.
    @State private var animatePhase = false

    /// Sundown night sky — deep dusk with the day's last embers glowing low on
    /// the horizon. The ember bloom breathes gently when motion is allowed.
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.07, green: 0.08, blue: 0.16), location: 0.0),
                    .init(color: Color(red: 0.14, green: 0.13, blue: 0.24), location: 0.45),
                    .init(color: Color(red: 0.28, green: 0.18, blue: 0.28), location: 0.78),
                    .init(color: Color(red: 0.44, green: 0.24, blue: 0.22), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(red: 0.92, green: 0.52, blue: 0.30).opacity(glowOpacity), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 640
            )
            .blendMode(.screen)
        }
        .animation(
            animate
                ? .easeInOut(duration: 8).repeatForever(autoreverses: true)
                : .default,
            value: animatePhase
        )
        .onAppear {
            guard animate else {
                return
            }
            animatePhase = true
        }
    }

    /// Ember-bloom opacity — drifts subtly when motion is allowed.
    private var glowOpacity: Double {
        animate && animatePhase ? 0.55 : 0.45
    }
}
