import AppKit
import Combine
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

    /// Light poll that keeps the accessibility gate live while the window is
    /// open. Accessibility trust is granted out-of-process in System Settings,
    /// so there is no notification to observe — we re-read the model's polled
    /// trust state on a slow cadence (plus on appear / activation below) so the
    /// gate reflects a fresh grant within a second or two of the user making it.
    private let accessibilityRefreshTimer = Timer.publish(
        every: 1,
        on: .main,
        in: .common
    ).autoconnect()

    /// Header + current step panel + navigation action row.
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
        .onAppear(perform: syncAccessibilityGrant)
        .onReceive(accessibilityRefreshTimer) { _ in
            syncAccessibilityGrant()
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification
            )
        ) { _ in
            syncAccessibilityGrant()
        }
    }

    /// Re-polls the model's Accessibility-trust state and folds it into the
    /// flow's hard gate. The model's `refreshAccessibilityTrust()` only *reads*
    /// the trust seam (never the prompting API), so this is safe to call on a
    /// timer; `updateAccessibilityGranted` then opens or re-closes the gate to
    /// match, so a revoked permission cannot leave a stale "granted" reading.
    private func syncAccessibilityGrant() {
        model.refreshAccessibilityTrust()
        flow.updateAccessibilityGranted(model.isAccessibilityTrusted)
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
                flow.markScheduleReviewed()
                model.openSettings()
            }
            .buttonStyle(CurfewSecondaryButtonStyle())

            if flow.hasReviewedScheduleSettings {
                Label("Schedule settings opened", systemImage: "checkmark.circle.fill")
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.accent)
            } else {
                Text("Open Settings once here before continuing.")
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
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
            permissionsExtras
        }

        if flow.currentStep == .confirmation {
            ForEach(flow.confirmationRequirements) { requirement in
                Label(
                    requirement.title,
                    systemImage: requirement.isSatisfied ? "checkmark.circle.fill" : "circle"
                )
                .font(CurfewTypography.body(13))
                .foregroundStyle(
                    requirement.isSatisfied ? CurfewTheme.accent : CurfewTheme.mutedInk
                )
            }
        }
    }

    /// Accessibility hard-gate + soft notifications guidance for the
    /// `.permissions` step.
    ///
    /// The accessibility row is a *real* grant check, not a self-attested
    /// checkbox: "Next" stays disabled (`flow.canAdvance`) until the model's
    /// polled trust state — synced into the flow on appear / activation / the
    /// refresh timer — reports granted. The button routes through
    /// `requestAccessibilityAccess()`, which prompts and opens System Settings →
    /// Privacy & Security → Accessibility. Notifications remain optional below;
    /// denial there is non-fatal and never blocks progress.
    @ViewBuilder
    private var permissionsExtras: some View {
        if flow.isAccessibilityGranted {
            Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                .font(CurfewTypography.bodyEmphasis(14))
                .foregroundStyle(CurfewTheme.accent)
        } else {
            Label("Accessibility access required", systemImage: "exclamationmark.triangle.fill")
                .font(CurfewTypography.bodyEmphasis(14))
                .foregroundStyle(CurfewTheme.warning)

            Text(
                "Curfew needs Accessibility access to block bypass shortcuts "
                    + "(⌘⇥, ⌘Q, …) during lockout. Grant it in System Settings, "
                    + "then return here — this updates on its own."
            )
            .font(CurfewTypography.body(13))
            .foregroundStyle(CurfewTheme.mutedInk)

            Button("Open System Settings") {
                model.requestAccessibilityAccess()
                flow.updateAccessibilityGranted(model.isAccessibilityTrusted)
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
        }

        Text(
            "Notifications are optional — they deliver the wrap-up warnings. "
                + "You can allow or change them in System Settings anytime."
        )
        .font(CurfewTypography.body(13))
        .foregroundStyle(CurfewTheme.mutedInk)
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
                .disabled(!flow.canFinish)
            } else {
                Button("Next") {
                    flow.advance()
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(!flow.canAdvance)
            }
        }
    }
}
