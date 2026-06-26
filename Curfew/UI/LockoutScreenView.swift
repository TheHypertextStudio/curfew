import CurfewKit
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

    /// Tracks hold-gesture progress (0 → 1) for the confirm-override button.
    @State private var holdProgress: Double = 0

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
            SundownSky(moment: model.skyMoment)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 24)
                centralBeat
                Spacer(minLength: 24)
                overrideSection
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(40)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }

    /// The calm centre of the lockout: the time as protagonist, the message,
    /// and — beneath a thin horizon rule — the unlock time as a quiet promise.
    /// Contextual cards (calendar, the evening reflection) sit below it.
    private var centralBeat: some View {
        VStack(spacing: 22) {
            VStack(spacing: 12) {
                Text(model.currentTime, style: .time)
                    .font(.system(size: 110, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(SundownPalette.warmWhite)
                    .shadow(color: .black.opacity(0.35), radius: 30, y: 12)

                Text(message)
                    .font(.system(size: 26, weight: .medium, design: .rounded))
                    .foregroundStyle(SundownPalette.warmWhite.opacity(0.9))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 720)

                if let unlockLine {
                    VStack(spacing: 10) {
                        Capsule()
                            .fill(SundownPalette.warmWhite.opacity(0.22))
                            .frame(width: 64, height: 1)
                        Text(unlockLine)
                            .font(.system(size: 18, weight: .regular, design: .rounded))
                            .foregroundStyle(SundownPalette.warmWhite.opacity(0.72))
                    }
                    .padding(.top, 4)
                }

                if let shutdownStatusLine = model.shutdownStatusLine {
                    Text(shutdownStatusLine)
                        .font(.system(size: 13, weight: .regular, design: .rounded))
                        .foregroundStyle(SundownPalette.warmWhite.opacity(0.5))
                }
            }

            // Calendar strip: next event and current event, Plus-gated.
            if model.featureFlags.calendarEnabled, model.licenseGate.isPlusUnlocked {
                calendarStrip
            }

            if model.reflectionState.isEveningReflectionPending {
                EveningReflectionCard(usesSolidPanels: visualConfiguration.usesSolidPanels)
                    .environmentObject(model)
                    .padding(.top, 4)
            }
        }
    }

    /// The "Convince Me" override flow, anchored at the bottom and held at low
    /// emphasis until invoked, so it never competes with the central beat.
    private var overrideSection: some View {
        VStack(spacing: 10) {
            if model.isOverrideComposerVisible {
                TextEditor(text: $model.overrideReasonDraft)
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .scrollContentBackground(.hidden)
                    .frame(width: 420, height: 120)
                    .padding(8)
                    .background(
                        visualConfiguration.usesSolidPanels
                            ? Color.black.opacity(0.72)
                            : Color.black.opacity(0.25),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )

                Text(
                    "Minimum \(OverrideRequestPolicy.minimumJustificationCharacters) characters"
                )
                .font(.caption)
                .foregroundStyle(SundownPalette.warmWhite.opacity(0.6))

                let holdDuration = OverrideRequestPolicy.confirmationHoldSeconds
                ZStack {
                    Capsule()
                        .fill(SundownPalette.ember.opacity(model.canConfirmOverride ? 1 : 0.4))
                    // Progress fill sweeps left-to-right during the hold gesture.
                    Color.white.opacity(0.22)
                        .clipShape(Capsule())
                        .scaleEffect(x: holdProgress, y: 1, anchor: .leading)
                        .animation(
                            .linear(duration: holdProgress == 0 ? 0 : holdDuration),
                            value: holdProgress
                        )
                    Text(
                        "Hold \(Int(holdDuration))s to unlock for \(model.settings.overrideDurationMinutes) min"
                    )
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(SundownPalette.warmWhite)
                }
                .frame(width: 340, height: 44)
                .onLongPressGesture(
                    minimumDuration: holdDuration,
                    pressing: { isPressing in
                        if isPressing, model.canConfirmOverride {
                            holdProgress = 1
                        } else {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                holdProgress = 0
                            }
                        }
                    },
                    perform: {
                        model.confirmOverride()
                        holdProgress = 0
                    }
                )
                .allowsHitTesting(model.canConfirmOverride)
            } else {
                Button(OverrideRequestPolicy.entryPrompt) {
                    model.beginOverrideRequest()
                }
                .buttonStyle(.plain)
                .foregroundStyle(SundownPalette.warmWhite.opacity(0.4))
            }
        }
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

/// The evening (sundown) reflection, shown inside the lockout screen as the
/// optional shutdown ritual. Renders the configured evening prompts; "Save &
/// settle in" records them and collapses the card, "Skip" dismisses it. Either
/// way the reflection never delays or weakens enforcement — the clock and
/// Convince Me flow remain below it.
struct EveningReflectionCard: View {
    @EnvironmentObject private var model: CurfewAppModel

    /// Forwarded from the lockout screen's accessibility configuration so the
    /// card's panels stay legible under Reduce Transparency.
    let usesSolidPanels: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Close out the day")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("A moment to reflect before you step away.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.7))
            }

            ReflectionFormView(
                prompts: model.reflectionConfiguration.prompts(for: .evening),
                submitLabel: "Save & settle in",
                usesSolidPanels: usesSolidPanels,
                onSubmit: { answers in
                    model.saveReflection(gate: .evening, answers: answers)
                },
                onSkip: {
                    model.skipReflection(gate: .evening)
                }
            )
        }
        .padding(24)
        .frame(maxWidth: 600, alignment: .leading)
        .background(
            usesSolidPanels
                ? Color.black.opacity(0.6)
                : Color.white.opacity(0.08)
        )
        .cornerRadius(18)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Evening reflection")
    }
}
