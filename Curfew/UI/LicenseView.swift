import CurfewKit
import SwiftUI

/// Settings panel for entering and managing a Curfew Plus license key.
struct LicenseView: View {
    @Environment(CurfewAppModel.self) private var model
    @State private var keyDraft = ""
    @State private var manualEntryExpanded = false
    @State private var showingRestore = false
    @State private var purchaseEmail = ""
    @State private var restoreRequestID = UUID()

    private var gate: LicenseGate {
        model.licenseGate
    }

    private var activation: LicenseActivationController {
        model.licenseActivation
    }

    /// Panel that swaps between an activation form and the activated
    /// licence summary depending on `LicenseGate.isPlusUnlocked`. Every row
    /// carries its own help and status under its label; the group footer says
    /// what Plus adds.
    var body: some View {
        SettingsGroup("Curfew Plus", footer: gate.isPlusUnlocked ? nil : featureFooter) {
            if gate.isPlusUnlocked {
                unlockedRows
            } else {
                lockedRows
            }
        }
        .sheet(isPresented: $showingRestore) { restoreSheet }
    }

    /// The activation's progress, result or error, shown under the row of
    /// the control that started it.
    private var activationStatus: (text: String, tone: SettingsDetailTone)? {
        if let error = activation
            .error ?? (activation.message == nil ? gate.activationError : nil) {
            return (error, .warning)
        }
        if activation.isBusy {
            return (activation.message ?? "Working…", .secondary)
        }
        if let message = activation.message {
            return (message, .secondary)
        }
        return nil
    }

    // MARK: - Unlocked state

    @ViewBuilder
    private var unlockedRows: some View {
        let status = activationStatus
        SettingsRow(
            title: "Curfew Plus is active",
            detail: status?.text ?? activeSummary,
            tone: status?.tone ?? .secondary
        ) {
            Button("Deactivate license") {
                activation.cancel()
                gate.deactivate()
                keyDraft = ""
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
        }
        .accessibilityIdentifier("license-activation-status")
    }

    /// "Lifetime, for email" or "Subscription, active until (date), for
    /// email", drawn from the activated key's `plan` and `expiresAt`.
    ///
    /// Deliberately says "active until", not "renews": `expiresAt` is the
    /// current period end (plus a grace window) regardless of whether the
    /// subscription is actively renewing or already cancelled and coasting
    /// to that same deadline. Nothing here can tell the two apart, so
    /// "renews" would promise automatic continuation to someone who just
    /// cancelled.
    private var activeSummary: String {
        let email = gate.activatedKey?.email ?? ""
        let owner = email.isEmpty ? "" : ", for \(email)"
        switch gate.activatedKey?.plan {
        case .subscription:
            if let expiresAt = gate.activatedKey?.expiresAt {
                let date = expiresAt.formatted(date: .abbreviated, time: .omitted)
                return "Subscription, active until \(date)\(owner)"
            }
            return "Subscription\(owner)"
        case .lifetime, .none:
            return "Lifetime\(owner)"
        }
    }

    // MARK: - Locked state

    @ViewBuilder
    private var lockedRows: some View {
        let expired = gate.activatedKey != nil
        // A stored-but-expired subscription lands here; nudge toward renewal.
        SettingsRow(
            title: expired ? "Your subscription has expired." : "Get Curfew Plus",
            detail: expired ? "Renew to restore Plus." : "One purchase, or a subscription.",
            tone: expired ? .warning : .secondary
        ) {
            Link(
                expired ? "Renew Curfew Plus" : "Get Curfew Plus",
                destination: LicensePurchase.pricingURL
            )
            .buttonStyle(CurfewSecondaryButtonStyle())
        }

        SettingsActionRow(
            title: "Already bought it",
            detail: "Get a link sent to the email on your receipt.",
            actionTitle: "Restore purchase…"
        ) {
            activation.cancel()
            restoreRequestID = UUID()
            showingRestore = true
        }
        .disabled(activation.isBusy)

        licenseKeyRow
    }

    /// The manual key entry: the row says what it is and shows the
    /// activation's status; the field appears in the same row when opened.
    private var licenseKeyRow: some View {
        let status = activationStatus
        return VStack(alignment: .leading, spacing: 8) {
            SettingsRow(
                title: "License key",
                detail: status?.text ?? "Paste the key from your purchase email.",
                tone: status?.tone ?? .secondary
            ) {
                HStack(spacing: 8) {
                    if activation.isBusy {
                        ProgressView().controlSize(.small)
                    }
                    Button("Enter a license key") {
                        manualEntryExpanded.toggle()
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                    .accessibilityValue(manualEntryExpanded ? "Expanded" : "Collapsed")
                }
            }
            .accessibilityIdentifier("license-activation-status")
            if manualEntryExpanded {
                HStack(spacing: 8) {
                    TextField("License key", text: $keyDraft)
                        .accessibilityLabel("License key")
                        .accessibilityIdentifier("license-key-input")
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
    }

    private var restoreSheet: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Restore purchase").font(.title2.bold())
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
                    restoreRequestID = UUID()
                    activation.cancel()
                    showingRestore = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
                if activation.isBusy {
                    ProgressView().controlSize(.small)
                }
                Button("Send restore link", action: requestRestore)
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
        let requestID = UUID()
        restoreRequestID = requestID
        let email = purchaseEmail
        Task {
            guard showingRestore, restoreRequestID == requestID else { return }
            if await activation.restore(email: email), restoreRequestID == requestID {
                showingRestore = false
            }
        }
    }

    /// What Plus adds, as one sentence under the group.
    private var featureFooter: String? {
        var features: [String] = []
        if model.featureFlags.widgetKitEnabled {
            features.append("widgets")
        }
        if model.featureFlags.cloudSyncEnabled {
            features.append("schedule sync across your Macs")
        }
        if model.featureFlags.calendarEnabled {
            features.append("today's calendar events")
        }
        guard !features.isEmpty else { return nil }
        let list = features.formatted(.list(type: .and))
        return "Plus adds \(list)."
    }
}

/// Single source of truth for where the app sends people to buy Plus. Points at
/// the landing page's pricing section, which presents both the one-time and the
/// subscription options together, rather than embedding two Stripe links here.
enum LicensePurchase {
    static let pricingURL = CurfewServiceEndpoints.current.pricingURL
}
