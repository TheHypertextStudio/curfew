import SwiftUI

nonisolated enum TaskBrowserPanelCopy {
    static let title = "Task Browser Enforcement"
    static let connectAction = "Connect Docket"
    static let breakAction = "Take 15-minute break"
    static let mappingAction = "Add destination"
    static let selectorKinds = ["Task", "Project", "Label"]
    static let scopeKinds = ["Origin", "Path prefix"]

    static func availabilityMessage(for flavor: CurfewFlavor) -> String? {
        flavor == .studioDevelopment
            ? "Chrome task-browser enforcement is unavailable in this Studio Dev build."
            : nil
    }
}

extension SettingsView {
    var taskBrowserEnforcementPanel: some View {
        TaskBrowserEnforcementPanel(controller: model.taskBrowserEnforcement)
    }
}

private struct TaskBrowserEnforcementPanel: View {
    @ObservedObject var controller: TaskBrowserEnforcementController
    @State private var selectorKind = SelectorKind.task
    @State private var selectorID = ""
    @State private var destination = ""
    @State private var scopeKind = BrowserDestinationScope.Kind.origin

    var body: some View {
        CurfewPanel {
            if let unavailable = TaskBrowserPanelCopy.availabilityMessage(for: .current) {
                CurfewSectionTitle(title: TaskBrowserPanelCopy.title, subtitle: unavailable)
            } else {
                CurfewSectionTitle(
                    title: TaskBrowserPanelCopy.title,
                    subtitle: "Limit Chrome to destinations that match the work active in Docket."
                )

                connectionControls
                statusRows
                Divider()
                enforcementControls
                Divider()
                mappingControls
            }
        }
        .accessibilityIdentifier("task-browser-enforcement-panel")
        .task {
            if CurfewFlavor.current != .studioDevelopment {
                controller.refresh()
            }
        }
    }

    private var connectionControls: some View {
        HStack(spacing: CurfewSpacing.medium) {
            Button(connectionActionTitle) {
                Task {
                    if controller.viewModel.docketAuthorization.isHealthy {
                        try? await controller.disconnect()
                    } else {
                        try? await controller.connect()
                    }
                }
            }
            .buttonStyle(CurfewSecondaryButtonStyle())
            .accessibilityIdentifier("task-browser-connect-button")

            if let errorMessage = controller.errorMessage {
                Text(errorMessage)
                    .font(CurfewTypography.body(13))
                    .foregroundStyle(Color.red.opacity(0.8))
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
        Toggle(
            "Enforce Chrome for active Docket work",
            isOn: Binding(
                get: { controller.viewModel.enforcementEnabled },
                set: { _ = controller.setEnforcementEnabled($0) }
            )
        )
        .disabled(!controller.viewModel.canToggleEnforcement)
        .accessibilityIdentifier("task-browser-enforcement-toggle")

        if let title = controller.viewModel.activeTaskTitle {
            LabeledContent("Active task") {
                Text(title)
                    .font(CurfewTypography.bodyEmphasis(13))
            }
        } else {
            Text("Docket has no retained active work session.")
                .font(CurfewTypography.body(13))
                .foregroundStyle(CurfewTheme.mutedInk)
        }

        if let breakEndsAt = controller.viewModel.breakEndsAt {
            LabeledContent("Break ends") {
                Text(breakEndsAt, style: .time)
                    .font(CurfewTypography.bodyEmphasis(13))
            }
        }

        Button(TaskBrowserPanelCopy.breakAction) {
            controller.beginBreak()
        }
        .buttonStyle(CurfewSecondaryButtonStyle())
        .disabled(!controller.viewModel.canBeginBreak)
        .accessibilityIdentifier("task-browser-break-button")
    }

    private var mappingControls: some View {
        VStack(alignment: .leading, spacing: CurfewSpacing.medium) {
            CurfewSectionTitle(
                title: "Allowed destinations",
                subtitle: "Map one Docket task, project, or label to an exact web scope."
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
                .foregroundStyle(status.isHealthy ? Color.green : CurfewTheme.warning)
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
