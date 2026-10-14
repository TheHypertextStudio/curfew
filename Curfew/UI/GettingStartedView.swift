import AppKit
import Combine
import CurfewKit
import SwiftUI

/// First-launch onboarding view hosted by the `getting-started`
/// `WindowGroup` scene in `CurfewApp`.
///
/// Layout is deliberately static: a title, a commitment-framing sentence,
/// a single `CurfewPanel` whose content switches on `flow.currentStep`, and
/// a bottom action row. Advancing / retreating through the five
/// `FirstRunStep` cases updates the panel; "Finish Setup" on the final
/// step passes an explicit schedule choice to the model before setup arms.
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
    @Environment(CurfewAppModel.self) private var model

    /// Local cursor tracking which onboarding pane is visible.
    @State private var flow = FirstRunFlow()
    @State private var showingImmediateLockConfirmation = false

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
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    stepPanel
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            actionRow
        }
        .padding(28)
        .frame(minWidth: 640, minHeight: 470)
        .background(CurfewTheme.canvas)
        .foregroundStyle(CurfewTheme.ink)
        .onAppear {
            // Re-entry (Settings → "Show Getting Started") skips the walkthrough
            // for an already-onboarded install — see `FirstRunFlow.returningUser()`.
            if model.settings.hasCompletedInitialSetup, flow.currentStep == .welcome {
                flow = .returningUser()
            }
            syncAccessibilityGrant()
        }
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
        .alert(
            "This Mac may lock within a minute",
            isPresented: $showingImmediateLockConfirmation
        ) {
            Button("Enable imminent lockout", role: .destructive) {
                model.completeOnboardingFlow(
                    choice: .weeklySchedule,
                    confirmedImmediateLock: true
                )
            }
            Button("Keep reviewing", role: .cancel) {}
        } message: {
            Text(
                model.settings.schedule.reviewLines.joined(separator: "\n") +
                    "\n\nMay lock this Mac now. Existing lockouts stay active."
            )
        }
    }

    /// Content panel that switches on the active `FirstRunStep`.
    private var stepPanel: some View {
        CurfewPanel {
            if !model.settings.hasCompletedInitialSetup {
                Text(flow.currentStep.message)
                    .font(CurfewTypography.body(14))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }

            stepExtras
        }
    }

    /// Step-specific extra content (schedule shortcut button, budget
    /// summary, permissions hint).
    @ViewBuilder
    private var stepExtras: some View {
        if !model.settings.hasCompletedInitialSetup, flow.currentStep == .schedule {
            scheduleReviewAndChoice
        }

        if !model.settings.hasCompletedInitialSetup, flow.currentStep == .extensionBudget {
            extensionBudgetExtras
        }

        if !model.settings.hasCompletedInitialSetup, flow.currentStep == .permissions {
            permissionsExtras
        }

        if model.settings.hasCompletedInitialSetup || flow.currentStep == .confirmation {
            if model.settings.hasCompletedInitialSetup, model.isAccessibilityTrusted {
                Label("Setup complete", systemImage: "checkmark.seal.fill")
                    .font(CurfewTypography.bodyEmphasis(14))
                    .foregroundStyle(CurfewTheme.accent)
            }

            if model.settings.hasCompletedInitialSetup, !model.isAccessibilityTrusted {
                permissionsExtras
            }

            if !model.settings.hasCompletedInitialSetup {
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

            if model.settings.hasCompletedInitialSetup {
                Text(model.automaticScheduleEnabled
                    ? model.scheduleSummarySentence
                    : "Automatic schedule is off; your saved times are not enforcing lockouts.")
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
            } else if flow.scheduleChoice == .weeklySchedule {
                Text(model.settings.schedule.reviewLines.joined(separator: "\n"))
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                if model.scheduleWouldLockNow {
                    Label(
                        "Finishing setup may lock this Mac now or within a minute.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(CurfewTheme.warning)
                }
            } else if flow.scheduleChoice == .remoteControlsOnly {
                Text(
                    "No automatic lockouts. Authorized remote locks can still apply."
                )
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
            }
        }
    }

    /// Keep the effective seven-day review beside both choices at the minimum
    /// onboarding window size. A tall single-column stack put the choice
    /// buttons below the scroll viewport, where clicking could not select one.
    private var scheduleReviewAndChoice: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Review all seven saved rules before choosing automatic lockouts:")
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.mutedInk)
                ForEach(model.settings.schedule.reviewLines, id: \.self) { line in
                    Text(line)
                        .font(CurfewTypography.body(12))
                        .foregroundStyle(CurfewTheme.ink)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                Button("Edit weekly schedule") {
                    model.requestWorkspaceNavigation(to: .schedule)
                }
                .buttonStyle(CurfewSecondaryButtonStyle())

                Button {
                    flow.chooseReviewedWeeklySchedule()
                } label: {
                    Text("I've reviewed these seven days — use this weekly schedule")
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(CurfewSecondaryButtonStyle())

                Button {
                    flow.chooseSchedule(.remoteControlsOnly)
                } label: {
                    Text("No automatic schedule — remote controls only")
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(CurfewSecondaryButtonStyle())

                if let choice = flow.scheduleChoice {
                    Label(
                        choice == .weeklySchedule
                            ? "Weekly lockouts selected. They start only when you finish setup."
                            : "No automatic lockouts. Authorized remote locks still work.",
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(CurfewTheme.accent)
                }
            }
            .frame(width: 228, alignment: .leading)
        }
    }

    /// Extension/override budget controls — the same `WeeklyBudgetSteppers`
    /// Settings → Enforcement uses, bound straight to settings, so the
    /// checklist's "Adjust weekly extension limit" is an action this step can
    /// actually perform, not just a read-only preview of values editable only
    /// elsewhere.
    private var extensionBudgetExtras: some View {
        VStack(alignment: .leading, spacing: 6) {
            WeeklyBudgetSteppers(model: model)
        }
        .font(CurfewTypography.body(13))
        .foregroundStyle(CurfewTheme.ink)
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
        if model.isAccessibilityTrusted {
            Label("Accessibility access granted", systemImage: "checkmark.circle.fill")
                .font(CurfewTypography.bodyEmphasis(14))
                .foregroundStyle(CurfewTheme.accent)
        } else {
            Label("Accessibility access required", systemImage: "exclamationmark.triangle.fill")
                .font(CurfewTypography.bodyEmphasis(14))
                .foregroundStyle(CurfewTheme.warning)

            Text(
                "Enable Curfew in System Settings, then return here to continue."
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
            "Notifications are optional. Manage them in System Settings."
        )
        .font(CurfewTypography.body(13))
        .foregroundStyle(CurfewTheme.mutedInk)
    }

    /// Back / Not now / Next | Finish action row.
    private var actionRow: some View {
        HStack(spacing: 10) {
            if model.settings.hasCompletedInitialSetup {
                Spacer()
                Button("Done") { model.dismissGettingStarted() }
                    .buttonStyle(CurfewPrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else {
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
                    Button(flow.scheduleChoice == .weeklySchedule
                        ? "Enable schedule and finish"
                        : "Finish without automatic schedule") {
                            guard let choice = flow.scheduleChoice else { return }
                            if model.completeOnboardingFlow(choice: choice)
                                == .requiresImmediateLockConfirmation {
                                showingImmediateLockConfirmation = true
                            }
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
}

private extension GettingStartedView {
    /// Static title + commitment sentence at the top of the window.
    var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.settings.hasCompletedInitialSetup {
                Text("Review setup")
                    .font(CurfewTypography.display(30))
                Text(model.automaticScheduleEnabled
                    ? "Automatic weekly lockouts are on."
                    : "Automatic weekly lockouts are off. Authorized remote locks can still apply.")
                    .foregroundStyle(CurfewTheme.mutedInk)
            } else {
                Text(flow.currentStep == .welcome ? GettingStartedCopy.title : flow.currentStep
                    .title)
                    .font(CurfewTypography.display(30))
                Text("Step \(flow.currentStep.rawValue + 1) of \(FirstRunStep.allCases.count)")
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
        }
    }

    /// Re-polls the model's Accessibility-trust state and folds it into the
    /// flow's hard gate. The model's `refreshAccessibilityTrust()` only *reads*
    /// the trust seam (never the prompting API), so this is safe to call on a
    /// timer; `updateAccessibilityGranted` then opens or re-closes the gate to
    /// match, so a revoked permission cannot leave a stale "granted" reading.
    func syncAccessibilityGrant() {
        if !model.isDemoSession {
            model.refreshAccessibilityTrust()
        }
        flow.updateAccessibilityGranted(model.isAccessibilityTrusted)
    }
}
