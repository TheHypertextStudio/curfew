import AppKit
import SwiftUI

/// Sidebar sections in the main window. Each case renders a different
/// detail pane via `MainWindowView.detailContent`. Used as both the
/// selection identity and the sidebar label source.
enum MainWorkspaceSection: String, CaseIterable, Identifiable {
    /// Status dashboard — current phase, time remaining, this-week rollup.
    case overview
    /// Wraps the full Settings view so configuration is reachable without
    /// the system Settings window.
    case configuration
    /// First-launch walkthrough — schedule, extension budget, warnings.
    case onboarding

    /// Stable `WindowGroup` id used by `openWindow(_:)` to focus the
    /// existing main window instead of spawning duplicates.
    static let windowID = "main-workspace"

    /// `Identifiable` conformance — raw string is already unique.
    var id: String {
        rawValue
    }

    /// Sidebar label.
    var title: String {
        switch self {
        case .overview:
            "Overview"
        case .configuration:
            "Configuration"
        case .onboarding:
            "Getting Started"
        }
    }

    /// SF Symbol used in the sidebar row.
    var symbolName: String {
        switch self {
        case .overview:
            "gauge.with.dots.needle.67percent"
        case .configuration:
            "slider.horizontal.3"
        case .onboarding:
            "sparkles"
        }
    }
}

/// Compact menu-bar popover. Shows the live status snapshot plus quick
/// actions (open workspace, request extension, open settings, quit).
/// The full UI is in `MainWindowView`; this view is tight and fixed-width
/// because the menu bar allots limited vertical space.
struct ContentView: View {
    /// Live app state — snapshot reads the derived display fields.
    @EnvironmentObject private var model: CurfewAppModel
    /// SwiftUI `openWindow` action so the popover can raise the main
    /// `WindowGroup` identified by `MainWorkspaceSection.windowID`.
    @Environment(\.openWindow) private var openWindow

    /// Menu-bar popover content.
    var body: some View {
        let snapshot = model.snapshot

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Curfew")
                        .font(CurfewTypography.title(22))
                    Text(snapshot.statusLine)
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }

                Spacer()

                Label(snapshot.timeRemainingText, systemImage: snapshot.symbolName)
                    .font(CurfewTypography.numeric(22))
                    .monospacedDigit()
                    .foregroundStyle(CurfewTheme.accent)
            }

            CurfewPanel {
                CurfewSectionTitle(
                    title: "Today",
                    subtitle: snapshot.scheduleWindowText
                )

                if let pending = snapshot.pendingScheduleDescription {
                    Text(pending)
                        .font(CurfewTypography.body(13))
                        .foregroundStyle(CurfewTheme.warning)
                }
            }

            CurfewPanel {
                CurfewSectionTitle(title: "Quick Actions")

                Button("Open Curfew") {
                    openMainWorkspace()
                }
                .buttonStyle(CurfewPrimaryButtonStyle())

                if snapshot.canRequestExtension {
                    Button(snapshot.extensionRequestTitle) {
                        model.tapExtensionRequest()
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                    .disabled(snapshot.extensionsRemaining == 0)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: CurfewAppModel
                            .extensionConfirmationHoldSeconds)
                            .onEnded { _ in
                                model.confirmExtensionRequest()
                            }
                    )
                }

                HStack(spacing: 10) {
                    Button("Settings") {
                        model.openSettings()
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())

                    Button("Getting Started") {
                        model.showGettingStarted()
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                }

                Button("Quit Curfew") {
                    NSApp.terminate(nil)
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
            }
        }
        .padding(14)
        .frame(width: 350)
        .background(CurfewTheme.canvas)
        .foregroundStyle(CurfewTheme.ink)
    }

    private func openMainWorkspace() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: MainWorkspaceSection.windowID)
    }
}

/// Main application window — a `NavigationSplitView` with a sidebar of
/// `MainWorkspaceSection` cases and a detail pane that swaps in the
/// corresponding section view. Also hosts the MCP consent sheet so every
/// pending AI write request is surfaced while the user is at the app.
struct MainWindowView: View {
    /// Live app state shared across detail panes.
    @EnvironmentObject private var model: CurfewAppModel
    /// Currently-selected sidebar section. Defaults to `.overview` on
    /// first display; SwiftUI restores the last selection between
    /// window appearances within a session.
    @State private var selectedSection: MainWorkspaceSection? = .overview

    /// Sidebar + detail split layout.
    var body: some View {
        NavigationSplitView {
            List(MainWorkspaceSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbolName)
                    .font(CurfewTypography.bodyEmphasis(14))
                    .foregroundStyle(CurfewTheme.ink)
                    .tag(section)
                    .padding(.vertical, 4)
                    .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(CurfewTheme.canvasStrong)
            .navigationTitle("Curfew")
            .listStyle(.sidebar)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(CurfewTheme.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(CurfewTheme.accent)
        .onAppear {
            #if DEBUG
                if let demoSection = model.demoInitialSection {
                    selectedSection = demoSection
                }
            #endif
        }
        // Surface MCP consent sheet whenever a new AI write request arrives.
        .sheet(item: Binding(
            get: { model.pendingMCPRequests.first },
            set: { _ in }
        )) { request in
            MCPConsentSheet(
                request: request,
                onApprove: { model.approveMCPRequest(request) },
                onDeny: { model.denyMCPRequest(request) }
            )
        }
    }

    /// Detail pane dispatcher — one case per `MainWorkspaceSection`.
    /// Defaults to `.overview` if `selectedSection` is momentarily nil
    /// (possible in multi-column navigation during resize animations).
    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection ?? .overview {
        case .overview:
            MainOverviewSectionView()
                .environmentObject(model)
        case .configuration:
            MainConfigurationSectionView()
                .environmentObject(model)
        case .onboarding:
            MainOnboardingSectionView()
                .environmentObject(model)
        }
    }
}

/// Overview detail pane — live status, this-week rollup, tomorrow's
/// summary, and the armed/disarmed action block.
private struct MainOverviewSectionView: View {
    @EnvironmentObject private var model: CurfewAppModel

    /// Scrolling layout so narrow windows don't truncate the action block.
    var body: some View {
        let snapshot = model.snapshot

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !model.isAccessibilityTrusted {
                    AccessibilityPermissionBanner()
                }
                CurfewPanel {
                    CurfewSectionTitle(title: "Status", subtitle: snapshot.statusLine)

                    Text("\(snapshot.timeRemainingText) remaining")
                        .font(CurfewTypography.display(34))
                        .monospacedDigit()
                        .foregroundStyle(CurfewTheme.accent)

                    Text(snapshot.scheduleWindowText)
                        .font(CurfewTypography.body(14))
                        .foregroundStyle(CurfewTheme.mutedInk)
                }

                ThisWeekView()
                    .environmentObject(model)

                CurfewPanel {
                    CurfewSectionTitle(
                        title: "Tomorrow",
                        subtitle: snapshot.scheduleSummarySentence
                    )
                    if let pending = snapshot.pendingScheduleDescription {
                        Text(pending)
                            .font(CurfewTypography.body(14))
                            .foregroundStyle(CurfewTheme.warning)
                    }
                }

                CurfewPanel {
                    CurfewSectionTitle(title: "Actions")

                    if !model.settings.hasCompletedInitialSetup {
                        Text(
                            "Setup is not complete. Curfew stays disarmed until you complete setup."
                        )
                        .font(CurfewTypography.body(14))
                        .foregroundStyle(CurfewTheme.mutedInk)

                        Button("Complete Setup and Enable Curfew") {
                            model.completeInitialSetup()
                        }
                        .buttonStyle(CurfewPrimaryButtonStyle())
                    } else if !model.isEnforcementRunning {
                        Text(
                            "Debug launches are safe by default. Start enforcement manually "
                                + "when you want to test lock behavior."
                        )
                        .font(CurfewTypography.body(14))
                        .foregroundStyle(CurfewTheme.mutedInk)

                        Button("Start Enforcement") {
                            model.start()
                        }
                        .buttonStyle(CurfewPrimaryButtonStyle())
                    } else {
                        Text("Enforcement is currently active.")
                            .font(CurfewTypography.body(14))
                            .foregroundStyle(CurfewTheme.accentMuted)
                    }

                    HStack(spacing: 10) {
                        Button("Open Settings") {
                            model.openSettings()
                        }
                        .buttonStyle(CurfewSecondaryButtonStyle())

                        Button("Show Getting Started") {
                            model.showGettingStarted()
                        }
                        .buttonStyle(CurfewSecondaryButtonStyle())
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}

/// Warning shown atop the Overview pane when the host process is not in
/// the system Accessibility allow-list. Without that trust the
/// CGEventTap that blocks bypass keys (⌘⇥, ⌘Q, ⌘⌥Esc, …) silently fails
/// at install time and the user gets a weaker lockout without knowing.
/// The banner deep-links to System Settings → Privacy & Security so the
/// user can grant the permission in two clicks.
private struct AccessibilityPermissionBanner: View {
    var body: some View {
        CurfewPanel {
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "Accessibility permission required",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(CurfewTypography.bodyEmphasis(14))
                .foregroundStyle(CurfewTheme.warning)

                Text(
                    "Curfew needs the Accessibility permission to block bypass "
                        + "shortcuts (⌘⇥, ⌘Q, …) during lockout. Without it the "
                        + "lockout overlay still appears, but bypass keys pass through."
                )
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)

                Button("Open System Settings") {
                    let path = "com.apple.preference.security?Privacy_Accessibility"
                    if let url = URL(string: "x-apple.systempreferences:" + path) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
            }
        }
    }
}

/// Configuration detail pane — delegates to `SettingsView` with
/// `tabbed: false` so it renders as a scrollable column instead of the
/// system-Settings tab bar.
private struct MainConfigurationSectionView: View {
    @EnvironmentObject private var model: CurfewAppModel

    /// Delegates layout to the shared Settings view.
    var body: some View {
        SettingsView(tabbed: false)
            .environmentObject(model)
    }
}

/// First-launch walkthrough pane — summarises the three setup steps and
/// links into the dedicated Getting Started window for the full flow.
private struct MainOnboardingSectionView: View {
    @EnvironmentObject private var model: CurfewAppModel

    /// Three-item checklist with deep-link buttons.
    var body: some View {
        ScrollView {
            CurfewPanel {
                CurfewSectionTitle(
                    title: "Getting Started",
                    subtitle: "Set your schedule first, then arm enforcement when you are ready."
                )

                VStack(alignment: .leading, spacing: 8) {
                    Label(ScheduleSurfaceCopy.mainChecklistItem, systemImage: "calendar")
                    Label("Configure extension and override limits.", systemImage: "hourglass")
                    Label("Tune warnings and optional auto-shutdown.", systemImage: "bell")
                }
                .font(CurfewTypography.bodyEmphasis(14))
                .foregroundStyle(CurfewTheme.ink)

                HStack(spacing: 10) {
                    Button("Open Getting Started Window") {
                        model.showGettingStarted()
                    }
                    .buttonStyle(CurfewPrimaryButtonStyle())

                    Button("Open Settings") {
                        model.openSettings()
                    }
                    .buttonStyle(CurfewSecondaryButtonStyle())
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }
}
