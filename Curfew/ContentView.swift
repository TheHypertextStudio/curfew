import AppKit
import SwiftUI

/// Sidebar sections in the main window. Each case renders a different
/// detail pane via `MainWindowView.detailContent`. Used as both the
/// selection identity and the sidebar label source.
///
/// The spine maps to the product's three verbs: **Trust** today, **Set**
/// your schedule, **Reflect** in the journal. Configuration lives in the
/// ⌘, Settings window, not here.
enum MainWorkspaceSection: String, CaseIterable, Identifiable {
    /// Live status — tonight's curfew at a glance.
    case today
    /// Weekly lock/unlock editor — the core creative act, reused by onboarding.
    case schedule
    /// Reflective archive — the weekly rollup, and soon the nightly entries.
    case journal

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
        case .today:
            "Today"
        case .schedule:
            "Schedule"
        case .journal:
            "Journal"
        }
    }

    /// SF Symbol used in the sidebar row.
    var symbolName: String {
        switch self {
        case .today:
            "sun.horizon"
        case .schedule:
            "calendar"
        case .journal:
            "book.closed"
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

        VStack(spacing: 0) {
            header(snapshot: snapshot)
            CompactEnforcementHealthWarning(health: model.enforcementHealth) {
                model.requestAccessibilityAccess()
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            actions(snapshot: snapshot)
        }
        .frame(width: 320)
        .background(CurfewTheme.canvas)
        .foregroundStyle(CurfewTheme.ink)
    }

    /// Compact sundown header — the countdown over a dusk band.
    private func header(snapshot: EnforcementSnapshot) -> some View {
        ZStack(alignment: .bottomLeading) {
            Self.miniSky
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.timeRemainingText)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(Self.warmWhite)
                Text(headerLine(snapshot))
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(Self.warmWhite.opacity(0.82))
            }
            .padding(18)
        }
        .frame(height: 116)
    }

    private func headerLine(_ snapshot: EnforcementSnapshot) -> String {
        if let lock = model.state.lockDate, snapshot.phase == .working {
            return "until your Mac locks at \(lock.formatted(date: .omitted, time: .shortened))"
        }
        return snapshot.statusLine
    }

    /// Menu-style action rows.
    private func actions(snapshot: EnforcementSnapshot) -> some View {
        VStack(spacing: 2) {
            menuRow("Open Curfew", icon: "sun.horizon", prominent: true) {
                openMainWorkspace()
            }
            if snapshot.canRequestExtension {
                menuRow(snapshot.extensionRequestTitle, icon: "plus.circle") {
                    model.tapExtensionRequest()
                }
                .disabled(snapshot.extensionsRemaining == 0)
                .simultaneousGesture(
                    LongPressGesture(
                        minimumDuration: CurfewAppModel.extensionConfirmationHoldSeconds
                    )
                    .onEnded { _ in model.confirmExtensionRequest() }
                )
            }
            menuRow("Settings", icon: "gearshape") { model.openSettings() }
            menuRow("Getting Started", icon: "sparkles") { model.showGettingStarted() }
            Divider().padding(.vertical, 4)
            menuRow("Quit Curfew", icon: "power") { NSApp.terminate(nil) }
        }
        .padding(10)
    }

    private func menuRow(
        _ title: String,
        icon: String,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)
                    .foregroundStyle(prominent ? CurfewTheme.accent : CurfewTheme.mutedInk)
                Text(title)
                    .font(CurfewTypography.bodyEmphasis(14))
                    .foregroundStyle(CurfewTheme.ink)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static let warmWhite = Color(red: 0.99, green: 0.97, blue: 0.94)
    private static let miniSky = LinearGradient(
        stops: [
            .init(color: Color(red: 0.28, green: 0.27, blue: 0.36), location: 0.0),
            .init(color: Color(red: 0.55, green: 0.42, blue: 0.42), location: 0.6),
            .init(color: Color(red: 0.86, green: 0.62, blue: 0.45), location: 1.0)
        ],
        startPoint: .top,
        endPoint: .bottom
    )

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
    /// Currently-selected sidebar section. Defaults to `.today` (a Debug
    /// demo-capture launch can pin a different pane via `demoLaunchSelection`);
    /// SwiftUI restores the last selection between window appearances.
    @State private var selectedSection: MainWorkspaceSection? = .demoLaunchSelection

    /// Sidebar + detail split layout.
    var body: some View {
        NavigationSplitView {
            List(MainWorkspaceSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbolName)
                    .font(CurfewTypography.bodyEmphasis(15))
                    .tag(section)
                    .padding(.vertical, 6)
            }
            .navigationTitle("Curfew")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 340)
        } detail: {
            detailContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(CurfewTheme.canvas)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(CurfewTheme.accent)
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
    /// Defaults to `.today` if `selectedSection` is momentarily nil
    /// (possible in multi-column navigation during resize animations).
    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection ?? .today {
        case .today:
            TodayView()
                .environmentObject(model)
        case .schedule:
            ScheduleView()
                .environmentObject(model)
        case .journal:
            JournalView()
                .environmentObject(model)
        }
    }
}
