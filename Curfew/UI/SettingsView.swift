import Combine
import CurfewKit
import SwiftUI

/// Native sidebar settings. Schedule and Journal remain workspace destinations.
struct SettingsView: View {
    @Environment(CurfewAppModel.self) var model
    @Environment(\.openWindow) var openWindow
    @State var selection: SettingsSection? = .general
    @State var didCopyConfig = false
    @State var manualSetupExpanded = false
    @State var registrationStatus = ClaudeDesktopRegistration.currentStatus()

    @StateObject var accountEnrollment = AccountEnrollmentController.settingsController()
    @State var accountRecoveryKey = ""
    @State var recoveryKeyExportMessage = ""

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .font(.system(size: 13))
                    .tag(section)
                    .accessibilityIdentifier("settings-\(section.rawValue)-tab")
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .padding(.top, 12)
            .frame(width: 180)
            .background(CurfewTheme.canvasStrong)
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                Text((selection ?? .general).title)
                    .font(.system(size: 22, weight: .semibold))
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 4)
                Form {
                    switch selection ?? .general {
                    case .general:
                        enforcementHealthPanel
                        if model.featureFlags.privilegedHelperEnabled {
                            privilegedHelperPanel
                        }
                        setupPanel
                    case .enforcement:
                        extensionsPanel
                        presencePanel
                    case .warnings:
                        warningPanel
                        shutdownPanel
                        protectedWorkPanel
                    case .integrations:
                        integrationsPanel
                    case .advanced:
                        advancedPanel
                        uninstallPanel
                    case .about:
                        aboutPanel
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .accessibilityIdentifier("settings-detail")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CurfewTheme.canvas)
        }
        .tint(CurfewTheme.accent)
        .background {
            SettingsWindowReader { window in
                accountEnrollment.presentationWindow = window
            }
        }
        .onAppear {
            refreshSystemState()
            selection = model.settingsDestination
            #if DEBUG
                if model.isDemoSession {
                    registrationStatus = DemoReviewState
                        .current == .claudeConfigured ? .alreadyRegistered : .claudeNotInstalled
                }
                if model.isDemoSession,
                   let raw = ProcessInfo.processInfo.environment["CURFEW_DEMO_SETTINGS_SECTION"],
                   let section = SettingsSection(rawValue: raw) {
                    selection = section
                }
            #endif
        }
        .onChange(of: selection) { _, section in
            if let section {
                model.settingsDestination = section
            }
        }
        .onChange(of: model.settingsDestination) { _, destination in selection = destination }
        .onReceive(Timer.publish(
            every: CurfewAppModel.privilegedHeartbeatInterval, on: .main, in: .common
        ).autoconnect()) { _ in
            refreshSystemState()
        }
        .onReceive(NotificationCenter.default
            .publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                refreshSystemState()
        }
    }

    /// Refresh out-of-process changes on return, without overwriting demo state.
    private func refreshSystemState() {
        #if DEBUG
            if ProcessInfo.processInfo.environment["CURFEW_DEMO_FIXTURE"] == "1" {
                return
            }
        #endif
        model.refreshAccessibilityTrust()
        model.privilegedHelperManager.refreshStatus()
        if model.featureFlags.privilegedHelperEnabled {
            Task { await model.privilegedHelperManager.reconcileDaemonStatus() }
        }
        registrationStatus = ClaudeDesktopRegistration.currentStatus()
    }
}

final class SettingsWindowReaderView: NSView {
    var resolve: @MainActor (NSWindow?) -> Void

    init(resolve: @escaping @MainActor (NSWindow?) -> Void) {
        self.resolve = resolve
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resolve(window)
    }
}

private struct SettingsWindowReader: NSViewRepresentable {
    let resolve: @MainActor (NSWindow?) -> Void

    func makeNSView(context _: Context) -> SettingsWindowReaderView {
        SettingsWindowReaderView(resolve: resolve)
    }

    func updateNSView(_ view: SettingsWindowReaderView, context _: Context) {
        view.resolve = resolve
        resolve(view.window)
    }
}
