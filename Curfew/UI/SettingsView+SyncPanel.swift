import AppKit
import SwiftUI

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
        if model.settings.accountSync.isEnrolled {
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
            case .signingIn:
                ProgressView("Waiting for secure sign-in and 2FA…")
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
            case .finishDeviceRegistration:
                Text(
                    "You’re signed in. Curfew still needs to finish connecting this Mac. "
                        + "No new sign-in is needed."
                )
                .font(CurfewTypography.bodyEmphasis(13))
                .foregroundStyle(CurfewTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
                enrollmentRetryStatus
                Button("Finish connecting this Mac") {
                    Task { await accountEnrollment.finishDeviceRegistration() }
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
                .disabled(accountEnrollment.isFinishingEnrollment)
            case .finishRecoverySetup:
                Text(
                    "You’re signed in and this Mac is registered. Curfew still needs to "
                        + "finish recovery setup before remote control can turn on."
                )
                .font(CurfewTypography.bodyEmphasis(13))
                .foregroundStyle(CurfewTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
                enrollmentRetryStatus
                Button("Finish recovery setup") {
                    Task { await accountEnrollment.finishRecoverySetup() }
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
                .disabled(accountEnrollment.isFinishingEnrollment)
            case .saveRecoveryKey(let key, _):
                Text(
                    "Save this Recovery Key outside Curfew. "
                        + "Better Auth backup codes cannot recover encrypted Curfew data."
                )
                .font(CurfewTypography.bodyEmphasis(13))
                .foregroundStyle(CurfewTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
                Text(key)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .accessibilityLabel("Curfew Recovery Key")
                Button("I saved the Recovery Key") {
                    Task {
                        if let enrollment = await accountEnrollment.acknowledgeSavedRecoveryKey() {
                            model.settings.accountSync.enrollment = enrollment
                        }
                    }
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
                .disabled(accountEnrollment.isFinishingEnrollment)
            case .enterRecoveryKey:
                SecureField("Curfew Recovery Key", text: $accountRecoveryKey)
                    .textFieldStyle(.roundedBorder)
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
                .disabled(accountRecoveryKey.isEmpty)
            case .ready(let enrollment):
                Label("Encrypted account sync is ready.", systemImage: "checkmark.shield")
                    .onAppear { model.settings.accountSync.enrollment = enrollment }
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

private struct AccountConnectionStatusView: View {
    @ObservedObject var engine: AccountSyncEngine

    private var presentation: AccountConnectionPresentation {
        AccountConnectionPresentation.resolve(engine.syncStatus)
    }

    var body: some View {
        HStack(alignment: .top, spacing: CurfewSpacing.small) {
            Image(systemName: presentation.systemImage)
                .foregroundStyle(statusColor)
            VStack(alignment: .leading, spacing: 3) {
                Text(presentation.title)
                    .font(CurfewTypography.bodyEmphasis(13))
                Text(presentation.detail)
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                if let lastConfirmedAt = presentation.lastConfirmedAt {
                    Text("Last confirmed \(lastConfirmedAt, style: .relative)")
                        .font(CurfewTypography.body(11))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch presentation.tone {
        case .neutral: CurfewTheme.mutedInk
        case .ready: CurfewTheme.accent
        case .warning: CurfewTheme.warning
        }
    }
}
