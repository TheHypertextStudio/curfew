import CurfewKit
import SwiftUI

/// Inline upsell shown in place of a Pro-gated feature.
///
/// Usage:
/// ```swift
/// ProGate(feature: "Cloud Sync", description: "Sync your schedule across all your Macs.") {
///     CloudSyncSettingsView()
/// }
/// ```
struct ProGate<Content: View>: View {
    @EnvironmentObject private var model: CurfewAppModel
    /// Feature name shown in the upsell header. Keep short.
    let feature: String
    /// One-sentence explainer for the upsell copy.
    let description: String
    /// The Pro-gated content, rendered verbatim when a valid licence is
    /// active and swapped for `PurchasePromptView` otherwise.
    @ViewBuilder let content: Content

    /// Renders `content` when Pro is unlocked; the upsell otherwise.
    var body: some View {
        if model.licenseGate.isProUnlocked {
            content
        } else {
            PurchasePromptView(feature: feature, description: description)
        }
    }
}

/// Inline upsell panel that replaces a Pro-gated feature when the
/// current build has no active licence. Surfaces a single Upgrade link
/// to the Stripe Checkout payment link; no in-app purchase surface.
struct PurchasePromptView: View {
    /// Feature name shown in the upsell header.
    let feature: String
    /// One-sentence explainer.
    let description: String

    /// Lock icon + copy + upgrade link in a compact horizontal panel.
    var body: some View {
        CurfewPanel {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(CurfewTheme.mutedInk)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(feature) — Curfew Pro")
                        .font(CurfewTypography.bodyEmphasis(14))
                        .foregroundStyle(CurfewTheme.ink)

                    Text(description)
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }

                Spacer()

                Link(
                    "Upgrade — $20",
                    destination: URL(
                        string: "https://buy.stripe.com/REPLACE_WITH_CURFEW_PRO_PAYMENT_LINK"
                    )!
                )
                .font(CurfewTypography.bodyEmphasis(13))
                .foregroundStyle(CurfewTheme.accent)
            }
        }
    }
}
