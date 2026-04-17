import EventKit
import SwiftUI

enum LockoutAccessibilityCopy {
    static func summary(message: String, unlockLine: String?) -> String {
        let unlockPortion = unlockLine ?? "Unlock time unavailable."
        return "Curfew lockout active. \(message). \(unlockPortion)"
    }
}

struct LockoutVisualConfiguration: Equatable {
    var animateBackground: Bool
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

struct LockoutScreenView: View {
    @EnvironmentObject private var model: CurfewAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

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

    var body: some View {
        ZStack {
            LockoutBackgroundView(animate: visualConfiguration.animateBackground)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text(model.currentTime, style: .time)
                    .font(.system(size: 72, weight: .light, design: .rounded))
                    .foregroundStyle(.white)

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

private struct LockoutBackgroundView: View {
    let animate: Bool
    @State private var animatePhase = false

    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.12, green: 0.08, blue: 0.20),
                Color(red: 0.18, green: 0.10, blue: 0.12),
                Color(red: 0.06, green: 0.09, blue: 0.16)
            ],
            startPoint: animate && animatePhase ? .topTrailing : .topLeading,
            endPoint: animate && animatePhase ? .bottomLeading : .bottomTrailing
        )
        .saturation(animate ? 1.1 : 1.0)
        .animation(
            animate
                ? .easeInOut(duration: 12).repeatForever(autoreverses: true)
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
}
