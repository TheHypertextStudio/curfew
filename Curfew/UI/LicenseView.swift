import CurfewKit
import SwiftUI

/// Settings panel for entering and managing a Curfew Plus license key.
struct LicenseView: View {
    @Environment(CurfewAppModel.self) private var model
    @State private var keyDraft = ""

    private var gate: LicenseGate {
        model.licenseGate
    }

    /// Panel that swaps between an activation form and the activated
    /// licence summary depending on `LicenseGate.isPlusUnlocked`.
    var body: some View {
        CurfewPanel {
            CurfewSectionTitle(
                title: "Curfew Plus",
                subtitle: gate.isPlusUnlocked
                    ? "Your license is active."
                    : "Unlock cloud sync, widgets, and calendar awareness."
            )

            if gate.isPlusUnlocked {
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
                Text(activeSummary)
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

    /// "Lifetime — email" or "Subscription · renews <date> — email", drawn from
    /// the activated key's `plan` and `expiresAt`.
    private var activeSummary: String {
        let email = gate.activatedKey?.email ?? ""
        switch gate.activatedKey?.plan {
        case .subscription:
            if let expiresAt = gate.activatedKey?.expiresAt {
                let date = expiresAt.formatted(date: .abbreviated, time: .omitted)
                return "Subscription · renews \(date) — \(email)"
            }
            return "Subscription — \(email)"
        case .lifetime, .none:
            return "Lifetime — \(email)"
        }
    }

    // MARK: - Locked state

    private var lockedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            // A stored-but-expired subscription lands here; nudge toward renewal.
            if gate.activatedKey != nil {
                Text("Your Plus subscription has lapsed. Renew to restore access.")
                    .font(CurfewTypography.label(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }

            plusFeatureList

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

                Link("Get Curfew Plus", destination: LicensePurchase.pricingURL)
                    .buttonStyle(CurfewLinkButtonStyle())
            }
        }
    }

    private var plusFeatureList: some View {
        VStack(alignment: .leading, spacing: 4) {
            plusFeatureRow("iCloud sync across all your Macs", icon: "icloud")
            plusFeatureRow("WidgetKit status widget", icon: "rectangle.3.group")
            plusFeatureRow("Calendar-aware schedule exceptions", icon: "calendar.badge.clock")
        }
    }

    private func plusFeatureRow(_ label: String, icon: String) -> some View {
        Label(label, systemImage: icon)
            .font(CurfewTypography.body(13))
            .foregroundStyle(CurfewTheme.mutedInk)
    }
}

/// Single source of truth for where the app sends people to buy Plus. Points at
/// the landing page's pricing section, which presents both the one-time and the
/// subscription options together, rather than embedding two Stripe links here.
enum LicensePurchase {
    static let pricingURL = URL(string: "https://curfew.hypertext.studio/#plus")!
}
