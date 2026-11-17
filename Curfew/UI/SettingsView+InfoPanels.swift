import CurfewKit
import EventKit
import SwiftUI

extension SettingsView {
    var integrationsPanel: some View {
        Group {
            commandLinePanel
            if CurfewFlavor.current != .development || model.isDemoSession {
                DisclosureGroup(isExpanded: $showsBrowserIntegration) {
                    taskBrowserEnforcementPanel
                } label: {
                    SettingsRowLabel(
                        title: "Chrome and Docket",
                        detail: "Keep Chrome to the websites for your active Docket task."
                    )
                }
            }
            if model.featureFlags.mcpServerEnabled {
                mcpConfigPanel
            }
            if model.featureFlags.widgetKitEnabled {
                PlusGate(feature: "Widgets", description: "See your curfew at a glance.") {
                    SettingsGroup(
                        "Widgets",
                        footer: "Add a Curfew widget from your Mac's widget gallery."
                    ) {
                        EmptyView()
                    }
                }
            }
            if model.featureFlags.calendarEnabled {
                PlusGate(
                    feature: "Calendar",
                    description: "See today's events alongside your curfew."
                ) {
                    SettingsGroup("Calendar") { calendarAuthRow }
                }
            }
        }
    }

    private var mcpConfigPanel: some View {
        @Bindable var model = model
        return SettingsGroup(
            "AI assistants",
            footer: model.settings.mcpEnabled
                ? "Your journal is stored on this Mac. An assistant you connect can receive "
                + "its contents, so only connect assistants you trust."
                : nil
        ) {
            SettingsToggleRow(
                title: "Allow assistants on this Mac",
                detail: Self.localAIExplanation,
                identifier: "assistant-enabled",
                isOn: $model.settings.mcpEnabled
            )
            DisclosureGroup(isExpanded: $showsAIPermissions) {
                Text(Self.localAIAuthorityDetails)
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
            } label: {
                SettingsRowLabel(title: "Data access and shutdown requests")
            }
            if model.settings.mcpEnabled {
                SettingsPickerRow(
                    title: "Changes",
                    detail: model.aiConsentPolicy.rationale,
                    selection: $model.aiConsentPolicy,
                    identifier: "assistant-policy"
                ) {
                    ForEach(AIConsentPolicy.allCases, id: \.self) { policy in
                        Text(policy.displayName).tag(policy)
                    }
                }
                claudeDesktopRegisterButton
                manualSetupRow
            }
            if !model.pendingMCPRequests.isEmpty {
                SettingsActionRow(
                    title: "Awaiting approval",
                    detail: model.pendingMCPRequests.count == 1
                        ? "1 request" : "\(model.pendingMCPRequests.count) requests",
                    actionTitle: "Review request…",
                    identifier: "review-ai-request"
                ) {
                    openWindow(id: MainWorkspaceSection.windowID)
                    model.requestWorkspaceNavigation(to: .today)
                }
            }
        }
    }

    @ViewBuilder
    private var manualSetupRow: some View {
        Button {
            manualSetupExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: manualSetupExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CurfewTheme.mutedInk)
                    .accessibilityHidden(true)
                SettingsRowLabel(title: "Manual setup")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("manual-assistant-setup")
        .accessibilityValue(manualSetupExpanded ? "Expanded" : "Collapsed")
        if manualSetupExpanded {
            SettingsActionRow(
                title: "Assistant configuration",
                detail: "Add the bundled curfew-mcp server to your assistant's MCP configuration.",
                actionTitle: didCopyConfig ? "Copied" : "Copy configuration",
                identifier: "copy-assistant-config"
            ) {
                copyClaudeDesktopConfig()
                didCopyConfig = true
            }
        }
    }

    @ViewBuilder
    private var calendarAuthRow: some View {
        switch model.calendarMonitor.authorizationStatus {
        case .fullAccess:
            let count = model.calendarMonitor.todayEvents.count
            SettingsActionRow(
                title: "Today's events",
                detail: count == 1 ? "1 event" : "\(count) events",
                actionTitle: nil
            )
        case .notDetermined:
            SettingsActionRow(
                title: "Calendar access",
                detail: "Curfew reads today's events to show them beside your curfew.",
                actionTitle: "Allow calendar access…"
            ) {
                if !model.isDemoSession {
                    model.calendarMonitor.requestAccessAndSync()
                }
            }
        default:
            SettingsActionRow(
                title: "Calendar access",
                detail: "Curfew needs full Calendar access to read events.",
                tone: .warning,
                actionTitle: "Open Calendar settings"
            ) {
                if !model.isDemoSession,
                   let url = URL(
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
                SettingsGroup("iCloud sync") { syncStatusRow }
            }
        }
    }

    @ViewBuilder
    private var syncStatusRow: some View {
        switch model.cloudKitSyncEngine.syncStatus {
        case .idle:
            SettingsActionRow(title: "iCloud sync", detail: "Ready to sync", actionTitle: nil)
        case .syncing:
            SettingsActionRow(title: "iCloud sync", detail: "Syncing…", actionTitle: nil)
        case .synced(let date):
            SettingsActionRow(
                title: "iCloud sync",
                detail: "Last synced \(date.formatted(.relative(presentation: .named)))",
                actionTitle: nil
            )
        case .failed(let message):
            SettingsActionRow(
                title: "Couldn't sync your schedule.",
                detail: message,
                tone: .warning,
                actionTitle: nil
            )
        case .unavailable:
            SettingsActionRow(
                title: "iCloud sync",
                detail: "Sign in to iCloud in System Settings to sync your schedule.",
                actionTitle: nil
            )
        }
    }

    var licensePanel: some View {
        LicenseView().environment(model)
    }
}
