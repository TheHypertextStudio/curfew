import SwiftUI

/// Full-screen morning (sunrise) reflection overlay — the start-of-day
/// counterpart to the lockout's sundown. Hosted across every display by
/// ``OverlayCoordinator/syncDaybreakOverlay(presented:model:)`` when
/// `CurfewAppModel.isDaybreakPresented` is true.
///
/// It commands the screen like the lockout (same `.screenSaver` level) so the
/// day genuinely starts here, but is leniently dismissible: "Start the day"
/// saves the answers, "Skip" walks away clean — neither carries a penalty and
/// the gate will not re-prompt again today.
struct DaybreakReflectionView: View {
    @EnvironmentObject private var model: CurfewAppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: model.currentTime)
        return hour < 5 ? "Still up?" : "Good morning"
    }

    var body: some View {
        ZStack {
            DaybreakBackgroundView(animate: !reduceMotion)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(greeting)
                            .font(.system(size: 46, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
                        Text("Set your intention before the day takes over.")
                            .font(.system(size: 18, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.78))
                    }

                    ReflectionFormView(
                        prompts: model.reflectionConfiguration.prompts(for: .morning),
                        submitLabel: "Start the day",
                        usesSolidPanels: reduceTransparency,
                        onSubmit: { answers in
                            model.saveReflection(gate: .morning, answers: answers)
                        },
                        onSkip: {
                            model.skipReflection(gate: .morning)
                        }
                    )
                }
                .padding(48)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(greeting). Morning reflection.")
    }
}

/// Slowly-warming dawn gradient behind the morning reflection — the mirror of
/// the lockout's `LockoutBackgroundView`. The sunrise glow rises from the
/// *top* (vs. the sundown ember low on the horizon) and breathes gently when
/// motion is allowed.
private struct DaybreakBackgroundView: View {
    /// When `false`, the animation is disabled (static gradient).
    let animate: Bool
    @State private var animatePhase = false

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(red: 0.42, green: 0.30, blue: 0.40), location: 0.0),
                    .init(color: Color(red: 0.30, green: 0.27, blue: 0.42), location: 0.28),
                    .init(color: Color(red: 0.18, green: 0.20, blue: 0.36), location: 0.6),
                    .init(color: Color(red: 0.10, green: 0.13, blue: 0.24), location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(red: 0.98, green: 0.74, blue: 0.42).opacity(glowOpacity), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 680
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
            guard animate else { return }
            animatePhase = true
        }
    }

    /// Sunrise-bloom opacity — drifts subtly when motion is allowed.
    private var glowOpacity: Double {
        animate && animatePhase ? 0.6 : 0.48
    }
}
