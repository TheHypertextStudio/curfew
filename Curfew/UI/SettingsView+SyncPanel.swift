import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension SettingsView {
    var coordinatorSyncPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Curfew Account",
                subtitle: "Connect this Mac for encrypted sync and remote control"
            )

            Text(Self.accountExplanation)
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)

            Divider()
            accountEnrollmentControls
            Divider()

            Text(Self.accountSecurityNote)
                .font(CurfewTypography.body(12))
                .foregroundStyle(CurfewTheme.mutedInk)
                .fixedSize(horizontal: false, vertical: true)
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
            AccountConnectionStatusView(engine: model.accountSyncEngine)
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

    private var storageUnavailableControls: some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.small) {
            Label(
                "Curfew can’t check this Mac’s saved account connection right now.",
                systemImage: "exclamationmark.triangle"
            )
            .foregroundStyle(CurfewTheme.warning)
            Text(
                "Your saved account and local protection have not been changed. "
                    + "Try again. If this keeps happening, contact Curfew support before "
                    + "starting a new sign-in."
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
    A Curfew Account is optional. It lets you see your devices and securely lock this Mac \
    from an AI assistant on your phone. Remote control is off until you turn it on for this \
    device. Local schedules, alarms, callbacks, and signed offline licenses keep working \
    without an account.
    """

    static let accountSecurityNote = """
    Curfew creates the account root key on an enrolled device. The service stores encrypted \
    records and public device keys, but it cannot decrypt your settings. Sign-in recovery and \
    encrypted-data recovery remain separate: 2FA backup codes restore access, while the Curfew \
    Recovery Key restores encrypted data.
    """
}

enum AccountConnectionTone: Equatable {
    case neutral
    case ready
    case warning
}

struct AccountConnectionPresentation: Equatable {
    let title: String
    let detail: String
    let systemImage: String
    let tone: AccountConnectionTone
    let lastConfirmedAt: Date?

    init(
        title: String,
        detail: String,
        systemImage: String,
        tone: AccountConnectionTone,
        lastConfirmedAt: Date? = nil
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        self.tone = tone
        self.lastConfirmedAt = lastConfirmedAt
    }

    static func resolve(_ status: AccountSyncStatus) -> AccountConnectionPresentation {
        switch status {
        case .accountFree:
            AccountConnectionPresentation(
                title: "This Mac is not connected",
                detail: "Connect a Curfew Account to use encrypted sync and remote control.",
                systemImage: "circle",
                tone: .neutral
            )
        case .connecting:
            AccountConnectionPresentation(
                title: "Connecting this Mac…",
                detail: "Curfew is securely connecting to your account. "
                    + "Your local schedule keeps working.",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .neutral
            )
        case .synchronized(let date):
            AccountConnectionPresentation(
                title: "This Mac is connected",
                detail: "Curfew is checking for remote commands. "
                    + "Choose which assistants and devices have access in your account.",
                systemImage: "checkmark.circle.fill",
                tone: .ready,
                lastConfirmedAt: date
            )
        case .pendingEncryption:
            AccountConnectionPresentation(
                title: "Encrypted changes are waiting to sync",
                detail: "Remote commands keep using your last confirmed settings.",
                systemImage: "lock.rotation",
                tone: .neutral
            )
        case .offline:
            AccountConnectionPresentation(
                title: "Remote control is offline",
                detail: "This Mac is still protected by its local schedule. "
                    + "Curfew will reconnect automatically.",
                systemImage: "wifi.slash",
                tone: .warning
            )
        case .rejected:
            AccountConnectionPresentation(
                title: "Remote control is temporarily unavailable",
                detail: "This Mac is still protected locally. "
                    + "Open your account to check access, or try again shortly.",
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning
            )
        }
    }
}
