import AppKit
import SwiftUI

extension SettingsView {
    var coordinatorSyncPanel: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Curfew Account",
                subtitle: "Sync encrypted policy, wake state, purchases, and devices"
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
            Label(
                "This Mac uses end-to-end encrypted account sync.",
                systemImage: "checkmark.shield"
            )
            .font(CurfewTypography.bodyEmphasis(13))
            .foregroundStyle(CurfewTheme.accent)
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
                    if let enrollment = try? accountEnrollment.acknowledgeSavedRecoveryKey() {
                        model.settings.accountSync.enrollment = enrollment
                    }
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
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

    private var openAccountButton: some View {
        Button("Open Account") {
            NSWorkspace.shared.open(
                URL(string: "https://curfew.hypertext.studio/account")!
            )
        }
        .buttonStyle(CurfewSecondaryButtonStyle())
    }

    static let accountExplanation = """
    A Curfew Account is optional. Local schedules, alarms, callbacks, and signed offline \
    licenses continue to work without one. An account lets your devices share encrypted \
    settings and one morning wake campaign.
    """

    static let accountSecurityNote = """
    Curfew creates the account root key on an enrolled device. The service stores encrypted \
    records and public device keys, but it cannot decrypt your settings. Sign-in recovery and \
    encrypted-data recovery remain separate: 2FA backup codes restore access, while the Curfew \
    Recovery Key restores encrypted data.
    """
}
