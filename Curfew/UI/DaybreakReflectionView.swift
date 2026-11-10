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

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: model.currentTime)
        return hour < 5 ? "Still up?" : "Good morning"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 8) {
                Text(greeting)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(SundownPalette.warmWhite)
                Text("Set your intention before the day takes over.")
                    .font(.system(size: 18, weight: .regular, design: .rounded))
                    .foregroundStyle(SundownPalette.warmWhite)
            }
            ReflectionFormView(
                draft: model.reflectionDraft(for: .morning),
                submitLabel: "Start the day",
                usesSolidPanels: reduceTransparency,
                onSubmit: { model.saveReflection(gate: .morning, answers: $0) },
                onSkip: { model.skipReflection(gate: .morning) }
            )
        }
        .frame(maxWidth: 560, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(greeting). Morning reflection.")
    }
}
