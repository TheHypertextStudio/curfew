import CurfewKit
import ServiceManagement

struct OnboardingConfirmationRequirement: Equatable, Identifiable {
    enum RequirementID: String {
        case scheduleReview
        case accessibilityGrant
    }

    let id: RequirementID
    let title: String
    let isSatisfied: Bool
}

extension FirstRunFlow {
    var confirmationRequirements: [OnboardingConfirmationRequirement] {
        [
            OnboardingConfirmationRequirement(
                id: .scheduleReview,
                title: scheduleChoice != nil
                    ? "Automatic schedule choice confirmed"
                    : "Choose whether to use automatic lockouts",
                isSatisfied: scheduleChoice != nil
            ),
            OnboardingConfirmationRequirement(
                id: .accessibilityGrant,
                title: isAccessibilityGranted
                    ? "Accessibility access granted"
                    : "Accessibility access still required",
                isSatisfied: isAccessibilityGranted
            )
        ]
    }
}

enum ShutdownPanelState: Equatable {
    case available
    case unavailable(message: String)

    static let availableExplanation =
        "When enabled, Curfew tells System Events to shut down your Mac after lockout. "
            + "The first real shutdown attempt will trigger a macOS permission prompt. "
            + "If you deny it, re-enable Curfew > System Events in Privacy & Security > Automation."

    static let appleEventsUsageDescription =
        "Curfew uses System Events to shut down your Mac after lockout when "
            + "you turn on auto shutdown."

    static let unavailableMessage =
        "Automatic shutdown isn't available in this version of Curfew. "
            + "Install Curfew from the official website to use it."

    static func resolve(isAvailable: Bool) -> ShutdownPanelState {
        if isAvailable {
            .available
        } else {
            .unavailable(message: unavailableMessage)
        }
    }
}

enum PrivilegedHelperStatusCopy {
    static func daemonDescription(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled: "Installed."
        case .requiresApproval: "Approval needed in System Settings."
        case .notRegistered, .notFound: "Not installed."
        @unknown default: "Unknown status."
        }
    }

    static func loginItemDescription(for status: SMAppService.Status) -> String {
        switch status {
        case .enabled: "Curfew opens automatically at login."
        case .requiresApproval: "Approval needed in System Settings."
        case .notRegistered, .notFound: "Not registered."
        @unknown default: "Unknown status."
        }
    }
}
