import AppKit
import CurfewKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var coordinatorSyncPanel: some View {
        SettingsGroup("Curfew Account", footer: Self.accountExplanation) {
            accountEnrollmentControls
            DisclosureGroup {
                Text(Self.accountSecurityNote)
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                SettingsRowLabel(title: "Encryption and account recovery")
            }
        }
    }

    @ViewBuilder
    private var accountEnrollmentControls: some View {
        if case .storageUnavailable = accountEnrollment.state {
            storageUnavailableControls
        } else if case .ready(let enrollment) = accountEnrollment.state,
                  model.settings.accountSync.enrollment != enrollment {
            SettingsActionRow(
                title: "Connected", detail: "Encrypted account sync is ready.", actionTitle: nil
            )
            .onAppear {
                model.settings.accountSync.enrollment = enrollment
            }
        } else if model.settings.accountSync.isEnrolled {
            AccountConnectionStatusView(
                engine: model.accountSyncEngine,
                remoteEnforcementReady: model.featureFlags.privilegedHelperEnabled
                    && model.privilegedHelperManager.isRemoteLockEnforcementAvailable,
                remoteEnforcementSupported: model.featureFlags.privilegedHelperEnabled
            )
            if !model.featureFlags.privilegedHelperEnabled {
                Link(
                    "Get Curfew",
                    destination: CurfewServiceEndpoints.production.accountPortal
                        .deletingLastPathComponent()
                )
                .buttonStyle(CurfewSecondaryButtonStyle())
                .accessibilityIdentifier("settings-get-curfew")
            }
            if model.featureFlags.privilegedHelperEnabled,
               !model.privilegedHelperManager.isRemoteLockEnforcementAvailable {
                let helper = model.privilegedHelperManager
                if helper.installationInProgress || helper.repairInProgress {
                    SettingsActionRow(
                        title: "Remote locks", detail: "Connecting the Curfew helper…",
                        actionTitle: nil
                    )
                } else if helper.daemonStatus == .requiresApproval {
                    SettingsActionRow(
                        title: "Remote locks", detail: "They need the Curfew helper.",
                        tone: .warning, actionTitle: "Allow the Curfew helper…"
                    ) {
                        if !model.isDemoSession {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                } else if helper.daemonStatus == .enabled {
                    SettingsActionRow(
                        title: "Remote locks", detail: "They need the Curfew helper.",
                        tone: .warning, actionTitle: "Check the Curfew helper"
                    ) { selection = .general }
                } else {
                    SettingsActionRow(
                        title: "Remote locks", detail: "They need the Curfew helper.",
                        tone: .warning, actionTitle: "Set up the Curfew helper…"
                    ) {
                        Task { await helper.installAndConnectDaemon() }
                    }
                }
            }
            if model.accountSyncEngine.syncStatus.requiresSameAccountSignIn {
                if case .signingIn = accountEnrollment.state {
                    accountSignInInProgress
                } else {
                    SettingsActionRow(
                        title: "Sign in again",
                        detail: accountEnrollment.enrollmentRetryError
                            ?? "Use the same Curfew account to reconnect this Mac.",
                        tone: .warning,
                        actionTitle: "Sign in again to reconnect this Mac"
                    ) {
                        if let enrollment = model.settings.accountSync.enrollment {
                            Task {
                                guard await accountEnrollment.reconnectEnrolledMac(enrollment),
                                      model.settings.accountSync.enrollment == enrollment
                                else { return }
                                await model.accountSyncEngine
                                    .reconnectAfterAuthentication(enrollment: enrollment)
                            }
                        }
                    }
                }
            }
            if case .rejected(AccountSyncRejectionReason.accessDenied) =
                model.accountSyncEngine.syncStatus {
                SettingsActionRow(
                    title: "Access was denied",
                    detail: "Check this Mac's access in your account, then try again.",
                    tone: .warning,
                    actionTitle: "Retry account connection"
                ) {
                    if let enrollment = model.settings.accountSync.enrollment {
                        Task {
                            await model.accountSyncEngine
                                .retryAfterAccessReview(enrollment: enrollment)
                        }
                    }
                }
            }
            openAccountButton
        } else {
            switch accountEnrollment.state {
            case .accountFree:
                SettingsActionRow(
                    title: "Not signed in",
                    detail: "Sign in to sync your schedule and allow remote control.",
                    actionTitle: "Sign in and enroll this Mac"
                ) {
                    Task { await accountEnrollment.signIn() }
                }
                openAccountButton
            case .storageUnavailable:
                storageUnavailableControls
            case .signingIn:
                accountSignInInProgress
            case .connectingDevice:
                SettingsActionRow(
                    title: "Connecting", detail: "Securely connecting this Mac…", actionTitle: nil
                )
            case .finishDeviceConnection:
                SettingsActionRow(
                    title: "Almost connected",
                    detail: enrollmentRetryDetail ?? "You’re signed in. Curfew still needs "
                        + "to connect this Mac. No new sign-in is needed.",
                    tone: .warning,
                    actionTitle: "Finish connecting this Mac"
                ) {
                    Task { await accountEnrollment.signIn() }
                }
            case .finishDeviceRegistration:
                SettingsActionRow(
                    title: "Almost connected",
                    detail: enrollmentRetryDetail ?? (accountEnrollment.requiresReauthorization
                        ? "Curfew needs a fresh sign-in to finish connecting this same Mac."
                        : "You’re signed in. Curfew still needs to finish connecting this Mac. "
                        + "No new sign-in is needed."),
                    tone: .warning,
                    actionTitle: accountEnrollment.requiresReauthorization
                        ? "Sign in again to finish connecting"
                        : "Finish connecting this Mac"
                ) {
                    Task {
                        if accountEnrollment.requiresReauthorization {
                            await accountEnrollment.reauthorizeSavedEnrollment()
                        } else {
                            await accountEnrollment.finishDeviceRegistration()
                        }
                    }
                }
                .disabled(accountEnrollment.isFinishingEnrollment
                    || (accountEnrollment.requiresReauthorization
                        && !accountEnrollment.canReauthorizeSavedEnrollment))
            case .finishRecoverySetup:
                SettingsActionRow(
                    title: "Recovery setup isn't finished",
                    detail: enrollmentRetryDetail ?? (accountEnrollment.requiresReauthorization
                        ? "This Mac is registered. Sign in again with the same account to "
                        + "finish recovery setup."
                        : "You’re signed in and this Mac is registered. Curfew still needs to "
                        + "finish recovery setup before remote control can turn on."),
                    tone: .warning,
                    actionTitle: accountEnrollment.requiresReauthorization
                        ? "Sign in again to finish recovery setup"
                        : "Finish recovery setup"
                ) {
                    Task {
                        if accountEnrollment.requiresReauthorization {
                            await accountEnrollment.reauthorizeSavedEnrollment()
                        } else {
                            await accountEnrollment.finishRecoverySetup()
                        }
                    }
                }
                .disabled(accountEnrollment.isFinishingEnrollment
                    || (accountEnrollment.requiresReauthorization
                        && !accountEnrollment.canReauthorizeSavedEnrollment))
            case .saveRecoveryKey(let key, _):
                Text(
                    "Save this Recovery Key outside Curfew. "
                        + "Copy it to a password manager or save a private file. "
                        + "Account recovery codes cannot restore encrypted Curfew data."
                )
                .font(CurfewTypography.bodyEmphasis(13))
                .foregroundStyle(CurfewTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityLabel("Curfew Recovery Key")
                HStack {
                    Button {
                        recoveryKeyExportMessage = AccountRecoveryKeyClipboard.copy(key)
                            ? "Recovery Key copied. Curfew clears it from the clipboard "
                            + "after one minute."
                            : "Curfew could not copy the Recovery Key. Select and copy it manually."
                    } label: {
                        Label("Copy recovery key", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                    .accessibilityIdentifier("settings-copy-recovery-key")

                    Button {
                        saveRecoveryKey(key)
                    } label: {
                        Label("Save recovery key…", systemImage: "arrow.down.doc")
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                    .accessibilityIdentifier("settings-save-recovery-key")
                }
                if !recoveryKeyExportMessage.isEmpty {
                    Text(recoveryKeyExportMessage)
                        .font(CurfewTypography.body(12))
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .accessibilityAddTraits(.updatesFrequently)
                }
                Button("I saved the Recovery Key") {
                    Task {
                        if let enrollment = await accountEnrollment.acknowledgeSavedRecoveryKey() {
                            model.settings.accountSync.enrollment = enrollment
                        }
                    }
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
                .accessibilityIdentifier("settings-confirm-recovery-key-saved")
                .disabled(accountEnrollment.isFinishingEnrollment)
            case .enterRecoveryKey:
                SecureField("Curfew Recovery Key", text: $accountRecoveryKey)
                    .textFieldStyle(.roundedBorder)
                enrollmentRetryStatus
                if accountEnrollment.requiresReauthorization {
                    Text("Sign in again with the same Curfew account, then restore your "
                        + "encrypted data with this Mac’s Recovery Key.")
                        .font(CurfewTypography.bodyEmphasis(13))
                        .foregroundStyle(CurfewTheme.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Sign in again to restore") {
                        Task { await accountEnrollment.reauthorizeSavedEnrollment() }
                    }
                    .buttonStyle(CurfewPrimaryButtonStyle())
                    .disabled(!accountEnrollment.canReauthorizeSavedEnrollment)
                }
                Text(
                    "The Recovery Key stays on this Mac. Curfew sends only the encrypted envelope."
                )
                .font(CurfewTypography.body(12))
                .foregroundStyle(CurfewTheme.mutedInk)
                Button("Restore encrypted account") {
                    Task {
                        await accountEnrollment.restore(recoveryKey: accountRecoveryKey)
                        if case .ready(let enrollment) = accountEnrollment.state {
                            model.settings.accountSync.enrollment = enrollment
                            accountRecoveryKey = ""
                        }
                    }
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
                .disabled(accountRecoveryKey.isEmpty
                    || accountEnrollment.requiresReauthorization)
            case .ready(let enrollment):
                SettingsActionRow(
                    title: "Connected", detail: "Encrypted account sync is ready.", actionTitle: nil
                )
                .onAppear {
                    model.settings.accountSync.enrollment = enrollment
                }
            case .failed(let message):
                SettingsActionRow(
                    title: "Couldn't connect this Mac",
                    detail: message,
                    tone: .warning,
                    actionTitle: "Try account enrollment again"
                ) {
                    Task { await accountEnrollment.signIn() }
                }
                openAccountButton
            }
        }
    }

    @ViewBuilder
    private var accountSignInInProgress: some View {
        SettingsActionRow(
            title: "Signing in",
            detail: "Waiting for secure sign-in and 2FA…",
            actionTitle: "Cancel sign-in",
            identifier: "settings-cancel-account-sign-in"
        ) {
            accountEnrollment.cancelSignIn()
        }
        if accountEnrollment.browserSignInURL != nil {
            SettingsActionRow(
                title: "Wrong browser profile?",
                detail: "Copy this temporary, private sign-in link and paste it into the "
                    + "profile that stores your passkey.",
                actionTitle: "Copy sign-in link",
                identifier: "settings-copy-account-sign-in-link"
            ) {
                accountEnrollment.copyBrowserSignInLink()
            }
        }
    }

    private var storageUnavailableControls: some View {
        SettingsActionRow(
            title: "Curfew can’t check this Mac’s saved account connection right now.",
            detail: "Your schedule still works on this Mac. If this keeps happening, "
                + "contact Curfew support.",
            tone: .warning,
            actionTitle: "Check saved connection again",
            identifier: "settings-retry-saved-account-connection"
        ) {
            accountEnrollment.reloadSavedEnrollment()
        }
    }

    /// A retry problem replaces the row's explanation rather than adding a row.
    private var enrollmentRetryDetail: String? {
        accountEnrollment.isFinishingEnrollment
            ? "Finishing secure connection…" : accountEnrollment.enrollmentRetryError
    }

    @ViewBuilder
    private var enrollmentRetryStatus: some View {
        if accountEnrollment.isFinishingEnrollment {
            ProgressView("Finishing secure connection…")
        } else if let message = accountEnrollment.enrollmentRetryError {
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(CurfewTheme.warning)
        }
    }

    private var openAccountButton: some View {
        SettingsActionRow(
            title: "Macs and remote control",
            detail: "Managed in your Curfew Account online.",
            actionTitle: "Manage devices and remote control"
        ) {
            NSWorkspace.shared.open(CurfewServiceEndpoints.current.accountPortal)
        }
    }

    private func saveRecoveryKey(_ key: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = AccountRecoveryKeyDocument.suggestedFilename
        panel.message = "This file can restore your encrypted Curfew data. Keep it private."
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            do {
                try AccountRecoveryKeyDocument(recoveryKey: key).write(to: destination)
                recoveryKeyExportMessage = "Recovery Key saved. Keep the file somewhere private."
            } catch {
                recoveryKeyExportMessage = "Curfew could not save the Recovery Key. "
                    + "Try another location."
                NSApp.presentError(error)
            }
        }
    }

    static let accountExplanation = """
    An optional account lets your phone lock this Mac. Remote control stays off until \
    you turn it on; local schedules and offline licenses work without an account.
    """

    static let accountSecurityNote = """
    Your enrolled device creates the encryption key; the service cannot read your settings. \
    2FA backup codes recover sign-in, while your Curfew Recovery Key recovers encrypted data.
    """
}
