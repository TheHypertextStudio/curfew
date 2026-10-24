import CurfewKit
import Foundation

/// Static copy used by the first-launch onboarding ("Getting Started")
/// window.
///
/// Extracted to a namespace enum so the exact wording of commitment-framing
/// copy lives in one place — the CLI's `curfew-ctl status` and future
/// landing-page copy pulls from the same strings when we standardise on a
/// shared copy deck post-v0.2. For now it's read by the SwiftUI onboarding
/// view only.
enum GettingStartedCopy {
    /// Window title — also used as the primary heading.
    static let title = "Welcome to Curfew"

    /// One-sentence framing shown under the title. Leans on the "you already
    /// made this decision when clear-headed" argument rather than pitching
    /// productivity benefits.
    static let commitmentMessage =
        "Choose your work hours. Curfew warns you before lockout and blocks access when work ends."

    /// Secondary heading introducing the numbered configuration steps.
    static let setupFocusTitle = "Set up Curfew"
}

/// One pane of the first-run onboarding flow.
///
/// `Int`-backed so we can advance/retreat by `rawValue ± 1` without
/// maintaining a separate next-step table. Keep the case order stable:
/// persisted progress (if we ever add resume-from-where-you-left) would key
/// off `rawValue`.
enum FirstRunStep: Int, CaseIterable, Identifiable {
    /// Introductory pane explaining Curfew's commitment model.
    case welcome

    /// Schedule configuration (work-end/work-resume times, days off).
    case schedule

    /// Extension + override budget configuration.
    case extensionBudget

    /// Notification + accessibility permissions walkthrough.
    case permissions

    /// Review pane that finalises onboarding and arms enforcement.
    case confirmation

    /// `Identifiable` conformance — raw value is already unique.
    var id: Int {
        rawValue
    }

    /// Human-readable heading for the pane.
    var title: String {
        switch self {
        case .welcome:
            "Welcome"
        case .schedule:
            "Schedule"
        case .extensionBudget:
            "Extra time"
        case .permissions:
            "Permissions"
        case .confirmation:
            "Ready to begin"
        }
    }

    /// Supporting paragraph that expands on `title`.
    var message: String {
        switch self {
        case .welcome:
            "Curfew warns you before your work hours end, then shows a full-screen lockout."
        case .schedule:
            ScheduleSurfaceCopy.onboardingMessage
        case .extensionBudget:
            "Choose how many extensions and overrides you can use each week."
        case .permissions:
            "Curfew uses optional notifications for warnings and Accessibility access "
                + "to block bypass shortcuts during lockout."
        case .confirmation:
            "Review your setup, then enable Curfew when you are ready."
        }
    }

    /// Bullet checklist shown alongside the message. Each entry is an action
    /// the user should complete before clicking Next.
    var checklist: [String] {
        switch self {
        case .welcome:
            ["Review how warnings and lockout work"]
        case .schedule:
            ScheduleSurfaceCopy.onboardingChecklist
        case .extensionBudget:
            ["Adjust weekly extension limit", "Set override duration"]
        case .permissions:
            ["Grant accessibility access", "Allow notifications (optional)"]
        case .confirmation:
            ["Review your schedule", "Enable Curfew"]
        }
    }
}

/// An explicit choice about automatic lockouts, distinct from editing the
/// proposed schedule and from authorizing remote fixed-duration controls.
enum AutomaticScheduleChoice: Equatable {
    case weeklySchedule
    case remoteControlsOnly
}

/// Stateful cursor into the first-run onboarding flow.
///
/// Kept as a plain value type rather than an `ObservableObject` so it can be
/// passed around between views cheaply and also exercised by unit tests
/// without a run-loop. The UI wraps it in `@State` and advances/retreats
/// from button handlers.
struct FirstRunFlow {
    /// The pane currently visible. Externally read-only; mutate via
    /// `advance()` / `retreat()`.
    private(set) var currentStep: FirstRunStep = .welcome

    /// Whether the user has acknowledged the seven effective weekly rules.
    private(set) var hasReviewedScheduleSettings = false

    /// Opening the editor is not consent. A choice is required before the
    /// schedule step can advance or setup can arm enforcement.
    private(set) var scheduleChoice: AutomaticScheduleChoice?

    /// Whether the app currently holds macOS Accessibility trust.
    ///
    /// This is a *real* grant check, not a self-attested checkbox: the view
    /// keeps it in sync with the injected `AccessibilityAuthorizing` seam
    /// (on appear / on app activation / a light timer), and the permissions
    /// step refuses to advance while it is `false`. Replacing the old
    /// "I reviewed permissions" acknowledgement closes the hole where a user
    /// could tick the box without ever granting access, leaving enforcement
    /// silently inert.
    private(set) var isAccessibilityGranted = false

    /// Whether the user is on the first step (drives "Back" button disabling).
    var isFirstStep: Bool {
        currentStep == .welcome
    }

    /// Whether the user is on the final step (drives the confirmation CTA).
    var isLastStep: Bool {
        currentStep == .confirmation
    }

    /// Whether the current step is allowed to advance.
    ///
    /// The permissions gate is a hard one: Accessibility must be *actually*
    /// granted (`isAccessibilityGranted`) before the user can leave the step.
    /// Notifications stay soft — their denial is non-fatal and never blocks
    /// progress.
    var canAdvance: Bool {
        switch currentStep {
        case .schedule:
            scheduleChoice != nil
        case .permissions:
            isAccessibilityGranted
        case .welcome, .extensionBudget, .confirmation:
            true
        }
    }

    /// Whether the final onboarding action should be enabled.
    var canFinish: Bool {
        isLastStep && scheduleChoice != nil && isAccessibilityGranted
    }

    /// Records explicit review of the seven rules shown during onboarding.
    mutating func markScheduleReviewed() {
        hasReviewedScheduleSettings = true
    }

    /// The onboarding review button is one state transition. Splitting the
    /// review acknowledgement and choice into separate SwiftUI `@State`
    /// mutations can leave the second mutation reading the old review flag.
    mutating func chooseReviewedWeeklySchedule() {
        hasReviewedScheduleSettings = true
        scheduleChoice = .weeklySchedule
    }

    /// Selects remote-only setup directly, or the weekly schedule after the
    /// user has acknowledged the actual configured rules.
    mutating func chooseSchedule(_ choice: AutomaticScheduleChoice) {
        guard choice == .remoteControlsOnly || hasReviewedScheduleSettings else { return }
        scheduleChoice = choice
    }

    /// Syncs the live Accessibility-trust state into the flow.
    ///
    /// Called by the view whenever a fresh reading is available (on appear, on
    /// app activation, and from a light refresh timer). Passing `false` after a
    /// previous `true` re-closes the gate, so a revoked permission can never
    /// leave the user advancing on a stale "granted" reading.
    mutating func updateAccessibilityGranted(_ granted: Bool) {
        guard isAccessibilityGranted != granted else { return }
        isAccessibilityGranted = granted
    }

    /// Moves forward one step, unless already on the last step (no-op).
    mutating func advance() {
        guard canAdvance, let nextStep = FirstRunStep(rawValue: currentStep.rawValue + 1) else {
            return
        }
        currentStep = nextStep
    }

    /// Moves backward one step, unless already on the first step (no-op).
    mutating func retreat() {
        guard let previousStep = FirstRunStep(rawValue: currentStep.rawValue - 1) else {
            return
        }
        currentStep = previousStep
    }

    /// A flow pre-seeded for someone re-opening Getting Started *after*
    /// finishing it once (from the Settings/menu re-entry points, which don't
    /// gate on `hasCompletedInitialSetup`). Jumps straight to Confirmation
    /// with the schedule gate already satisfied — walking an already-onboarded
    /// user through Schedule/Extension-Budget/Permissions again is pure
    /// friction, since those already govern a live, working setup.
    /// Accessibility is intentionally left `false` here: the view's own
    /// on-appear sync immediately re-polls the *real* current grant, so a
    /// permission revoked since setup still shows as required.
    static func returningUser() -> FirstRunFlow {
        var flow = FirstRunFlow()
        flow.currentStep = .confirmation
        flow.hasReviewedScheduleSettings = true
        flow.scheduleChoice = .weeklySchedule
        return flow
    }
}
