import CurfewKit
import SwiftUI

extension SettingsView {
    var advancedPanel: some View {
        @Bindable var model = model
        return Section {
            Toggle("Local HTTP server", isOn: $model.settings.mcpHTTPEnabled)
            if model.settings.mcpHTTPEnabled {
                LabeledContent("Port") {
                    TextField("9847", value: $model.settings.mcpHTTPPort, format: .number)
                        .frame(width: 80)
                }
                Text("Restart Curfew to apply changes.").foregroundStyle(CurfewTheme.mutedInk)
            }
            DisclosureGroup("Technical details") {
                Text("For MCP clients that cannot launch the bundled stdio server. "
                    + "Listens on 127.0.0.1 only; other devices cannot connect.")
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
        } header: {
            Text("Assistant diagnostics")
        } footer: {
            Text("Most assistants do not need this.")
        }
    }

    @ViewBuilder
    var setupPanel: some View {
        if !model.settings.hasCompletedInitialSetup {
            Section("Setup") {
                Text("Finish setup before Curfew can enforce your schedule.")
                    .foregroundStyle(CurfewTheme.mutedInk)
            }
        }
    }
}
