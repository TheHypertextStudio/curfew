import SwiftUI

/// First-launch onboarding view presented in its own AppKit window by
/// `GettingStartedWindowPresenter`.
///
/// Layout is deliberately static: a title, a commitment-framing sentence,
/// a single `CurfewPanel` whose content switches on `flow.currentStep`, and
/// a bottom action row. Advancing / retreating through the five
/// `FirstRunStep` cases updates the panel; "Finish Setup" on the final
/// step calls `completeOnboardingFlow()` on the model, which marks the
/// setup-complete flag and arms enforcement.
///
/// Uses `@State` (rather than `@StateObject` + an `ObservableObject`) for
/// the flow cursor because the cursor is a plain value type and all
/// necessary invalidation happens naturally through SwiftUI's value
/// diffing.
struct GettingStartedView: View {
    /// Shared app model — we only read a few settings here
    /// (extension/override budgets for the budget step) and trigger
    /// navigation actions (`openSettings`, `dismissGettingStarted`,
    /// `completeOnboardingFlow`).
    @EnvironmentObject private var model: CurfewAppModel

    /// Local cursor tracking which onboarding pane is visible.
    @State private var flow = FirstRunFlow()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            stepPanel
            Spacer(minLength: 0)
            actionRow
        }
        .padding(28)
        .frame(minWidth: 640, minHeight: 470)
        .background(CurfewTheme.canvas)
        .foregroundStyle(CurfewTheme.ink)
    }

    /// Static title + commitment sentence at the top of the window.
    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(GettingStartedCopy.title)
                .font(CurfewTypography.display(30))

            Text(GettingStartedCopy.commitmentMessage)
                .font(CurfewTypography.body(18))
                .foregroundStyle(CurfewTheme.mutedInk)
        }
    }

    /// Content panel that switches on the active `FirstRunStep`.
    private var stepPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: flow.currentStep.title,
                subtitle: "Step \(flow.currentStep.rawValue + 1) "
                    + "of \(FirstRunStep.allCases.count)"
            )

            Text(flow.currentStep.message)
                .font(CurfewTypography.body(14))
                .foregroundStyle(CurfewTheme.mutedInk)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(flow.currentStep.checklist, id: \.self) { line in
                    Label(line, systemImage: "checkmark.circle")
                }
            }
            .font(CurfewTypography.bodyEmphasis(14))
            .foregroundStyle(CurfewTheme.ink)

            stepExtras
        }
    }

    /// Step-specific extra content (schedule shortcut button, budget
    /// summary, permissions hint).
    @ViewBuilder
    private var stepExtras: some View {
        if flow.currentStep == .schedule {
            Button("Open Schedule Settings") {
                model.openSettings()
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
        }

        if flow.currentStep == .extensionBudget {
            Text("Current extension limit: \(model.settings.extensionWeeklyLimit) per week")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
            Text("Current override limit: \(model.settings.overrideWeeklyLimit) per week")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
        }

        if flow.currentStep == .permissions {
            Text(
                "You can review notifications and accessibility access "
                    + "in system settings at any time."
            )
            .font(CurfewTypography.body(13))
            .foregroundStyle(CurfewTheme.mutedInk)
        }
    }

    /// Back / Not now / Next | Finish action row.
    private var actionRow: some View {
        HStack(spacing: 10) {
            Button("Back") {
                flow.retreat()
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
            .disabled(flow.isFirstStep)

            Button("Not now") {
                model.dismissGettingStarted()
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
            .keyboardShortcut(.cancelAction)

            Spacer()

            if flow.isLastStep {
                Button("Finish Setup") {
                    model.completeOnboardingFlow()
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Next") {
                    flow.advance()
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
            }
        }
    }
}
