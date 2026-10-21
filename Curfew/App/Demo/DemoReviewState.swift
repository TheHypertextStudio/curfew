#if DEBUG
    import CurfewKit
    import Foundation

    /// Deterministic visual states; none start real services or enforcement.
    enum DemoReviewState: String, CaseIterable {
        case normal = "default"
        case restContinuity = "rest-continuity"
        case restNight = "rest-night"
        case restMorning = "rest-morning"
        case accountUpdateFailed = "account-update-failed"
        case accountHelperHidden = "account-helper-hidden"
        case accountOffline = "account-offline"
        case accountSignInRequired = "account-sign-in-required"
        case accountHelperUnavailable = "account-helper-unavailable"
        case menuOffWarning = "menu-off-warning"
        case todayOffLocked = "today-off-locked"
        case setupReview = "setup-review"
        case setupReviewDenied = "setup-review-denied"
        case assistantMalformed = "assistant-malformed"
        case assistantExhausted = "assistant-exhausted"
        case ready
        case accessibilityDenied = "accessibility-denied"
        case tapDown = "tap-down"
        case helperApproval = "helper-approval"
        case helperUnauthorized = "helper-unauthorized"
        case helperStale = "helper-stale"
        case helperRegistration = "helper-registration"
        case loginApproval = "login-approval"
        case limitsNone = "limits-none"
        case assistantOn = "assistant-on"
        case assistantReadOnly = "assistant-read-only"
        case assistantAutomatic = "assistant-automatic"
        case assistantPending = "assistant-pending"
        case claudeAbsent = "claude-absent"
        case claudeConfigured = "claude-configured"
        case licenseInvalid = "license-invalid"
        case licenseLifetime = "license-lifetime"
        case licenseSubscription = "license-subscription"
        case licenseExpired = "license-expired"
        case cloudIdle = "cloud-idle"
        case cloudSyncing = "cloud-syncing"
        case cloudSynced = "cloud-synced"
        case cloudFailed = "cloud-failed"
        case cloudUnavailable = "cloud-unavailable"
        case calendarDenied = "calendar-denied"
        case calendarEmpty = "calendar-empty"
        case schedulePending = "schedule-pending"
        case scheduleApplied = "schedule-applied"
        case scheduleOvernight = "schedule-overnight"
        case dayOff = "day-off"
        case journalPopulated = "journal-populated"
        case promptsEmpty = "prompts-empty"
        case overrideCooldown = "override-cooldown"
        case overrideInvalid = "override-invalid"
        case overrideReady = "override-ready"
        case overridesExhausted = "overrides-exhausted"
        case shutdownDenied = "shutdown-denied"
        case shutdownFailed = "shutdown-failed"

        static var current: DemoReviewState {
            DemoReviewState(rawValue: ProcessInfo.processInfo
                .environment["CURFEW_DEMO_STATE"] ?? "") ?? .normal
        }

        var settingsSection: SettingsSection {
            switch self {
            case .limitsNone: .enforcement
            case .accountOffline, .accountSignInRequired, .accountHelperUnavailable,
                 .accountUpdateFailed, .accountHelperHidden,
                 .assistantOn, .assistantReadOnly, .assistantAutomatic, .assistantPending,
                 .assistantMalformed, .assistantExhausted,
                 .claudeAbsent, .claudeConfigured, .cloudIdle, .cloudSyncing, .cloudSynced,
                 .cloudFailed, .cloudUnavailable, .calendarDenied, .calendarEmpty: .integrations
            case .licenseInvalid, .licenseLifetime, .licenseSubscription, .licenseExpired: .about
            default: .general
            }
        }

        var enablesPreviewConnections: Bool {
            switch self {
            case .cloudIdle, .cloudSyncing, .cloudSynced, .cloudFailed, .cloudUnavailable,
                 .calendarDenied, .calendarEmpty: true
            default: false
            }
        }
    }
#endif
