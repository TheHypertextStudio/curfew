import AppKit
import CurfewKit
import SwiftUI

// MARK: The permission

/// Accessibility, alone: one line saying why, and the state of the grant in a
/// place that is always there, so it appears without moving anything. Like
/// every screen's content it sits midway between the heading and the buttons.
struct GettingStartedPermissionContent: View {
    let granted: Bool
    let waiting: Bool
    @Environment(\.setupMetrics) private var metrics

    private var status: String? {
        if granted {
            return GettingStartedCopy.allowed
        }
        return waiting ? GettingStartedCopy.waitingForAccess : nil
    }

    var body: some View {
        VStack(spacing: GettingStartedLayout.spacing16) {
            Text(GettingStartedCopy.accessibilityLine)
                .setupBody(metrics.body)
            ZStack {
                if let status {
                    GettingStartedStatus(text: status, done: granted)
                        .id(status)
                        .transition(.opacity.combined(with: .scale(scale: 0.92)))
                }
            }
            .frame(height: 24)
            .animation(.spring(duration: 0.45, bounce: 0.2), value: status)
        }
    }
}

// MARK: The optional asks

/// Notifications and the Curfew helper, each one row. Nothing here is needed:
/// Continue without touching a row is the skip. A row's button and the state
/// that replaces it share one fixed place.
struct GettingStartedOptionalContent: View {
    let asks: [SetupOptionalAsk]
    let notificationStatus: SetupPermissionStatus
    let helperStatus: SetupHelperStatus
    let onAllowNotifications: () -> Void
    let onInstallHelper: () -> Void
    let onApproveHelper: () -> Void
    @Environment(\.setupMetrics) private var metrics

    var body: some View {
        VStack(spacing: GettingStartedLayout.spacing12) {
            ForEach(asks, id: \.self) { ask in
                HStack(spacing: GettingStartedLayout.spacing16) {
                    Text(ask == .notifications
                        ? GettingStartedCopy.notificationsAsk
                        : GettingStartedCopy.helperAsk)
                        .sundownFont(.body, size: metrics.body)
                    Spacer(minLength: GettingStartedLayout.spacing12)
                    Group {
                        if ask == .notifications {
                            notificationsControl
                        } else {
                            helperControl
                        }
                    }
                    .frame(width: 104, height: 32, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: 440)
        .animation(.spring(duration: 0.45, bounce: 0.2), value: notificationStatus)
        .animation(.spring(duration: 0.45, bounce: 0.2), value: helperStatus)
    }

    @ViewBuilder
    private var notificationsControl: some View {
        switch notificationStatus {
        case .notAsked:
            Button("Allow", action: onAllowNotifications)
                .buttonStyle(GettingStartedSecondaryButtonStyle(compact: true))
                .accessibilityLabel("Allow notifications")
                .accessibilityHint(GettingStartedCopy.notificationsReason)
                .transition(.opacity)
        case .allowed:
            GettingStartedStatus(text: GettingStartedCopy.allowed, done: true)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        case .off:
            GettingStartedStatus(text: "Off", done: false)
                .transition(.opacity)
        }
    }

    @ViewBuilder
    private var helperControl: some View {
        switch helperStatus {
        case .notInstalled:
            Button("Install", action: onInstallHelper)
                .buttonStyle(GettingStartedSecondaryButtonStyle(compact: true))
                .accessibilityLabel("Install the Curfew helper")
                .accessibilityHint(GettingStartedCopy.helperReason)
                .transition(.opacity)
        case .failed:
            Button("Try again", action: onInstallHelper)
                .buttonStyle(GettingStartedSecondaryButtonStyle(compact: true))
                .accessibilityLabel("Try installing the Curfew helper again")
                .transition(.opacity)
        case .installing:
            GettingStartedStatus(text: "Installing", done: false)
                .transition(.opacity)
        case .needsApproval:
            Button("Approve", action: onApproveHelper)
                .buttonStyle(GettingStartedSecondaryButtonStyle(compact: true))
                .accessibilityLabel("Approve the Curfew helper in System Settings")
                .transition(.opacity)
        case .installed:
            GettingStartedStatus(text: "Installed", done: true)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
        }
    }
}

// MARK: Set

/// Setup is committed: when this Mac next locks and, once, what is weaker
/// without the Curfew helper.
struct GettingStartedReadyContent: View {
    let readyLine: String
    let helperNote: String?
    @Environment(\.setupMetrics) private var metrics

    var body: some View {
        VStack(spacing: GettingStartedLayout.spacing12) {
            Text(readyLine)
                .setupBody(metrics.body)
            if let helperNote {
                Text(helperNote)
                    .setupBody(metrics.small)
            }
        }
    }
}

// MARK: Closing offer

/// One optional offer: Curfew Plus, which is what syncs Curfew to the
/// person's other devices. Uses only the app's existing pricing link and
/// account sign-in. Its buttons and the Skip beneath them weigh the same.
struct GettingStartedExtrasContent: View {
    @Environment(CurfewAppModel.self) private var model
    @Environment(\.setupMetrics) private var metrics
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
        VStack(spacing: GettingStartedLayout.spacing16) {
            Text(GettingStartedCopy.plusOffer)
                .setupBody(metrics.body)
                .frame(maxWidth: 480)
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
            .frame(height: 40)
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
