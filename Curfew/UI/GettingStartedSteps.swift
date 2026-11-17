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

/// Accessibility first, because it is the one required grant and granting it
/// moves setup on; then notifications and the Curfew helper, each marked
/// optional, each with one line saying why.
struct GettingStartedPermissionsStep: View {
    let notificationStatus: SetupPermissionStatus
    let helperStatus: SetupHelperStatus
    let showsHelper: Bool
    let accessibilityGranted: Bool
    let notificationsSkipped: Bool
    let helperSkipped: Bool
    let onSkipNotifications: () -> Void
    let onSkipHelper: () -> Void
    let onAllowNotifications: () -> Void
    let onInstallHelper: () -> Void
    let onApproveHelper: () -> Void
    let onOpenAccessibility: () -> Void

    var body: some View {
        GettingStartedPanel {
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
            Divider().padding(.leading, 60)
            GettingStartedRow(
                symbol: "bell.fill",
                title: GettingStartedCopy.notificationsTitle,
                reason: GettingStartedCopy.notificationsReason,
                isOptional: true
            ) {
                switch notificationStatus {
                case .notAsked where notificationsSkipped:
                    GettingStartedStatus(text: "Skipped", done: false)
                case .notAsked:
                    HStack(spacing: GettingStartedLayout.spacing12) {
                        Button("Skip", action: onSkipNotifications)
                            .buttonStyle(GettingStartedLinkButtonStyle())
                            .accessibilityLabel("Skip notifications")
                        Button("Allow", action: onAllowNotifications)
                            .buttonStyle(GettingStartedSecondaryButtonStyle())
                            .accessibilityLabel("Allow notifications")
                    }
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
                    reason: GettingStartedCopy.helperReason,
                    isOptional: true
                ) {
                    helperControl
                }
            }
        }
    }

    @ViewBuilder
    private var helperControl: some View {
        switch helperStatus {
        case .notInstalled where helperSkipped, .failed where helperSkipped:
            GettingStartedStatus(text: "Skipped", done: false)
        case .notInstalled:
            HStack(spacing: GettingStartedLayout.spacing12) {
                Button("Skip", action: onSkipHelper)
                    .buttonStyle(GettingStartedLinkButtonStyle())
                    .accessibilityLabel("Skip the Curfew helper")
                Button("Install", action: onInstallHelper)
                    .buttonStyle(GettingStartedSecondaryButtonStyle())
                    .accessibilityLabel("Install the Curfew helper")
            }
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

// MARK: Step 3

struct GettingStartedReadyStep: View {
    let readyLine: String
    let helperNote: String?
    let onPreview: () -> Void
    @ScaledMetric(relativeTo: .largeTitle) private var heroSize: CGFloat = 40

    var body: some View {
        VStack(alignment: .leading, spacing: GettingStartedLayout.spacing24) {
            Text(readyLine)
                .font(.system(size: heroSize, weight: .bold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: GettingStartedLayout.spacing12) {
                Button(action: onPreview) {
                    Label(GettingStartedCopy.previewLock, systemImage: "lock.fill")
                }
                .buttonStyle(GettingStartedSecondaryButtonStyle())
                .accessibilityHint("Shows the lock for a few seconds. Nothing locks.")
                if let helperNote {
                    Text(helperNote)
                        .font(.footnote)
                        .foregroundStyle(CurfewTheme.mutedInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.top, GettingStartedLayout.spacing40)
    }
}

// MARK: Closing step

/// One optional offer: Curfew Plus, which is what syncs Curfew to the
/// person's other devices. Uses only the app's existing pricing link and
/// account sign-in.
struct GettingStartedExtrasStep: View {
    @Environment(CurfewAppModel.self) private var model
    @StateObject private var account: AccountEnrollmentController
    let onSignedIn: () -> Void

    @MainActor
    init(
        makeAccount: @escaping @MainActor () -> AccountEnrollmentController,
        onSignedIn: @escaping () -> Void
    ) {
        _account = StateObject(wrappedValue: makeAccount())
        self.onSignedIn = onSignedIn
    }

    private var isSignedIn: Bool {
        if model.settings.accountSync.isEnrolled {
            return true
        }
        if case .ready = account.state {
            return true
        }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GettingStartedLayout.spacing24) {
            Text(GettingStartedCopy.plusOffer)
                .font(.title3)
                .foregroundStyle(CurfewTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: GettingStartedLayout.spacing12) {
                if model.licenseGate.isPlusUnlocked {
                    GettingStartedStatus(text: "Curfew Plus is active", done: true)
                } else {
                    Button(GettingStartedCopy.getPlus) {
                        guard !model.isDemoSession,
                              !RuntimeEnvironment.isUnitTestHost else { return }
                        NSWorkspace.shared.open(LicensePurchase.pricingURL)
                    }
                    .buttonStyle(GettingStartedSecondaryButtonStyle())
                    .accessibilityHint("Opens Curfew Plus pricing in your browser.")
                }
                signInControl
            }
        }
        .background { GettingStartedWindowReader { account.presentationWindow = $0 } }
        .onAppear {
            if isSignedIn {
                onSignedIn()
            }
        }
        .onChange(of: account.state) { _, state in
            if case .ready(let enrollment) = state {
                model.settings.accountSync.enrollment = enrollment
                onSignedIn()
            }
        }
    }

    @ViewBuilder
    private var signInControl: some View {
        if isSignedIn {
            GettingStartedStatus(text: "Signed in", done: true)
        } else {
            switch account.state {
            case .accountFree, .failed, .ready:
                Button(GettingStartedCopy.signIn) {
                    Task { await account.signIn() }
                }
                .buttonStyle(GettingStartedSecondaryButtonStyle())
                .accessibilityHint("For people who already have Curfew Plus.")
            case .signingIn, .connectingDevice:
                HStack(spacing: GettingStartedLayout.spacing8) {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { account.cancelSignIn() }
                        .buttonStyle(GettingStartedSecondaryButtonStyle())
                        .accessibilityLabel("Cancel sign in")
                }
            case .storageUnavailable, .finishDeviceConnection, .finishDeviceRegistration,
                 .finishRecoverySetup, .saveRecoveryKey, .enterRecoveryKey:
                // The remaining account steps (recovery key and the like)
                // live in Settings, which resumes from the saved checkpoint.
                Button("Finish in Settings") {
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
    var isOptional = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: GettingStartedLayout.spacing16) {
            Image(systemName: symbol)
                .font(.system(.title3, weight: .medium))
                .foregroundStyle(CurfewTheme.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: GettingStartedLayout.spacing4) {
                HStack(alignment: .firstTextBaseline, spacing: GettingStartedLayout.spacing8) {
                    Text(title).font(.setupRowTitle)
                    if isOptional {
                        Text("Optional")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(CurfewTheme.mutedInk)
                    }
                }
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
