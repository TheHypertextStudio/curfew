import CurfewKit
import SwiftUI

/// The two "how many per week" extension/override steppers, shared by
/// Settings → Enforcement's full budget panel (which also has the duration
/// steppers) and Getting Started's Extension Budget step (which only needs
/// this weekly-count pair) — so the range and label wording can't drift
/// between the two surfaces the way two independently-typed copies would.
struct WeeklyBudgetSteppers: View {
    @Bindable var model: CurfewAppModel

    var body: some View {
        Stepper(value: $model.settings.extensionWeeklyLimit, in: 0 ... 10) {
            LabeledContent("Extensions", value: "\(model.settings.extensionWeeklyLimit) per week")
        }
        Stepper(value: $model.settings.overrideWeeklyLimit, in: 0 ... 10) {
            LabeledContent("Overrides", value: "\(model.settings.overrideWeeklyLimit) per week")
        }
    }
}
