import AppKit
import CurfewKit
import SwiftUI

// MARK: Step 1

/// Two times and the days they apply to, prefilled from the current schedule.
struct GettingStartedScheduleStep: View {
    @Binding var draft: SetupScheduleDraft

    private var calendar: Calendar {
        .current
    }

    /// Weekdays in the locale's order.
    private var orderedDays: [Weekday] {
        let first = calendar.firstWeekday
        return (0 ..< 7).compactMap { Weekday(rawValue: (first - 1 + $0) % 7 + 1) }
    }

    var body: some View {
        GettingStartedPanel {
            GettingStartedRow(
                symbol: "sunset.fill",
                title: GettingStartedCopy.curfewLabel,
                reason: GettingStartedCopy.curfewReason
            ) {
                timePicker(minutes: $draft.lockMinutes, label: "Curfew time")
            }
            Divider().padding(.leading, 60)
            GettingStartedRow(
                symbol: "sunrise.fill",
                title: GettingStartedCopy.unlockLabel,
                reason: GettingStartedCopy.unlockReason
            ) {
                timePicker(minutes: $draft.unlockMinutes, label: "Unlock time")
            }
            Divider().padding(.leading, 60)
            VStack(alignment: .leading, spacing: GettingStartedLayout.spacing12) {
                Text(GettingStartedCopy.daysLabel)
                    .font(.setupRowTitle)
                    .accessibilityAddTraits(.isHeader)
                HStack(spacing: GettingStartedLayout.spacing8) {
                    ForEach(orderedDays) { day in
                        Toggle(isOn: binding(for: day)) {
                            Text(calendar.shortWeekdaySymbols[day.rawValue - 1])
                                .frame(maxWidth: .infinity)
                        }
                        .toggleStyle(GettingStartedChipStyle())
                        .accessibilityLabel(calendar.weekdaySymbols[day.rawValue - 1])
                    }
                }
            }
            .padding(.leading, 60)
            .padding(.trailing, GettingStartedLayout.spacing16)
            .padding(.vertical, GettingStartedLayout.spacing16)
        }
    }

    private func timePicker(minutes: Binding<Int>, label: String) -> some View {
        DatePicker(label, selection: dateBinding(minutes), displayedComponents: .hourAndMinute)
            .datePickerStyle(.stepperField)
            .labelsHidden()
            .controlSize(.large)
            .accessibilityLabel(label)
    }

    private func binding(for day: Weekday) -> Binding<Bool> {
        Binding(
            get: { draft.workingDays.contains(day) },
            set: { isOn in
                if isOn {
                    draft.workingDays.insert(day)
                } else {
                    draft.workingDays.remove(day)
                }
            }
        )
    }

    private func dateBinding(_ minutes: Binding<Int>) -> Binding<Date> {
        let calendar = calendar
        let midnight = calendar.startOfDay(for: Date())
        return Binding(
            get: { midnight.addingTimeInterval(TimeInterval(minutes.wrappedValue * 60)) },
            set: { date in
                let parts = calendar.dateComponents([.hour, .minute], from: date)
                minutes.wrappedValue = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            }
        )
    }
}

// MARK: Step 2

/// Notifications and the Curfew helper first, each optional with one line
/// saying why; Accessibility last, because granting it moves setup on.
struct GettingStartedPermissionsStep: View {
    let notificationStatus: SetupPermissionStatus
    let helperStatus: SetupHelperStatus
    let showsHelper: Bool
    let accessibilityGranted: Bool
    let onAllowNotifications: () -> Void
    let onInstallHelper: () -> Void
    let onApproveHelper: () -> Void
    let onOpenAccessibility: () -> Void

    var body: some View {
        GettingStartedPanel {
            GettingStartedRow(
                symbol: "bell.fill",
                title: GettingStartedCopy.notificationsTitle,
                reason: GettingStartedCopy.notificationsReason
            ) {
                switch notificationStatus {
                case .notAsked:
                    Button("Allow", action: onAllowNotifications)
                        .buttonStyle(GettingStartedSecondaryButtonStyle())
                        .accessibilityLabel("Allow notifications")
                case .allowed:
                    GettingStartedStatus(text: "Allowed", done: true)
                case .off:
                    GettingStartedStatus(text: "Off", done: false)
                }
            }
            if showsHelper {
                Divider().padding(.leading, 60)
                GettingStartedRow(
                    symbol: "lock.shield.fill",
                    title: GettingStartedCopy.helperTitle,
                    reason: GettingStartedCopy.helperReason
                ) {
                    switch helperStatus {
                    case .notInstalled:
                        Button("Install", action: onInstallHelper)
                            .buttonStyle(GettingStartedSecondaryButtonStyle())
                            .accessibilityLabel("Install the Curfew helper")
                    case .failed:
                        Button("Try again", action: onInstallHelper)
                            .buttonStyle(GettingStartedSecondaryButtonStyle())
                            .accessibilityLabel("Try installing the Curfew helper again")
                    case .installing:
                        HStack(spacing: GettingStartedLayout.spacing8) {
                            ProgressView().controlSize(.small)
                            Text("Installing").foregroundStyle(CurfewTheme.mutedInk)
                        }
                        .accessibilityElement(children: .combine)
                    case .needsApproval:
                        Button("Approve", action: onApproveHelper)
                            .buttonStyle(GettingStartedSecondaryButtonStyle())
                            .accessibilityLabel("Approve the Curfew helper in System Settings")
                    case .installed:
                        GettingStartedStatus(text: "Installed", done: true)
                    }
                }
            }
            Divider().padding(.leading, 60)
            GettingStartedRow(
                symbol: "accessibility",
                title: GettingStartedCopy.accessibilityTitle,
                reason: GettingStartedCopy.accessibilityReason
            ) {
                if accessibilityGranted {
                    GettingStartedStatus(text: "Allowed", done: true)
                } else {
                    Button(GettingStartedCopy.openSystemSettings, action: onOpenAccessibility)
                        .buttonStyle(GettingStartedPrimaryButtonStyle())
                        .accessibilityHint(
                            "Opens Accessibility with Curfew ready to drag into the list."
                        )
                }
            }
        }
    }
}

// MARK: Step 3

struct GettingStartedReadyStep: View {
    let readyLine: String
    let helperNote: String?
    let onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: GettingStartedLayout.spacing24) {
            Label(readyLine, systemImage: "sunset.fill")
                .font(.system(.title2, design: .rounded, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onPreview) {
                Label(GettingStartedCopy.previewLock, systemImage: "lock.fill")
            }
            .buttonStyle(GettingStartedSecondaryButtonStyle())
            .accessibilityHint("Shows the lock for a few seconds. Nothing locks.")
            if let helperNote {
                Text(helperNote)
                    .font(.callout)
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: Closing step

/// Optional: sign in to sync, and the lifetime licence. Both use the app's
/// existing account and licence paths.
struct GettingStartedExtrasStep: View {
    @Environment(CurfewAppModel.self) private var model
    @StateObject private var account: AccountEnrollmentController
    let onTookExtra: () -> Void

    @MainActor
    init(
        makeAccount: @escaping @MainActor () -> AccountEnrollmentController,
        onTookExtra: @escaping () -> Void
    ) {
        _account = StateObject(wrappedValue: makeAccount())
        self.onTookExtra = onTookExtra
    }

    var body: some View {
        GettingStartedPanel {
            GettingStartedRow(
                symbol: "arrow.triangle.2.circlepath",
                title: GettingStartedCopy.syncTitle,
                reason: GettingStartedCopy.syncReason
            ) {
                syncControl
            }
            Divider().padding(.leading, 60)
            GettingStartedRow(
                symbol: "seal.fill",
                title: GettingStartedCopy.licenceTitle,
                reason: GettingStartedCopy.licenceReason
            ) {
                if model.licenseGate.isPlusUnlocked {
                    GettingStartedStatus(text: "Active", done: true)
                } else {
                    Button(GettingStartedCopy.getLicence) {
                        onTookExtra()
                        guard !model.isDemoSession,
                              !RuntimeEnvironment.isUnitTestHost else { return }
                        NSWorkspace.shared.open(LicensePurchase.pricingURL)
                    }
                    .buttonStyle(GettingStartedSecondaryButtonStyle())
                    .accessibilityHint("Opens Curfew pricing in your browser.")
                }
            }
        }
        .background { GettingStartedWindowReader { account.presentationWindow = $0 } }
        .onChange(of: account.state) { _, state in
            if case .ready(let enrollment) = state {
                model.settings.accountSync.enrollment = enrollment
                onTookExtra()
            }
        }
    }

    @ViewBuilder
    private var syncControl: some View {
        if model.settings.accountSync.isEnrolled {
            GettingStartedStatus(text: "On", done: true)
        } else {
            switch account.state {
            case .accountFree, .failed:
                Button(GettingStartedCopy.signInToSync) {
                    Task { await account.signIn() }
                }
                .buttonStyle(GettingStartedSecondaryButtonStyle())
            case .signingIn, .connectingDevice:
                HStack(spacing: GettingStartedLayout.spacing8) {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { account.cancelSignIn() }
                        .buttonStyle(GettingStartedSecondaryButtonStyle())
                        .accessibilityLabel("Cancel sign in")
                }
            case .ready:
                GettingStartedStatus(text: "On", done: true)
            case .storageUnavailable, .finishDeviceConnection, .finishDeviceRegistration,
                 .finishRecoverySetup, .saveRecoveryKey, .enterRecoveryKey:
                // The remaining account steps (recovery key and the like)
                // live in Settings, which resumes from the saved checkpoint.
                Button("Finish in Settings") {
                    onTookExtra()
                    model.settingsDestination = .account
                    model.openSettings()
                }
                .buttonStyle(GettingStartedSecondaryButtonStyle())
            }
        }
    }
}

// MARK: Shared pieces

struct GettingStartedRow<Trailing: View>: View {
    let symbol: String
    let title: String
    let reason: String
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: GettingStartedLayout.spacing16) {
            Image(systemName: symbol)
                .font(.system(.title3, weight: .medium))
                .foregroundStyle(CurfewTheme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GettingStartedLayout.spacing4) {
                Text(title).font(.setupRowTitle)
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: GettingStartedLayout.spacing12)
            trailing
        }
        .padding(.horizontal, GettingStartedLayout.spacing16)
        .padding(.vertical, GettingStartedLayout.spacing16)
    }
}

/// A row's live state, in words with a symbol so colour is never the signal.
struct GettingStartedStatus: View {
    let text: String
    let done: Bool

    var body: some View {
        Label(text, systemImage: done ? "checkmark.circle.fill" : "minus.circle")
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundStyle(done ? CurfewTheme.accent : CurfewTheme.mutedInk)
    }
}

/// Hands the hosting window to the account sign-in so its browser sheet has
/// an anchor.
private struct GettingStartedWindowReader: NSViewRepresentable {
    let resolve: @MainActor (NSWindow?) -> Void

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_ view: NSView, context _: Context) {
        let resolve = resolve
        DispatchQueue.main.async { resolve(view.window) }
    }
}
