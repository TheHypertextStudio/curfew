#if DEBUG
    import CurfewKit
    import EventKit
    import Foundation
    import ServiceManagement

    @MainActor
    extension CurfewAppModel {
        // Applies visual values to an isolated, disarmed demo model only.
        // Exhaustive fixture mapping intentionally keeps each synthetic state visible.
        // swiftlint:disable:next cyclomatic_complexity function_body_length
        func applyDemoReviewState(_ review: DemoReviewState) {
            guard isDemoSession else { return }
            settingsDestination = review.settingsSection
            switch review {
            case .normal: break
            case .accountOffline, .accountSignInRequired, .accountHelperUnavailable,
                 .accountUpdateFailed, .accountHelperHidden:
                let enrollment = AccountDeviceEnrollment(
                    deviceID: UUID(), keyEpoch: 1, enrolledAt: currentTime
                )
                settings.accountSync.enrollment = enrollment
                accountSyncEngine.start(enrollment: enrollment)
                privilegedHelperManager.seedDemoStatus(daemon: .enabled, connection: .unauthorized)
                switch review {
                case .accountOffline: accountSyncEngine.markOffline()
                case .accountSignInRequired:
                    accountSyncEngine.reject(AccountSyncRejectionReason.signInRequired)
                case .accountUpdateFailed:
                    accountSyncEngine.reject("Rejected stale or invalid wake state.")
                default: accountSyncEngine.markSynchronized(at: currentTime)
                }
            case .menuOffWarning:
                state = CurfewEvaluation(
                    phase: .warning, warningStage: .fifteenMinutes,
                    minutesRemaining: 15, canRequestExtension: true,
                    lockDate: currentTime.addingTimeInterval(900),
                    unlockDate: currentTime.addingTimeInterval(8 * 3600)
                )
            case .todayOffLocked:
                state = DemoFixture.evaluation(for: .lockout, now: currentTime)
            case .setupReview, .setupReviewDenied:
                settings.hasCompletedInitialSetup = true
                if review == .setupReviewDenied {
                    isAccessibilityTrusted = false
                    enforcementHealth = .degradedNoAccessibility
                }
            case .assistantExhausted:
                settings.mcpEnabled = true
                extensionsRemaining = 0
                state = CurfewEvaluation(
                    phase: .warning, warningStage: .thirtyMinutes,
                    minutesRemaining: 30, canRequestExtension: true,
                    lockDate: currentTime.addingTimeInterval(1800),
                    unlockDate: currentTime.addingTimeInterval(8 * 3600)
                )
                pendingMCPRequests = [MCPPendingRequest(
                    tool: .requestExtension, argumentsJSON: #"{"reason":"Save my work."}"#
                )]
            case .assistantMalformed:
                settings.mcpEnabled = true
                pendingMCPRequests = [MCPPendingRequest(
                    tool: .setSchedule, argumentsJSON: #"{"weekday":"monday","lock_time":"25:00"}"#
                )]
            case .ready:
                enforcementHealth = .active
                privilegedHelperManager.seedDemoStatus(daemon: .enabled, connection: .ready)
            case .accessibilityDenied:
                isAccessibilityTrusted = false
                enforcementHealth = .degradedNoAccessibility
            case .tapDown: enforcementHealth = .degradedTapDown
            case .helperApproval:
                privilegedHelperManager.seedDemoStatus(daemon: .requiresApproval)
            case .loginApproval:
                privilegedHelperManager.seedDemoStatus(login: .requiresApproval)
            case .helperUnauthorized, .helperStale, .helperRegistration:
                let connection: PrivilegedHelperManager
                    .ConnectionState = review == .helperUnauthorized
                    ? .unauthorized : (review == .helperStale ? .stale : .registrationFailed)
                privilegedHelperManager.seedDemoStatus(daemon: .enabled, connection: connection)
                enforcementHealth = review == .helperUnauthorized ? .degradedHelperUnauthorized
                    : (review == .helperStale ? .degradedHelperStale : .degradedHelperRegistration)
            case .limitsNone:
                settings.extensionWeeklyLimit = 0
                settings.overrideWeeklyLimit = 0
            case .assistantOn, .assistantReadOnly, .assistantAutomatic, .assistantPending,
                 .claudeAbsent, .claudeConfigured:
                settings.mcpEnabled = true
                aiConsentPolicy = review == .assistantAutomatic ? .autoApprove
                    : (review == .assistantReadOnly ? .deny : .queue)
                if review == .assistantPending {
                    pendingMCPRequests = [MCPPendingRequest(
                        tool: .requestExtension,
                        argumentsJSON: #"{"reason":"Finish saving my work."}"#
                    )]
                }
            case .licenseInvalid:
                licenseGate.seedDemoLicense(
                    nil,
                    error: "That key isn't valid. Check your purchase email."
                )
            case .licenseLifetime, .licenseSubscription, .licenseExpired:
                seedDemoLicense(review)
            case .cloudIdle, .cloudSyncing, .cloudSynced, .cloudFailed, .cloudUnavailable,
                 .calendarDenied, .calendarEmpty:
                seedDemoLicense(.licenseLifetime)
                seedDemoConnections(review)
            case .schedulePending:
                settings.pendingScheduleChange = PendingScheduleChange(
                    proposedSchedule: .startupHours, requestedAt: currentTime,
                    effectiveAt: currentTime.addingTimeInterval(86400), classification: .weaker
                )
            case .scheduleApplied: scheduleChangeJustApplied = true
            case .scheduleOvernight: settings.schedule = .startupHours
            case .dayOff: state = .dayOff
            case .journalPopulated:
                reflectionState.recorder = DemoReflectionRecorder(now: currentTime)
            case .promptsEmpty:
                reflectionState.configuration = ReflectionConfiguration(
                    morningEnabled: true, eveningEnabled: true, morningPrompts: [],
                    eveningPrompts: []
                )
            case .overrideCooldown, .overrideInvalid, .overrideReady:
                isOverrideComposerVisible = true
                overrideRequestedAt = review == .overrideCooldown ? currentTime
                    : currentTime.addingTimeInterval(-OverrideRequestPolicy.cooldownSeconds)
                overrideReasonDraft = review == .overrideInvalid ? "One more task" : DemoFixture
                    .overrideReason
            case .overridesExhausted: overridesRemaining = 0
            case .shutdownDenied:
                shutdownStatusLine = "Shutdown needs permission. Lockout remains active."
            case .shutdownFailed:
                shutdownStatusLine = "Shutdown failed. Lockout remains active."
            }
        }

        private func seedDemoLicense(_ review: DemoReviewState) {
            let subscription = review != .licenseLifetime
            licenseGate.seedDemoLicense(LicenseKey(
                email: "alex@example.com", product: "curfew-plus",
                plan: subscription ? .subscription : .lifetime, orderID: "demo",
                issuedAt: currentTime, expiresAt: subscription
                    ? Date()
                    .addingTimeInterval(review == .licenseExpired ? -86400 : 86400 * 30) : nil
            ))
        }

        private func seedDemoConnections(_ review: DemoReviewState) {
            switch review {
            case .cloudSyncing: cloudKitSyncEngine.seedDemoStatus(.syncing)
            case .cloudSynced: cloudKitSyncEngine.seedDemoStatus(.synced(date: currentTime))
            case .cloudFailed: cloudKitSyncEngine
                .seedDemoStatus(.failed(message: "The network is unavailable."))
            case .cloudUnavailable: cloudKitSyncEngine.seedDemoStatus(.unavailable)
            case .calendarDenied: calendarMonitor.seedDemoAuthorization(.denied)
            case .calendarEmpty: calendarMonitor.seedDemoAuthorization(.fullAccess)
            default: break
            }
        }
    }
#endif
