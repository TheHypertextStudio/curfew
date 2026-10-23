import AppKit
import CurfewKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var coordinatorSyncPanel: some View {
        Section {
            accountEnrollmentControls
            DisclosureGroup("Encryption and account recovery") {
                Text(Self.accountSecurityNote).foregroundStyle(CurfewTheme.mutedInk)
            }
        } header: {
            Text("Curfew Account")
        } footer: {
            Text(Self.accountExplanation)
        }
    }

    @ViewBuilder
    private var accountEnrollmentControls: some View {
        if case .storageUnavailable = accountEnrollment.state {
            storageUnavailableControls
        } else if case .ready(let enrollment) = accountEnrollment.state,
                  model.settings.accountSync.enrollment != enrollment {
            Label("Encrypted account sync is ready.", systemImage: "checkmark.shield")
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
                if model.privilegedHelperManager.installationInProgress
                    || model.privilegedHelperManager.repairInProgress {
                    Label("Connecting background protection…", systemImage: "hourglass")
                } else if model.privilegedHelperManager.daemonStatus == .requiresApproval {
                    Button("Approve Background Protection…") {
                        if !model.isDemoSession {
                            SMAppService.openSystemSettingsLoginItems()
                        }
                    }
                    .buttonStyle(CurfewPrimaryButtonStyle())
                } else if model.privilegedHelperManager.daemonStatus == .enabled {
                    Button("Review Background Protection") { selection = .general }
                        .buttonStyle(CurfewPrimaryButtonStyle())
                } else {
                    Button("Connect Background Protection…") {
                        Task { await model.privilegedHelperManager.installAndConnectDaemon() }
                    }
                    .buttonStyle(CurfewPrimaryButtonStyle())
                }
            }
            if model.accountSyncEngine.syncStatus.requiresSameAccountSignIn {
                if case .signingIn = accountEnrollment.state {
                    accountSignInInProgress
                } else {
                    Button("Sign in again to reconnect this Mac") {
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
                    .buttonStyle(CurfewPrimaryButtonStyle())
                    if let message = accountEnrollment.enrollmentRetryError {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(CurfewTheme.warning)
                    }
                }
            }
            if case .rejected(AccountSyncRejectionReason.accessDenied) =
                model.accountSyncEngine.syncStatus {
                Button("Retry account connection") {
                    if let enrollment = model.settings.accountSync.enrollment {
                        Task {
                            await model.accountSyncEngine
                                .retryAfterAccessReview(enrollment: enrollment)
                        }
                    }
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
            }
            openAccountButton
        } else {
            switch accountEnrollment.state {
            case .accountFree:
                Button("Sign in and enroll this Mac") {
                    Task { await accountEnrollment.signIn() }
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
                openAccountButton
            case .storageUnavailable:
                storageUnavailableControls
            case .signingIn:
                accountSignInInProgress
            case .connectingDevice:
                ProgressView("Securely connecting this Mac…")
            case .finishDeviceConnection:
                Text("You’re signed in. Curfew still needs to connect this Mac. "
                    + "No new sign-in is needed.")
                    .font(CurfewTypography.bodyEmphasis(13))
                    .foregroundStyle(CurfewTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                enrollmentRetryStatus
                Button("Finish connecting this Mac") {
                    Task { await accountEnrollment.signIn() }
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
            case .finishDeviceRegistration:
                Text(accountEnrollment.requiresReauthorization
                    ? "Curfew needs a fresh sign-in to finish connecting this same Mac."
                    : "You’re signed in. Curfew still needs to finish connecting this Mac. "
                    + "No new sign-in is needed.")
                    .font(CurfewTypography.bodyEmphasis(13))
                    .foregroundStyle(CurfewTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                enrollmentRetryStatus
                Button(accountEnrollment.requiresReauthorization
                    ? "Sign in again to finish connecting"
                    : "Finish connecting this Mac") {
                        Task {
                            if accountEnrollment.requiresReauthorization {
                                await accountEnrollment.reauthorizeSavedEnrollment()
                            } else {
                                await accountEnrollment.finishDeviceRegistration()
                            }
                        }
                    }
                    .buttonStyle(CurfewPrimaryButtonStyle())
                    .disabled(accountEnrollment.isFinishingEnrollment
                        || (accountEnrollment.requiresReauthorization
                            && !accountEnrollment.canReauthorizeSavedEnrollment))
            case .finishRecoverySetup:
                Text(accountEnrollment.requiresReauthorization
                    ? "This Mac is registered. Sign in again with the same account to "
                    + "finish recovery setup."
                    : "You’re signed in and this Mac is registered. Curfew still needs to "
                    + "finish recovery setup before remote control can turn on.")
                    .font(CurfewTypography.bodyEmphasis(13))
                    .foregroundStyle(CurfewTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                enrollmentRetryStatus
                Button(accountEnrollment.requiresReauthorization
                    ? "Sign in again to finish recovery setup"
                    : "Finish recovery setup") {
                        Task {
                            if accountEnrollment.requiresReauthorization {
                                await accountEnrollment.reauthorizeSavedEnrollment()
                            } else {
                                await accountEnrollment.finishRecoverySetup()
                            }
                        }
                    }
                    .buttonStyle(CurfewPrimaryButtonStyle())
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
                        Label("Copy Recovery Key", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                    .accessibilityIdentifier("settings-copy-recovery-key")

                    Button {
                        saveRecoveryKey(key)
                    } label: {
                        Label("Save Recovery Key…", systemImage: "arrow.down.doc")
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
                Label("Encrypted account sync is ready.", systemImage: "checkmark.shield")
                    .onAppear {
                        model.settings.accountSync.enrollment = enrollment
                    }
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(CurfewTheme.warning)
                Button("Try account enrollment again") {
                    Task { await accountEnrollment.signIn() }
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
                openAccountButton
            }
        }
    }

    @ViewBuilder
    private var accountSignInInProgress: some View {
        ProgressView("Waiting for secure sign-in and 2FA…")
        Button("Cancel sign-in") {
            accountEnrollment.cancelSignIn()
        }
        .buttonStyle(CurfewSecondaryButtonStyle())
        .accessibilityIdentifier("settings-cancel-account-sign-in")
        if accountEnrollment.browserSignInURL != nil {
            Text(
                "Did Curfew open the wrong browser profile? Copy this temporary, private "
                    + "sign-in link and paste it into the profile that stores your passkey."
            )
            .font(CurfewTypography.body(12))
            .foregroundStyle(CurfewTheme.mutedInk)
            .fixedSize(horizontal: false, vertical: true)

            Button {
                accountEnrollment.copyBrowserSignInLink()
            } label: {
                Label("Copy sign-in link", systemImage: "doc.on.doc")
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
            .accessibilityIdentifier("settings-copy-account-sign-in-link")
        }
    }

    private var storageUnavailableControls: some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.small) {
            Label(
                "Curfew can’t check this Mac’s saved account connection right now.",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(CurfewTheme.warning)
            Text(
                "Your local schedule and protection still work, but Curfew may need "
                    + "to repair this Mac’s account sign-in. Check the saved connection "
                    + "again. If this keeps happening, contact Curfew support."
            )
            .font(CurfewTypography.body(12))
            .foregroundStyle(CurfewTheme.mutedInk)
            Button("Check saved connection again") {
                accountEnrollment.reloadSavedEnrollment()
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
            .accessibilityIdentifier("settings-retry-saved-account-connection")
        }
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
        Button("Manage devices and remote control") {
            NSWorkspace.shared.open(CurfewServiceEndpoints.current.accountPortal)
        }
        .buttonStyle(CurfewSecondaryButtonStyle())
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
