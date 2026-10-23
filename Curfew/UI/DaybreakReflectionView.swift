import CurfewKit
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
    @Environment(CurfewAppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    /// Drives the one-shot "awakening" rise-in when the sunrise gate appears.
    @State private var awoke = false

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: model.currentTime)
        return switch hour {
        case 5 ..< 12: "Good morning"
        case 12 ..< 17: "Good afternoon"
        case 17 ..< 24: "Good evening"
        default: "Welcome back"
        }
    }

    var body: some View {
        ZStack {
            SundownSky(moment: model.skyMoment)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(greeting)
                            .font(.system(size: 46, weight: .semibold, design: .rounded))
                            .foregroundStyle(SundownPalette.warmWhite)
                            .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
                        Text("What do you plan to work on today?")
                            .font(.system(size: 18, weight: .regular, design: .rounded))
                            .foregroundStyle(SundownPalette.warmWhite.opacity(0.78))
                    }

                    ReflectionFormView(
                        prompts: model.reflectionConfiguration.prompts(for: .morning),
                        submitLabel: "Save reflection",
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
                .opacity(awoke ? 1 : 0)
                .offset(y: awoke ? 0 : 18)
            }
            .scrollIndicators(.hidden)
        }
        .onAppear {
            guard !reduceMotion else {
                awoke = true
                return
            }
            withAnimation(.easeOut(duration: 0.9)) { awoke = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(greeting). Start-of-work reflection.")
    }
}
