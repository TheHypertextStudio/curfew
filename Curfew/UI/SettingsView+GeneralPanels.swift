import CurfewKit
import SwiftUI

extension SettingsView {
    @ViewBuilder
    var advancedPanel: some View {
        if SettingsDeveloperDetail.isVisible {
            assistantDiagnosticsPanel
        }
    }

    private var assistantDiagnosticsPanel: some View {
        @Bindable var model = model
        return SettingsGroup("Assistant diagnostics", footer: "Most assistants don't need this.") {
            SettingsToggleRow(
                title: "Local HTTP server",
                detail: "For MCP clients that can't launch the bundled server. "
                    + "Listens on 127.0.0.1 only.",
                isOn: $model.settings.mcpHTTPEnabled
            )
            if model.settings.mcpHTTPEnabled {
                SettingsRow(title: "Port", detail: "Restart Curfew to apply a change.") {
                    TextField("9847", value: $model.settings.mcpHTTPPort, format: .number)
                        .labelsHidden()
                        .frame(width: 80)
                }
            }
        }
    }

    @ViewBuilder
    var setupPanel: some View {
        if !model.settings.hasCompletedInitialSetup {
            SettingsGroup("Setup") {
                SettingsActionRow(
                    title: "Setup isn't finished",
                    detail: "Finish setup and Curfew starts keeping your schedule.",
                    actionTitle: nil
                )
            }
        }
    }
}
