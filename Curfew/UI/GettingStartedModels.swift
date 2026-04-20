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
        "Set your schedule while you're thinking clearly, then let Curfew enforce it later."

    /// Secondary heading introducing the numbered configuration steps.
    static let setupFocusTitle = "What to Configure First"
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
            "Extension Budget"
        case .permissions:
            "Permissions"
        case .confirmation:
            "Confirmation"
        }
    }

    /// Supporting paragraph that expands on `title`.
    var message: String {
        switch self {
        case .welcome:
            "Curfew helps you keep commitments you made while you had clear focus."
        case .schedule:
            ScheduleSurfaceCopy.onboardingMessage
        case .extensionBudget:
            "Set weekly extension and override limits to keep exceptions deliberate."
        case .permissions:
            "Curfew uses notifications and accessibility APIs so warnings "
                + "and lockout behavior work reliably."
        case .confirmation:
            "Review your setup, then enable Curfew when you are ready."
        }
    }

    /// Bullet checklist shown alongside the message. Each entry is an action
    /// the user should complete before clicking Next.
    var checklist: [String] {
        switch self {
        case .welcome:
            ["Understand how Curfew enforces commitments"]
        case .schedule:
            ScheduleSurfaceCopy.onboardingChecklist
        case .extensionBudget:
            ["Adjust weekly extension limit", "Set override duration"]
        case .permissions:
            ["Allow notifications", "Confirm accessibility permissions"]
        case .confirmation:
            ["Enable Curfew", "Start with confidence"]
        }
    }
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

    /// Whether onboarding has routed the user through live schedule settings.
    private(set) var hasReviewedScheduleSettings = false

    /// Whether the permissions step has been explicitly acknowledged.
    private(set) var hasAcknowledgedPermissions = false

    /// Whether the user is on the first step (drives "Back" button disabling).
    var isFirstStep: Bool {
        currentStep == .welcome
    }

    /// Whether the user is on the final step (drives the confirmation CTA).
    var isLastStep: Bool {
        currentStep == .confirmation
    }

    /// Whether the current step is allowed to advance.
    var canAdvance: Bool {
        switch currentStep {
        case .schedule:
            hasReviewedScheduleSettings
        case .permissions:
            hasAcknowledgedPermissions
        case .welcome, .extensionBudget, .confirmation:
            true
        }
    }

    /// Whether the final onboarding action should be enabled.
    var canFinish: Bool {
        isLastStep && hasReviewedScheduleSettings && hasAcknowledgedPermissions
    }

    /// Records that the user has opened the live schedule editor from onboarding.
    mutating func markScheduleReviewed() {
        hasReviewedScheduleSettings = true
    }

    /// Records that the user reviewed the permissions guidance.
    mutating func acknowledgePermissions() {
        hasAcknowledgedPermissions = true
    }

    /// Moves forward one step, unless already on the last step (no-op).
    mutating func advance() {
        guard canAdvance else {
            return
        }
        guard let nextStep = FirstRunStep(rawValue: currentStep.rawValue + 1) else {
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
}
