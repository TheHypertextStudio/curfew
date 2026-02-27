import SwiftUI

enum LockoutAccessibilityCopy {
    static func summary(message: String, unlockLine: String?) -> String {
        let unlockPortion = unlockLine ?? "Unlock time unavailable."
        return "Curfew lockout active. \(message). \(unlockPortion)"
    }
}

struct LockoutVisualConfiguration: Equatable, Sendable {
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

                        Text("Minimum \(OverrideRequestPolicy.minimumJustificationCharacters) characters")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.65))

                        Button("Hold for 3s to unlock for \(model.settings.overrideDurationMinutes) min") {}
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
