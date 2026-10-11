import Foundation

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

    static func resolve(
        _ status: AccountSyncStatus,
        remoteEnforcementReady: Bool = true
    ) -> AccountConnectionPresentation {
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
                    + "Your schedule is unchanged.",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .neutral
            )
        case .synchronized(let date):
            synchronized(at: date, remoteEnforcementReady: remoteEnforcementReady)
        case .pendingEncryption:
            AccountConnectionPresentation(
                title: "Encrypted changes are waiting to sync",
                detail: "Your encrypted changes haven’t synced yet.",
                systemImage: "lock.rotation",
                tone: .neutral
            )
        case .offline:
            AccountConnectionPresentation(
                title: "Remote control is offline",
                detail: "Your schedule is unchanged. "
                    + "Curfew will reconnect automatically.",
                systemImage: "wifi.slash",
                tone: .warning
            )
        case .rejected:
            rejected(requiresSameAccountSignIn: status.requiresSameAccountSignIn)
        }
    }

    private static func rejected(requiresSameAccountSignIn: Bool) -> AccountConnectionPresentation {
        if requiresSameAccountSignIn {
            return AccountConnectionPresentation(
                title: "Reconnect this Mac to Curfew",
                detail: "Curfew cannot authenticate this Mac right now. "
                    + "Sign in again with the same account to restore remote control. "
                    + "Your local schedule stays unchanged.",
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning
            )
        }
        return AccountConnectionPresentation(
            title: "Check this Mac’s account access",
            detail: "Curfew Account denied this Mac’s request. Its device access may have "
                + "been removed. Check this Mac in your account. Your schedule is unchanged.",
            systemImage: "exclamationmark.triangle.fill",
            tone: .warning
        )
    }

    private static func synchronized(
        at date: Date,
        remoteEnforcementReady: Bool
    ) -> AccountConnectionPresentation {
        if !remoteEnforcementReady {
            return AccountConnectionPresentation(
                title: "Remote locks are not ready",
                detail: "This Mac is signed in, but background protection cannot enforce remote "
                    + "locks right now. Review Background Protection in General.",
                systemImage: "exclamationmark.triangle.fill",
                tone: .warning,
                lastConfirmedAt: date
            )
        }
        return AccountConnectionPresentation(
            title: "This Mac is connected",
            detail: "Curfew is checking for remote commands. "
                + "Choose which assistants and devices have access in your account.",
            systemImage: "checkmark.circle.fill",
            tone: .ready,
            lastConfirmedAt: date
        )
    }
}
