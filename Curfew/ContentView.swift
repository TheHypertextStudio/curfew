import AppKit
import CurfewAtmosphere
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
        case .today: HorizonSymbol.today.systemName
        case .schedule: HorizonSymbol.schedule.systemName
        case .journal: HorizonSymbol.journal.systemName
        }
    }

    /// ⌘1, ⌘2 and ⌘3 move between the sections.
    var shortcut: KeyEquivalent {
        switch self {
        case .today: "1"
        case .schedule: "2"
        case .journal: "3"
        }
    }
}

/// The menu bar popover: the same sky, countdown, one thing and two actions
/// as Today, then Open Curfew, Settings and Quit. Quit is hidden while locked.
struct ContentView: View {
    @Environment(CurfewAppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    /// Height of the sky, ground included.
    static let skyHeight: CGFloat = 340

    var body: some View {
        VStack(spacing: 0) {
            sky
            CompactEnforcementHealthWarning(health: model.presentedEnforcementHealth) {
                model.requestAccessibilityAccess()
            }
            .padding(.horizontal, CurfewSpacing.small)
            .padding(.top, CurfewSpacing.small)
            // Renders only while a capture session is live. The popover is
            // where a user goes when they notice the system's green camera
            // light and want to know which app turned it on.
            CompactCameraLiveIndicator(isLive: model.isPresenceCameraLive) {
                model.openSettings()
            }
            .padding(.horizontal, CurfewSpacing.small)
            .padding(.top, CurfewSpacing.small)
            menu
        }
        .onAppear {
            model.appRouter.registerSettingsOpener { openSettings() }
        }
        .frame(width: 340)
        .background(CurfewTheme.canvas)
        .foregroundStyle(CurfewTheme.ink)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("curfew-menu-popover")
    }

    /// The sky with the countdown and actions above the horizon and the one
    /// thing on the ground, at the popover's scale.
    private var sky: some View {
        let presentation = model.todayPresentation
        let metrics = TodayMetrics.popover
        let skyHeight = Self.skyHeight * (1 - HorizonGeometry.horizon)
        return ZStack(alignment: .top) {
            HorizonSkyView(frame: model.horizonFrame, isDayRunning: model.isHorizonDayRunning)
            VStack(spacing: 0) {
                TodayHero(
                    presentation: presentation, metrics: metrics, horizon: model.horizonFrame,
                    voice: model.voice,
                    holdDuration: CurfewAppModel.extensionConfirmationHoldSeconds,
                    onTurnOn: turnOn,
                    onMoreTime: { model.confirmExtensionRequest() },
                    onCallItADay: { model.callItADay() }
                )
                .padding(.bottom, metrics.actionsToHorizon)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .frame(height: skyHeight)
                Group {
                    if presentation.showsOneThing {
                        OneThingView(
                            oneThing: model.todaysOneThing, size: metrics.oneThing,
                            voice: model.voice,
                            onDone: { model.setOneThingDone($0) },
                            onSave: { model.saveTodaysOneThing($0) }
                        )
                        .accessibilitySortPriority(2)
                    }
                }
                .padding(.top, metrics.horizonToGround)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, CurfewSpacing.large)
        }
        .frame(height: Self.skyHeight)
        .clipped()
        .accessibilityElement(children: .contain)
    }

    private var menu: some View {
        VStack(spacing: 2) {
            menuRow("Open Curfew", symbol: HorizonSymbol.today.systemName) {
                openMainWorkspace()
            }
            menuRow("Settings", symbol: "gearshape") { model.openSettings() }
            if model.allowsQuit {
                Divider().padding(.vertical, CurfewSpacing.xSmall)
                menuRow("Quit Curfew", symbol: "power") { NSApp.terminate(nil) }
            }
        }
        .padding(CurfewSpacing.small)
    }

    private func menuRow(
        _ title: String, symbol: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: CurfewSpacing.medium) {
                Image(systemName: symbol)
                    .frame(width: 20)
                    .foregroundStyle(CurfewTheme.mutedInk)
                Text(title)
                    .foregroundStyle(CurfewTheme.ink)
                Spacer()
            }
            .sundownFont(.strong, size: 14)
            .padding(.horizontal, CurfewSpacing.small)
            .padding(.vertical, CurfewSpacing.small)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func turnOn() {
        if model.settings.hasCompletedInitialSetup {
            model.start()
        } else {
            model.showGettingStarted()
        }
    }

    private func openMainWorkspace() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: MainWorkspaceSection.windowID)
    }
}

/// Main application window. On Today the detail's sky carries
/// `.backgroundExtensionEffect()`, the macOS 26 way to run a detail background
/// behind the floating sidebar: the system sidebar glass, with no extra
/// material, refracts the sky and keeps its own labels and selection legible.
/// On Schedule and Journal the sidebar sits on the opaque adaptive canvas.
struct MainWindowView: View {
    /// Live app state shared across detail panes.
    @Environment(CurfewAppModel.self) private var model
    /// Presents the initial surface for unsigned demo captures.
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    /// Currently-selected sidebar section. Defaults to `.today` (a Debug
    /// demo-capture launch can pin a different pane via `demoLaunchSelection`);
    /// SwiftUI restores the last selection between window appearances.
    @State private var selectedSection: MainWorkspaceSection = .demoLaunchSelection
    /// Sidebar visibility — kept .all so the floating glass sidebar is always
    /// shown on launch. The user can still dismiss it with the toolbar toggle.
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    private var showsSky: Bool {
        selectedSection == .today
    }

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
            // Off Today the sidebar is one opaque adaptive surface, as before.
            // On Today it is only the system glass, over the sky the detail
            // extends beneath it; no custom material sits under it, so nothing
            // from behind the window can show through the selected row.
            .background {
                if !showsSky {
                    CurfewTheme.canvasStrong.ignoresSafeArea()
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 248, max: 340)
        } detail: {
            // Each destination owns its own background now — Today's composed sky
            // hero, a calm opaque canvas on Schedule/Journal. No global stretched
            // sky behind everything (that was doubling the per-destination sky and
            // distorting to fill the window).
            detailContent
                .id(selectedSection)
                .focusedSceneValue(\.workspaceSection, $selectedSection)
                .transition(.opacity)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.easeInOut(duration: 0.28), value: selectedSection)
        }
        .navigationSplitViewStyle(.prominentDetail)
        .background(WorkspaceNativeRegionReader(selectedTitle: selectedSection.title)
            .frame(width: 0, height: 0))
        .tint(CurfewTheme.accent)
        .task {
            #if DEBUG
                if model.isDemoSession,
                   let scenario = CurfewLaunchBehavior
                       .demoScenario(environment: ProcessInfo.processInfo.environment) {
                    if scenario == .settings {
                        openSettings()
                    }
                    if scenario ==
                        .gettingStarted {
                        openWindow(id: CurfewAppModel.gettingStartedWindowID)
                    }
                }
            #endif
        }
        .sheet(item: Binding(
            get: { model.pendingMCPRequests.first },
            set: { newValue in
                // SwiftUI calls this with `nil` on an interactive dismissal
                // (Escape, click outside). A no-op setter here used to
                // silently swallow that *and*, since the item never left
                // `pendingMCPRequests`, block every subsequent MCP request
                // from ever being shown until this one was explicitly
                // Approved/Denied via a button. Route the dismissal through
                // the same deny path "Deny" uses, so both close together.
                guard newValue == nil,
                      let dismissed = model.pendingMCPRequests.first else { return }
                model.denyMCPRequest(dismissed, reason: "Dismissed without a decision.")
            }
        )) { request in
            MCPConsentSheet(
                request: request,
                presentation: ConsentPresentation(
                    request: request,
                    schedule: model.settings.schedule,
                    extensionMinutes: model.settings.extensionDurationMinutes,
                    canRequestExtension: model.state.canRequestExtension,
                    extensionsRemaining: model.extensionsRemaining,
                    pendingScheduleChange: model.settings.pendingScheduleChange
                ),
                onApprove: { model.approveMCPRequest(request) },
                onDeny: { model.denyMCPRequest(request) }
            )
        }
        .onAppear {
            model.appRouter.registerSettingsOpener { openSettings() }
        }
        // Bridges `requestWorkspaceNavigation(to:)` (e.g. Getting Started's
        // "Open Schedule" step) into this window's own sidebar selection.
        .onChange(of: model.requestedWorkspaceSection, initial: true) { _, requested in
            guard let requested else { return }
            selectedSection = requested
            model.requestedWorkspaceSection = nil
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        switch selectedSection {
        case .today:
            TodayView()
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

extension FocusedValues {
    /// The main window's selected section, for the ⌘1 to ⌘3 commands.
    @Entry var workspaceSection: Binding<MainWorkspaceSection>?
}
