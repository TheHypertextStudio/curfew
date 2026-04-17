import AppKit
import SwiftUI

enum MainWorkspaceSection: String, CaseIterable, Identifiable {
    case overview
    case configuration
    case onboarding

    static let windowID = "main-workspace"

    var id: String {
        rawValue
    }

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

struct ContentView: View {
    @EnvironmentObject private var model: CurfewAppModel
    @Environment(\.openWindow) private var openWindow

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

struct MainWindowView: View {
    @EnvironmentObject private var model: CurfewAppModel
    @State private var selectedSection: MainWorkspaceSection? = .overview

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

private struct MainOverviewSectionView: View {
    @EnvironmentObject private var model: CurfewAppModel

    var body: some View {
        let snapshot = model.snapshot

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
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

private struct MainConfigurationSectionView: View {
    @EnvironmentObject private var model: CurfewAppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CurfewSectionTitle(
                title: "Configuration",
                subtitle: "Schedule, warnings, extensions, overrides, and shutdown behavior"
            )
            .padding(.horizontal, 24)
            .padding(.top, 24)

            SettingsView()
                .environmentObject(model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MainOnboardingSectionView: View {
    @EnvironmentObject private var model: CurfewAppModel

    var body: some View {
        ScrollView {
            CurfewPanel {
                CurfewSectionTitle(
                    title: "Getting Started",
                    subtitle: "Set your schedule first, then arm enforcement when you are ready."
                )

                VStack(alignment: .leading, spacing: 8) {
                    Label("Choose lock and unlock times for each day.", systemImage: "calendar")
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
