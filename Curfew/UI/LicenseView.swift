import CurfewKit
import SwiftUI

/// Settings panel for entering and managing a Curfew Plus license key.
struct LicenseView: View {
    @Environment(CurfewAppModel.self) private var model
    @State private var keyDraft = ""
    @State private var manualEntryExpanded = false
    @State private var showingRestore = false
    @State private var purchaseEmail = ""

    private var gate: LicenseGate {
        model.licenseGate
    }

    private var activation: LicenseActivationController {
        model.licenseActivation
    }

    /// Panel that swaps between an activation form and the activated
    /// licence summary depending on `LicenseGate.isPlusUnlocked`.
    var body: some View {
        Section("Curfew Plus") {
            if activation.isBusy {
                HStack { ProgressView().controlSize(.small); Text(activation.message ?? "Working…")
                }
            } else if let message = activation.message {
                Text(message).foregroundStyle(CurfewTheme.accent)
                    .accessibilityIdentifier("license-activation-status")
            }
            if let error = activation.error ?? gate.activationError {
                Text(error).foregroundStyle(CurfewTheme.warning)
                    .textSelection(.enabled)
            }
            if gate.isPlusUnlocked {
                unlockedBody
            } else {
                lockedBody
            }
        }
        .sheet(isPresented: $showingRestore) { restoreSheet }
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
                activation.cancel()
                gate.deactivate()
                keyDraft = ""
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
        }
    }

    /// "Lifetime — email" or "Subscription · active until <date> — email",
    /// drawn from the activated key's `plan` and `expiresAt`.
    ///
    /// Deliberately says "active until", not "renews": `expiresAt` is the
    /// current period end (plus a grace window) regardless of whether the
    /// subscription is actively renewing or already cancelled and coasting
    /// to that same deadline — nothing here can tell the two apart, so
    /// "renews" would promise automatic continuation to someone who just
    /// cancelled.
    private var activeSummary: String {
        let email = gate.activatedKey?.email ?? ""
        switch gate.activatedKey?.plan {
        case .subscription:
            if let expiresAt = gate.activatedKey?.expiresAt {
                let date = expiresAt.formatted(date: .abbreviated, time: .omitted)
                return "Subscription · active until \(date) — \(email)"
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
                Text("Your subscription has expired. Renew to restore Plus.")
                    .font(CurfewTypography.label(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }

            plusFeatureList

            HStack(spacing: 10) {
                Button("Restore Purchase…") {
                    showingRestore = true
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
                .disabled(activation.isBusy)
                Link("Get Curfew Plus", destination: LicensePurchase.pricingURL)
                    .buttonStyle(CurfewLinkButtonStyle())
            }

            DisclosureGroup("Enter a license key", isExpanded: $manualEntryExpanded) {
                TextField("License key", text: $keyDraft)
                    .font(CurfewTypography.body(13))
                    .textFieldStyle(.roundedBorder)
                    .disableAutocorrection(true)
                Button("Activate") { activation.activateManually(keyDraft) }
                    .buttonStyle(CurfewPrimaryButtonStyle())
                    .disabled(activation.isBusy || keyDraft
                        .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var restoreSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore Purchase").font(.title2.bold())
            Text("Enter the email address on your receipt.")
                .foregroundStyle(CurfewTheme.mutedInk)
            TextField("Purchase email", text: $purchaseEmail)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)
                .onSubmit { requestRestore() }
            if let error = activation.error {
                Text(error).foregroundStyle(CurfewTheme.warning)
            }
            HStack {
                Button("Cancel") {
                    activation.cancel()
                    showingRestore = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                if activation.isBusy {
                    ProgressView().controlSize(.small)
                }
                Button("Send Restore Link", action: requestRestore)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRestore || activation.isBusy)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private var canRestore: Bool {
        let email = purchaseEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        return email.count <= 254 && email.range(
            of: "^[^\\s<>@]+@[^\\s<>@]+\\.[^\\s<>@]+$", options: .regularExpression
        ) != nil
    }

    private func requestRestore() {
        guard canRestore, !activation.isBusy else { return }
        Task {
            await activation.restore(email: purchaseEmail)
            if activation.error == nil {
                showingRestore = false
            }
        }
    }

    private var plusFeatureList: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.featureFlags.widgetKitEnabled {
                plusFeatureRow("Widgets", icon: "rectangle.3.group")
            }
            if model.featureFlags.cloudSyncEnabled {
                plusFeatureRow("Schedule sync across your Macs", icon: "icloud")
            }
            if model.featureFlags.calendarEnabled {
                plusFeatureRow("Today's calendar events", icon: "calendar.badge.clock")
            }
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
