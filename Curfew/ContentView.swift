import AppKit
import CurfewKit
import SwiftUI

/// Sidebar sections in the main window. Each case renders a different
/// detail pane via `MainWindowView.detailContent`. Used as both the
/// selection identity and the sidebar label source.
///
/// The spine maps to the product's three verbs: **Trust** today, **Set**
/// your schedule, **Reflect** in the journal — where reading past entries and
/// editing the prompts you answer both live. Only system/enforcement
/// configuration lives in the ⌘, Settings window.
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
    @Environment(CurfewAppModel.self) private var model
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

    /// Compact sundown header — the countdown over the live sky, which melts
    /// into the popover canvas at the bottom so there's no hard seam.
    private func header(snapshot: EnforcementSnapshot) -> some View {
        ZStack(alignment: .topLeading) {
            SundownSky(moment: model.skyMoment)
                .overlay(alignment: .bottom) {
                    LinearGradient(
                        colors: [.clear, CurfewTheme.canvas],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 48)
                }
            VStack(alignment: .leading, spacing: 4) {
                Text(snapshot.timeRemainingText)
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(SundownPalette.warmWhite)
                Text(headerLine(snapshot))
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(SundownPalette.warmWhite.opacity(0.82))
            }
            .padding(.horizontal, 18)
            .padding(.top, 18)
        }
        .frame(height: 128)
        .clipped()
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

    private func openMainWorkspace() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: MainWorkspaceSection.windowID)
    }
}

/// Main application window — `NavigationSplitView` whose detail column carries
/// `.backgroundExtensionEffect()` on the `SundownSky` view. This is the
/// macOS 26 public API for bleeding a detail-column background behind the
/// floating sidebar glass: the system mirrors and blurs the sky into the
/// sidebar's safe-area edge so the `NSGlassEffectView` that backs the sidebar
/// refracts sky colours rather than the desktop wallpaper behind the window.
struct MainWindowView: View {
    /// Live app state shared across detail panes.
    @Environment(CurfewAppModel.self) private var model
    /// Opens the Getting Started `WindowGroup` when the model requests it.
    @Environment(\.openWindow) private var openWindow
    /// Dismisses the Getting Started window when the model requests it.
    @Environment(\.dismissWindow) private var dismissWindow
    /// Currently-selected sidebar section. Defaults to `.today` (a Debug
    /// demo-capture launch can pin a different pane via `demoLaunchSelection`);
    /// SwiftUI restores the last selection between window appearances.
    @State private var selectedSection: MainWorkspaceSection = .demoLaunchSelection
    /// Sidebar visibility — kept .all so the floating glass sidebar is always
    /// shown on launch. The user can still dismiss it with the toolbar toggle.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(MainWorkspaceSection.allCases, selection: $selectedSection) { section in
                Label(section.title, systemImage: section.symbolName)
                    .font(CurfewTypography.bodyEmphasis(15))
                    .tag(section)
                    .padding(.vertical, 6)
            }
            .navigationTitle("Curfew")
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            // One consistent adaptive surface so the sidebar harmonises with the
            // canvas detail in both modes, instead of rendering a light glass slab
            // beside a dark page (the "sudden colour change" seam).
            .background(CurfewTheme.canvasStrong.ignoresSafeArea())
            .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 340)
        } detail: {
            // Each destination owns its own background now — Today's composed sky
            // hero, a calm opaque canvas on Schedule/Journal. No global stretched
            // sky behind everything (that was doubling the per-destination sky and
            // distorting to fill the window).
            detailContent
                .id(selectedSection)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.28), value: selectedSection)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .tint(CurfewTheme.accent)
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
        // Bridge the model's onboarding triggers to the SwiftUI scene graph.
        // `showGettingStarted()` / `dismissGettingStarted()` bump these
        // monotonic counters; opening / dismissing the window is a scene
        // concern, so it lives here rather than in the model.
        .onChange(of: model.gettingStartedRequestID) {
            openWindow(id: CurfewAppModel.gettingStartedWindowID)
        }
        .onChange(of: model.gettingStartedDismissID) {
            dismissWindow(id: CurfewAppModel.gettingStartedWindowID)
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .today:
            TodayView(selectedSection: $selectedSection)
                .environment(model)
        case .schedule:
            ScheduleView()
                .environment(model)
        case .journal:
            JournalView()
                .environment(model)
        }
    }
}
