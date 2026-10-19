import CurfewKit
import EventKit
import SwiftUI

extension SettingsView {
    var integrationsPanel: some View {
        Group {
            coordinatorSyncPanel
            if CurfewFlavor.current != .development || model.isDemoSession {
                taskBrowserEnforcementPanel
            }
            if model.featureFlags.mcpServerEnabled {
                mcpConfigPanel
            }
            if model.featureFlags.widgetKitEnabled {
                PlusGate(feature: "Widgets", description: "See your curfew at a glance.") {
                    Section("Widgets") {
                        Text("Add a Curfew widget from your Mac's widget gallery.")
                            .foregroundStyle(CurfewTheme.mutedInk)
                    }
                }
            }
            if model.featureFlags.calendarEnabled {
                PlusGate(
                    feature: "Calendar",
                    description: "See today's events alongside your curfew."
                ) {
                    Section("Calendar") { calendarAuthRow }
                }
            }
            if model.featureFlags.cloudSyncEnabled, !model.settings.accountSync.isEnrolled {
                devicesPanel
            }
        }
    }

    private var mcpConfigPanel: some View {
        @Bindable var model = model
        return Section {
            Toggle("Allow assistants on this Mac", isOn: $model.settings.mcpEnabled)
                .accessibilityIdentifier("assistant-enabled")
            Text("Connected assistants can read your status, schedule, activity, and reflections.")
                .foregroundStyle(CurfewTheme.mutedInk)
            if model.settings.mcpEnabled {
                Picker("Changes", selection: $model.aiConsentPolicy) {
                    ForEach(AIConsentPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("assistant-policy")
                Text(model.aiConsentPolicy.rationale).foregroundStyle(CurfewTheme.mutedInk)
                claudeDesktopRegisterButton
                VStack(alignment: .leading, spacing: 10) {
                    Button {
                        manualSetupExpanded.toggle()
                    } label: {
                        Label(
                            "Manual setup",
                            systemImage: manualSetupExpanded ? "chevron.down" : "chevron.right"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("manual-assistant-setup")
                    .accessibilityValue(manualSetupExpanded ? "Expanded" : "Collapsed")
                    if manualSetupExpanded {
                        Text(
                            "Add the bundled curfew-mcp server "
                                + "to your assistant's MCP configuration."
                        )
                        .foregroundStyle(CurfewTheme.mutedInk)
                        Button(didCopyConfig ? "Copied" : "Copy Configuration") {
                            copyClaudeDesktopConfig()
                            didCopyConfig = true
                        }
                        .accessibilityIdentifier("copy-assistant-config")
                    }
                }
            }
            if !model.pendingMCPRequests.isEmpty {
                LabeledContent("Awaiting approval", value: "\(model.pendingMCPRequests.count)")
                Button("Review Request…") {
                    openWindow(id: MainWorkspaceSection.windowID)
                    model.requestWorkspaceNavigation(to: .today)
                }
                .accessibilityIdentifier("review-ai-request")
            }
        } header: {
            Text("AI assistants")
        } footer: {
            if model.settings.mcpEnabled {
                Text("Your journal is stored on this Mac. An assistant you connect can receive "
                    + "its contents, so only connect assistants you trust.")
            }
        }
    }

    @ViewBuilder
    private var calendarAuthRow: some View {
        switch model.calendarMonitor.authorizationStatus {
        case .fullAccess:
            let count = model.calendarMonitor.todayEvents.count
            LabeledContent("Today's events", value: count == 1 ? "1 event" : "\(count) events")
        case .notDetermined:
            Button("Allow Calendar Access…") {
                if !model.isDemoSession {
                    model.calendarMonitor.requestAccessAndSync()
                }
            }
        default:
            Text("Calendar access is off.").foregroundStyle(CurfewTheme.mutedInk)
            Button("Open Calendar Settings") {
                if !model.isDemoSession,
                   let url =
                   URL(
                       string: "x-apple.systempreferences:com.apple.preference.security"
                           + "?Privacy_Calendars"
                   ) {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    private func copyClaudeDesktopConfig() {
        let path = Bundle.main.bundlePath + "/Contents/Resources/curfew-mcp"
        let object: [String: Any] = ["mcpServers": [ClaudeDesktopRegistration.serverKey: [
            "command": path, "args": [String]()
        ]]]
        guard let data = try? JSONSerialization.data(
            withJSONObject: object,
            options: .prettyPrinted
        ),
            let config = String(data: data, encoding: .utf8) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(config, forType: .string)
    }

    var devicesPanel: some View {
        Group {
            devicesListPanel
            PlusGate(feature: "iCloud sync", description: "Sync your schedule across your Macs.") {
                Section("iCloud sync") { syncStatusRow }
            }
        }
    }

    @ViewBuilder
    private var syncStatusRow: some View {
        switch model.cloudKitSyncEngine.syncStatus {
        case .idle:
            Text("Ready to sync").foregroundStyle(CurfewTheme.mutedInk)
        case .syncing:
            HStack { ProgressView().controlSize(.small); Text("Syncing…") }
        case .synced(let date):
            LabeledContent("Last synced") { Text(date, style: .relative) }
        case .failed(let message):
            Text("Couldn't sync your schedule.").foregroundStyle(CurfewTheme.warning)
            DisclosureGroup("Details") { Text(message).textSelection(.enabled) }
        case .unavailable:
            Text("Sign in to iCloud in System Settings to sync your schedule.")
                .foregroundStyle(CurfewTheme.mutedInk)
        }
    }

    var licensePanel: some View {
        LicenseView().environment(model)
    }
}
