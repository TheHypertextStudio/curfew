import CurfewKit
import SwiftUI

nonisolated enum TaskBrowserPanelCopy {
    static let title = "Websites during work"
    static let connectAction = "Connect Docket"
    static let breakAction = "Take 15-minute break"
    static let mappingAction = "Add destination"
    static let selectorKinds = ["Task", "Project", "Label"]
    static let scopeKinds = ["Origin", "Path prefix"]

    static func availabilityMessage(for flavor: CurfewFlavor) -> String? {
        flavor == .development
            ? "Websites during work isn't available in this build."
            : nil
    }
}

extension SettingsView {
    var taskBrowserEnforcementPanel: some View {
        TaskBrowserEnforcementPanel(controller: model.taskBrowserEnforcement)
    }
}

private struct TaskBrowserEnforcementPanel: View {
    @Environment(CurfewAppModel.self) private var model
    @ObservedObject var controller: TaskBrowserEnforcementController
    @State private var selectorKind = SelectorKind.task
    @State private var selectorID = ""
    @State private var mappingsExpanded = false
    @State private var destination = ""
    @State private var scopeKind = BrowserDestinationScope.Kind.origin

    var body: some View {
        Section {
            if let unavailable = TaskBrowserPanelCopy.availabilityMessage(for: .current),
               !model.isDemoSession {
                SettingsActionRow(title: "Docket", detail: unavailable, actionTitle: nil)
            } else {
                connectionControls
                if SettingsDeveloperDetail.isVisible {
                    DisclosureGroup("Connection details") {
                        statusRows
                    }
                }
                enforcementControls
                if SettingsDeveloperDetail.isVisible {
                    destinationsEditor
                }
            }
        } header: {
            Text(TaskBrowserPanelCopy.title)
                .accessibilityIdentifier("task-browser-enforcement-panel")
        }
        .task {
            if CurfewFlavor.current != .development || model.isDemoSession {
                controller.refresh()
            }
        }
    }

    /// The ID-based destination editor is a diagnostic tool: it needs raw
    /// Docket identifiers, so it only appears with developer detail.
    @ViewBuilder
    private var destinationsEditor: some View {
        Button {
            mappingsExpanded.toggle()
        } label: {
            Label(
                "Allowed destinations",
                systemImage:
                mappingsExpanded ? "chevron.down" : "chevron.right"
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("task-browser-destinations-disclosure")
        .accessibilityValue(mappingsExpanded ? "Expanded" : "Collapsed")
        if mappingsExpanded {
            mappingControls
        }
    }

    private var connectionControls: some View {
        SettingsActionRow(
            title: "Docket",
            detail: controller.errorMessage ?? controller.viewModel.statusSummary,
            tone: controller.errorMessage == nil ? .secondary : .warning,
            actionTitle: connectionActionTitle,
            identifier: "task-browser-connect-button"
        ) {
            Task {
                if controller.viewModel.docketAuthorization.isHealthy {
                    try? await controller.disconnect()
                } else {
                    try? await controller.connect()
                }
            }
        }
    }

    private var statusRows: some View {
        VStack(spacing: CurfewSpacing.small) {
            statusRow("Docket authorization", status: controller.viewModel.docketAuthorization)
            statusRow("Last successful Docket poll", status: controller.viewModel.docketPoll)
            statusRow("Chrome extension heartbeat", status: controller.viewModel.extensionHeartbeat)
            statusRow("Native host", status: controller.viewModel.nativeHost)
            statusRow("Enforcement", status: controller.viewModel.enforcementReadiness)
        }
    }

    @ViewBuilder
    private var enforcementControls: some View {
        SettingsToggleRow(
            title: "Limit Chrome during work",
            detail: activeWorkDetail,
            identifier: "task-browser-enforcement-toggle",
            isOn: Binding(
                get: { controller.viewModel.enforcementEnabled },
                set: { _ = controller.setEnforcementEnabled($0) }
            )
        )
        .disabled(!controller.viewModel.canToggleEnforcement)

        SettingsActionRow(
            title: "Break",
            detail: controller.viewModel.breakEndsAt.map {
                "Ends at \($0.formatted(date: .omitted, time: .shortened))"
            } ?? "Chrome opens up for 15 minutes.",
            actionTitle: TaskBrowserPanelCopy.breakAction,
            identifier: "task-browser-break-button"
        ) {
            controller.beginBreak()
        }
        .disabled(!controller.viewModel.canBeginBreak)
    }

    /// The active Docket task, or that there is none, under the switch.
    private var activeWorkDetail: String {
        if let title = controller.viewModel.activeTaskTitle {
            return "Active task: \(title)"
        }
        return "Curfew has no current work session from Docket."
    }

    private var mappingControls: some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.medium) {
            CurfewSectionTitle(
                title: "Allowed destinations",
                subtitle: "Allow a website or URL path for a Docket task, project, or label."
            )

            ForEach(controller.settings.mappings) { mapping in
                mappingRow(mapping)
            }

            HStack(spacing: CurfewSpacing.small) {
                Picker("Selector", selection: $selectorKind) {
                    ForEach(SelectorKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .frame(width: 130)

                TextField("Selector ID", text: $selectorID)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("task-browser-selector-id")
            }

            HStack(spacing: CurfewSpacing.small) {
                Picker("Scope", selection: $scopeKind) {
                    Text("Origin").tag(BrowserDestinationScope.Kind.origin)
                    Text("Path prefix").tag(BrowserDestinationScope.Kind.pathPrefix)
                }
                .frame(width: 130)

                TextField("https://example.com or https://example.com/path", text: $destination)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("task-browser-destination")

                Button(TaskBrowserPanelCopy.mappingAction) {
                    addMapping()
                }
                .buttonStyle(CurfewSecondaryButtonStyle())
                .disabled(selectorID.isEmpty || destination.isEmpty)
                .accessibilityIdentifier("task-browser-add-mapping")
            }
        }
    }

    private var connectionActionTitle: String {
        controller.viewModel.docketAuthorization.isHealthy
            ? "Disconnect Docket"
            : TaskBrowserPanelCopy.connectAction
    }

    private func statusRow(
        _ title: String,
        status: TaskBrowserIntegrationStatus
    ) -> some View {
        HStack(spacing: CurfewSpacing.small) {
            Image(systemName: status.isHealthy ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(status.isHealthy ? CurfewTheme.accent : CurfewTheme.warning)
                .accessibilityHidden(true)
            Text(title)
                .font(CurfewTypography.body(13))
            Spacer()
            Text(status.detail)
                .font(CurfewTypography.bodyEmphasis(13))
                .foregroundStyle(status.isHealthy ? CurfewTheme.ink : CurfewTheme.mutedInk)
        }
    }

    private func mappingRow(_ mapping: WorkDestinationMapping) -> some View {
        HStack(spacing: CurfewSpacing.small) {
            VStack(alignment: .leading, spacing: 2) {
                Text(mapping.hostLabel)
                    .font(CurfewTypography.bodyEmphasis(13))
                Text(mapping.detailLabel)
                    .font(CurfewTypography.body(12))
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
            Spacer()
            Button("Remove", systemImage: "trash") {
                controller.removeMapping(id: mapping.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(mapping.hostLabel)")
        }
    }

    private func addMapping() {
        do {
            _ = try controller.addMapping(
                selector: selectorKind.selector(id: selectorID),
                destination: destination,
                scopeKind: scopeKind
            )
            selectorID = ""
            destination = ""
        } catch {
            return
        }
    }
}

private enum SelectorKind: String, CaseIterable, Identifiable {
    case task
    case project
    case label

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .task: "Task"
        case .project: "Project"
        case .label: "Label"
        }
    }

    func selector(id: String) -> WorkDestinationSelector {
        switch self {
        case .task: .task(id)
        case .project: .project(id)
        case .label: .label(id)
        }
    }
}

private extension WorkDestinationMapping {
    var hostLabel: String {
        URL(string: scope.origin)?.host ?? scope.origin
    }

    var detailLabel: String {
        let selectorLabel = switch selector {
        case .task(let id): "Task \(id)"
        case .project(let id): "Project \(id)"
        case .label(let id): "Label \(id)"
        }
        let scopeLabel = scope.path.map { scope.origin + $0 } ?? scope.origin
        return "\(selectorLabel) · \(scopeLabel)"
    }
}
