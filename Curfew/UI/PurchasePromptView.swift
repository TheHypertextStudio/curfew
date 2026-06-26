import CurfewKit
import SwiftUI

/// Inline upsell shown in place of a Plus-gated feature.
///
/// Usage:
/// ```swift
/// PlusGate(feature: "Cloud Sync", description: "Sync your schedule across all your Macs.") {
///     CloudSyncSettingsView()
/// }
/// ```
struct PlusGate<Content: View>: View {
    @Environment(CurfewAppModel.self) private var model
    /// Feature name shown in the upsell header. Keep short.
    let feature: String
    /// One-sentence explainer for the upsell copy.
    let description: String
    /// The Plus-gated content, rendered verbatim when a valid licence is
    /// active and swapped for `PurchasePromptView` otherwise.
    @ViewBuilder let content: Content

    /// Renders `content` when Plus is unlocked; the upsell otherwise.
    var body: some View {
        if model.licenseGate.isPlusUnlocked {
            content
        } else {
            PurchasePromptView(feature: feature, description: description)
        }
    }
}

/// Inline upsell panel that replaces a Plus-gated feature when the
/// current build has no active licence. Surfaces a single Upgrade link
/// to the landing pricing section (one-time + subscription); no in-app
/// purchase surface.
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
                    Text("\(feature) — Curfew Plus")
                        .font(CurfewTypography.bodyEmphasis(14))
                        .foregroundStyle(CurfewTheme.ink)

                    Text(description)
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }

                Spacer()

                Link("Get Plus", destination: LicensePurchase.pricingURL)
                    .font(CurfewTypography.bodyEmphasis(13))
                    .foregroundStyle(CurfewTheme.accent)
            }
        }
    }
}
