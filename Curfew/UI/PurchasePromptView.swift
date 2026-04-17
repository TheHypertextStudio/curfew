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
    let feature: String
    let description: String
    @ViewBuilder let content: Content

    var body: some View {
        if model.licenseGate.isProUnlocked {
            content
        } else {
            PurchasePromptView(feature: feature, description: description)
        }
    }
}

struct PurchasePromptView: View {
    let feature: String
    let description: String

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

                Link("Upgrade — $19", destination: URL(string: "https://curfew.hypertext.studio/#pro")!)
                    .font(CurfewTypography.bodyEmphasis(13))
                    .foregroundStyle(CurfewTheme.accent)
            }
        }
    }
}
