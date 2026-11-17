import CurfewKit
import SwiftUI

struct AccountConnectionStatusView: View {
    @ObservedObject var engine: AccountSyncEngine
    let remoteEnforcementReady: Bool
    let remoteEnforcementSupported: Bool

    private var presentation: AccountConnectionPresentation {
        AccountConnectionPresentation.resolve(
            engine.syncStatus,
            remoteEnforcementReady: remoteEnforcementReady,
            remoteEnforcementSupported: remoteEnforcementSupported
        )
    }

    var body: some View {
        SettingsRow(
            title: presentation.title,
            detail: detailText,
            tone: presentation.tone == .warning ? .warning : .secondary
        ) {
            if needsSupport, let supportURL = URL(string: "mailto:hello@hypertext.studio") {
                Link("Contact Curfew support", destination: supportURL)
                    .font(CurfewTypography.bodyEmphasis(12))
            }
        }
    }

    /// The explanation, with when the connection was last confirmed.
    private var detailText: String {
        guard let lastConfirmedAt = presentation.lastConfirmedAt else { return presentation.detail }
        return presentation.detail
            + " Last confirmed \(lastConfirmedAt.formatted(.relative(presentation: .named)))."
    }

    private var needsSupport: Bool {
        guard case .rejected(let reason) = engine.syncStatus else { return false }
        return reason == AccountSyncRejectionReason.localDeviceIdentityMissing
            || reason == AccountSyncRejectionReason.localDeviceIdentityInvalid
    }
}
