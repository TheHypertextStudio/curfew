import SwiftUI

/// Settings panel for entering and managing a Curfew Pro license key.
struct LicenseView: View {
    @EnvironmentObject private var model: CurfewAppModel
    @State private var keyDraft = ""

    private var gate: LicenseGate {
        model.licenseGate
    }

    /// Panel that swaps between an activation form and the activated
    /// licence summary depending on `LicenseGate.isProUnlocked`.
    var body: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Curfew Pro",
                subtitle: gate.isProUnlocked
                    ? "Your license is active."
                    : "Unlock cloud sync, widgets, and calendar awareness."
            )

            if gate.isProUnlocked {
                unlockedBody
            } else {
                lockedBody
            }
        }
    }

    // MARK: - Unlocked state

    private var unlockedBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(CurfewTheme.accent)
                Text("Pro — \(gate.activatedKey?.email ?? "")")
                    .font(CurfewTypography.bodyEmphasis(14))
                    .foregroundStyle(CurfewTheme.ink)
            }

            Button("Deactivate License") {
                gate.deactivate()
                keyDraft = ""
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
        }
    }

    // MARK: - Locked state

    private var lockedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            proFeatureList

            TextField("Paste license key…", text: $keyDraft)
                .font(CurfewTypography.body(13))
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

            Text("Paste the key from your purchase confirmation page or email.")
                .font(CurfewTypography.label(12))
                .foregroundStyle(CurfewTheme.mutedInk)

            if let error = gate.activationError {
                Text(error)
                    .font(CurfewTypography.label(12))
                    .foregroundStyle(CurfewTheme.warning)
            }

            HStack(spacing: 10) {
                Button("Activate") {
                    gate.activate(keyDraft)
                }
                .buttonStyle(CurfewPrimaryButtonStyle())
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Link("Buy Curfew Pro — $20", destination: purchaseURL)
                    .font(CurfewTypography.bodyEmphasis(14))
                    .foregroundStyle(CurfewTheme.accent)
            }
        }
    }

    private var proFeatureList: some View {
        VStack(alignment: .leading, spacing: 4) {
            proFeatureRow("iCloud sync across all your Macs", icon: "icloud")
            proFeatureRow("WidgetKit status widget", icon: "rectangle.3.group")
            proFeatureRow("Calendar-aware schedule exceptions", icon: "calendar.badge.clock")
        }
    }

    private func proFeatureRow(_ label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(CurfewTypography.body(13))
            .foregroundStyle(CurfewTheme.mutedInk)
    }

    private var purchaseURL: URL {
        URL(string: "https://buy.stripe.com/REPLACE_WITH_CURFEW_PRO_PAYMENT_LINK")!
    }
}
