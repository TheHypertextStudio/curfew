import Combine
import CurfewKit
import SwiftUI

/// Settings keeps each category on its own page while preserving shared account state.
struct SettingsView: View {
    /// Live app state shared across panels.
    @Environment(CurfewAppModel.self) var model
    @Environment(\.openWindow) var openWindow
    @State var didCopyConfig = false
    @State var manualSetupExpanded = false
    @State var registrationStatus = ClaudeDesktopRegistration.currentStatus()
    @State var recoveryKeyExportMessage = ""
    private let initialSection: SettingsSection?

    /// Retain navigation while the Settings window remains open.
    @State var selection: SettingsSection = .enforcement
    @StateObject var accountEnrollment = AccountEnrollmentController.settingsController()
    @State var accountRecoveryKey = ""
    @State var showsBrowserIntegration = false
    @State var showsOtherIntegrations = false
    @State var showsAIPermissions = false
    @State var showsWarningTimes = false
    @State var showsPresencePrivacy = false
    @State var showsDeferringCommands = false
    @State var showsProtectedProcesses = false

    init(initialSection: SettingsSection? = nil, expandedDetails: Bool = false) {
        self.initialSection = initialSection
        _showsAIPermissions = State(initialValue: expandedDetails)
        _showsWarningTimes = State(initialValue: expandedDetails)
        _showsPresencePrivacy = State(initialValue: expandedDetails)
        _showsDeferringCommands = State(initialValue: expandedDetails)
        _showsProtectedProcesses = State(initialValue: expandedDetails)
        #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            let showsBrowserFixture = environment["CURFEW_DEMO_FIXTURE"] == "1" &&
                environment["CURFEW_DEMO_SCENARIO"] == DemoScenario.settings.rawValue
            _selection =
                State(initialValue: initialSection ??
                    (showsBrowserFixture ? .integrations : .enforcement))
            _showsBrowserIntegration = State(initialValue: showsBrowserFixture)
        #else
            _selection = State(initialValue: initialSection ?? .enforcement)
        #endif
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(selection.title)
                        .accessibilityIdentifier("settings-page-title")
                        .font(CurfewTypography.title(26))
                        .accessibilityAddTraits(.isHeader)
                    if selection == .general {
                        Spacer()
                        Button {
                            model.showGettingStarted()
                        } label: {
                            if model.settings.hasCompletedInitialSetup {
                                Text("Review Setup…")
                            } else {
                                Text("Continue Setup…")
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 4)
                Form {
                    page
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .id(selection)
                .accessibilityIdentifier("settings-page-\(selection.id)")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(CurfewTheme.canvas)
        }
        .tint(CurfewTheme.accent)
        .background(CurfewTheme.canvas)
        .background {
            SettingsWindowReader { window in
                accountEnrollment.presentationWindow = window
            }
        }
        .onAppear {
            refreshSystemState()
            selection = initialSection ?? model.settingsDestination
            #if DEBUG
                if initialSection == nil, model.isDemoSession,
                   DemoReviewState.current == .normal,
                   ProcessInfo.processInfo.environment["CURFEW_DEMO_SCENARIO"] == "settings" {
                    selection = .integrations
                }
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
            model.settingsDestination = section
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

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(CurfewTypography.title(18))
                .padding(.horizontal, 24)
                .padding(.top, 20)
            List(selection: Binding<SettingsSection?>(
                get: { selection },
                set: {
                    if let section = $0 {
                        selection = section
                    }
                }
            )) {
                Section {
                    navigationGroup([.general, .enforcement, .presence, .shutdown, .protectedWork])
                }
                Section {
                    navigationGroup([.account, .integrations])
                }
                Section {
                    navigationGroup([.advanced, .about])
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .frame(width: 204)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(CurfewTheme.canvasStrong)
    }

    private func navigationGroup(_ sections: [SettingsSection]) -> some View {
        ForEach(sections) { section in
            Label(section.title, systemImage: section.icon)
                .font(CurfewTypography.bodyEmphasis(13))
                .tag(section)
                .accessibilityIdentifier("settings-category-\(section.id)")
        }
    }

    @ViewBuilder
    private var page: some View {
        switch selection {
        case .general:
            enforcementHealthPanel
            if model.featureFlags.privilegedHelperEnabled {
                privilegedHelperPanel
            }
            setupPanel
        case .enforcement:
            extensionsPanel
            warningPanel
        case .presence:
            presencePanel
        case .shutdown:
            shutdownPanel
        case .protectedWork:
            protectedWorkPanel
        case .account:
            coordinatorSyncPanel
            if model.featureFlags.cloudSyncEnabled, !model.settings.accountSync.isEnrolled {
                devicesPanel
            }
        case .integrations:
            integrationsPanel
        case .advanced:
            advancedPanel
            uninstallPanel
        case .about:
            aboutPanel
        }
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
